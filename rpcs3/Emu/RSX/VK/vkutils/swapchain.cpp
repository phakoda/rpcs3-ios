#include "stdafx.h"
#include "swapchain.h"
#include "Emu/RSX/Common/presentation_policy.h"

#include <array>

namespace vk
{
	// Swapchain image RPCS3
	swapchain_image_RPCS3::swapchain_image_RPCS3(render_device& dev, const memory_type_mapping& memory_map, u32 width, u32 height)
		:image(dev, memory_map.device_local, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, VK_IMAGE_TYPE_2D, VK_FORMAT_B8G8R8A8_UNORM, width, height, 1, 1, 1,
			VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_TILING_OPTIMAL,
			VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, 0, VMM_ALLOCATION_POOL_SWAPCHAIN)
	{
		m_width = width;
		m_height = height;
		current_layout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;

		m_dma_buffer = std::make_unique<buffer>(dev, m_width * m_height * 4, memory_map.host_visible_coherent,
			VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT, VK_BUFFER_USAGE_TRANSFER_DST_BIT, 0, VMM_ALLOCATION_POOL_SWAPCHAIN);
	}

	void swapchain_image_RPCS3::do_dma_transfer(command_buffer& cmd)
	{
		VkBufferImageCopy copyRegion = {};
		copyRegion.bufferOffset = 0;
		copyRegion.bufferRowLength = m_width;
		copyRegion.bufferImageHeight = m_height;
		copyRegion.imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 };
		copyRegion.imageOffset = {};
		copyRegion.imageExtent = { m_width, m_height, 1 };

		change_layout(cmd, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
		vkCmdCopyImageToBuffer(cmd, value, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, m_dma_buffer->value, 1, &copyRegion);
		change_layout(cmd, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
	}

	u32 swapchain_image_RPCS3::get_required_memory_size() const
	{
		return m_width * m_height * 4;
	}

	void* swapchain_image_RPCS3::get_pixels()
	{
		return m_dma_buffer->map(0, VK_WHOLE_SIZE);
	}

	void swapchain_image_RPCS3::free_pixels()
	{
		m_dma_buffer->unmap();
	}

	// swapchain BASE
	swapchain_base::swapchain_base(physical_device& gpu, u32 present_queue, u32 graphics_queue, u32 transfer_queue, VkFormat format)
	{
		dev.create(gpu, graphics_queue, present_queue, transfer_queue);
		m_surface_format = format;
	}

	// NATIVE swapchain base
	VkResult native_swapchain_base::acquire_next_swapchain_image(VkSemaphore /*semaphore*/, u64 /*timeout*/, u32* result)
	{
		u32 index = 0;
		for (auto& p : swapchain_images)
		{
			if (!p.first)
			{
				p.first = true;
				*result = index;
				return VK_SUCCESS;
			}

			++index;
		}

		return VK_NOT_READY;
	}

	void native_swapchain_base::init_swapchain_images(render_device& dev, u32 preferred_count)
	{
		swapchain_images.resize(preferred_count);
		for (auto& img : swapchain_images)
		{
			img.second = std::make_unique<swapchain_image_RPCS3>(dev, dev.get_memory_mapping(), m_width, m_height);
			img.first = false;
		}
	}

	// WSI implementation
	void swapchain_WSI::init_swapchain_images(render_device& dev, u32 /*preferred_count*/)
	{
		std::vector<VkImage> vk_images;
		CHECK_RESULT(rsx::presentation::enumerate<VkImage>(
			[&](u32* count, VkImage* images) { return _vkGetSwapchainImagesKHR(dev, m_vk_swapchain, count, images); },
			vk_images, VK_SUCCESS, VK_INCOMPLETE));

		if (vk_images.empty()) fmt::throw_exception("Driver returned 0 images for swapchain");

		swapchain_images.resize(vk_images.size());
		for (u32 i = 0; i < vk_images.size(); ++i)
		{
			swapchain_images[i].value = vk_images[i];
		}
	}

	swapchain_WSI::swapchain_WSI(vk::physical_device& gpu, u32 present_queue, u32 graphics_queue, u32 transfer_queue, VkFormat format, VkSurfaceKHR surface, VkColorSpaceKHR color_space, bool force_wm_reporting_off)
		: WSI_swapchain_base(gpu, present_queue, graphics_queue, transfer_queue, format)
	{
		_vkCreateSwapchainKHR = reinterpret_cast<PFN_vkCreateSwapchainKHR>(vkGetDeviceProcAddr(dev, "vkCreateSwapchainKHR"));
		_vkDestroySwapchainKHR = reinterpret_cast<PFN_vkDestroySwapchainKHR>(vkGetDeviceProcAddr(dev, "vkDestroySwapchainKHR"));
		_vkGetSwapchainImagesKHR = reinterpret_cast<PFN_vkGetSwapchainImagesKHR>(vkGetDeviceProcAddr(dev, "vkGetSwapchainImagesKHR"));
		_vkAcquireNextImageKHR = reinterpret_cast<PFN_vkAcquireNextImageKHR>(vkGetDeviceProcAddr(dev, "vkAcquireNextImageKHR"));
		_vkQueuePresentKHR = reinterpret_cast<PFN_vkQueuePresentKHR>(vkGetDeviceProcAddr(dev, "vkQueuePresentKHR"));

		m_surface = surface;
		m_color_space = color_space;

		if (!force_wm_reporting_off)
		{
			switch (gpu.get_driver_vendor())
			{
			case driver_vendor::AMD:
			case driver_vendor::INTEL:
			case driver_vendor::RADV:
			case driver_vendor::MVK:
				break;
			case driver_vendor::ANV:
			case driver_vendor::NVIDIA:
				m_wm_reports_flag = true;
				break;
			default:
				break;
			}
		}
	}

	void swapchain_WSI::destroy(bool)
	{
		if (VkDevice pdev = dev)
		{
			if (m_vk_swapchain)
			{
				_vkDestroySwapchainKHR(pdev, m_vk_swapchain, nullptr);
				m_vk_swapchain = VK_NULL_HANDLE;
				swapchain_images.clear();
			}

			dev.destroy();
		}
	}

	std::pair<VkSurfaceCapabilitiesKHR, bool> swapchain_WSI::init_surface_capabilities()
	{
#ifdef _WIN32
		if (g_cfg.video.vk.exclusive_fullscreen_mode != vk_exclusive_fs_mode::unspecified && dev.get_surface_capabilities_2_support())
		{
			HMONITOR hmonitor = MonitorFromWindow(window_handle, MONITOR_DEFAULTTOPRIMARY);
			if (hmonitor)
			{
				VkSurfaceCapabilities2KHR pSurfaceCapabilities = {};
				pSurfaceCapabilities.sType = VK_STRUCTURE_TYPE_SURFACE_CAPABILITIES_2_KHR;

				VkPhysicalDeviceSurfaceInfo2KHR pSurfaceInfo = {};
				pSurfaceInfo.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SURFACE_INFO_2_KHR;
				pSurfaceInfo.surface = m_surface;

				VkSurfaceCapabilitiesFullScreenExclusiveEXT full_screen_exclusive_capabilities = {};
				VkSurfaceFullScreenExclusiveWin32InfoEXT full_screen_exclusive_win32_info = {};
				full_screen_exclusive_capabilities.sType = VK_STRUCTURE_TYPE_SURFACE_CAPABILITIES_FULL_SCREEN_EXCLUSIVE_EXT;

				pSurfaceCapabilities.pNext = &full_screen_exclusive_capabilities;

				full_screen_exclusive_win32_info.sType = VK_STRUCTURE_TYPE_SURFACE_FULL_SCREEN_EXCLUSIVE_WIN32_INFO_EXT;
				full_screen_exclusive_win32_info.hmonitor = hmonitor;

				pSurfaceInfo.pNext = &full_screen_exclusive_win32_info;

				auto getPhysicalDeviceSurfaceCapabilities2KHR = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceCapabilities2KHR>(
					vkGetInstanceProcAddr(dev.gpu(), "vkGetPhysicalDeviceSurfaceCapabilities2KHR")
					);
				ensure(getPhysicalDeviceSurfaceCapabilities2KHR);
				CHECK_RESULT(getPhysicalDeviceSurfaceCapabilities2KHR(dev.gpu(), &pSurfaceInfo, &pSurfaceCapabilities));

				return { pSurfaceCapabilities.surfaceCapabilities, !!full_screen_exclusive_capabilities.fullScreenExclusiveSupported };
			}
			else
			{
				rsx_log.warning("Swapchain: failed to get monitor for the window");
			}
		}
#endif
		VkSurfaceCapabilitiesKHR surface_descriptors = {};
		CHECK_RESULT(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(dev.gpu(), m_surface, &surface_descriptors));
		return { surface_descriptors, false };
	}

	bool swapchain_WSI::init()
	{
		if (dev.get_present_queue() == VK_NULL_HANDLE)
		{
			rsx_log.error("Cannot create WSI swapchain without a present queue");
			return false;
		}

		VkSwapchainKHR old_swapchain = m_vk_swapchain;
		vk::physical_device& gpu = const_cast<vk::physical_device&>(dev.gpu());

		auto [surface_descriptors, should_specify_exclusive_full_screen_mode] = init_surface_capabilities();

		const auto extent = rsx::presentation::choose_extent(
			{m_width, m_height},
			{surface_descriptors.currentExtent.width, surface_descriptors.currentExtent.height},
			{surface_descriptors.minImageExtent.width, surface_descriptors.minImageExtent.height},
			{surface_descriptors.maxImageExtent.width, surface_descriptors.maxImageExtent.height});
		if (!extent)
		{
			// A zero extent is normal while the app/window is not drawable.
			return false;
		}

		constexpr VkImageUsageFlags required_usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
		if ((surface_descriptors.supportedUsageFlags & required_usage) != required_usage)
		{
			rsx_log.error("Swapchain: surface does not support required color-attachment and transfer-destination usage");
			return false;
		}

		constexpr std::array<u32, 4> alpha_preference = {
			VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR, VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
			VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR, VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR};
		const auto composite_alpha = rsx::presentation::choose_composite_alpha(
			surface_descriptors.supportedCompositeAlpha, alpha_preference);
		if (!composite_alpha)
		{
			rsx_log.error("Swapchain: surface exposes no supported composite-alpha mode");
			return false;
		}

		std::vector<VkPresentModeKHR> present_modes;
		CHECK_RESULT(rsx::presentation::enumerate<VkPresentModeKHR>(
			[&](u32* count, VkPresentModeKHR* modes) { return vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, m_surface, count, modes); },
			present_modes, VK_SUCCESS, VK_INCOMPLETE));

		VkPresentModeKHR swapchain_present_mode = VK_PRESENT_MODE_FIFO_KHR;
		std::vector<VkPresentModeKHR> preferred_modes;

		switch (g_cfg.video.vsync)
		{
		case vsync_mode::off:
			preferred_modes = { VK_PRESENT_MODE_IMMEDIATE_KHR, VK_PRESENT_MODE_MAILBOX_KHR, VK_PRESENT_MODE_FIFO_RELAXED_KHR };
			break;
		case vsync_mode::adaptive:
			preferred_modes = { VK_PRESENT_MODE_MAILBOX_KHR, VK_PRESENT_MODE_FIFO_RELAXED_KHR };
			break;
		case vsync_mode::full:
		default:
			// FIFO is guaranteed to be supported, no need to go through a preference chain
			preferred_modes = {};
			break;
		}

		bool mode_found = false;
		for (VkPresentModeKHR preferred_mode : preferred_modes)
		{
			//Search for this mode in supported modes
			for (VkPresentModeKHR mode : present_modes)
			{
				if (mode == preferred_mode)
				{
					swapchain_present_mode = mode;
					mode_found = true;
					break;
				}
			}

			if (mode_found)
				break;
		}

		rsx_log.notice("Swapchain: present mode %d in use.", static_cast<int>(swapchain_present_mode));

		const u32 nb_swap_images = rsx::presentation::choose_image_count(
			surface_descriptors.minImageCount, surface_descriptors.maxImageCount);

		VkSurfaceTransformFlagBitsKHR pre_transform = surface_descriptors.currentTransform;
		if (surface_descriptors.supportedTransforms & VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR)
			pre_transform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;

		VkSwapchainCreateInfoKHR swap_info = {};
		swap_info.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
		swap_info.surface = m_surface;
		swap_info.minImageCount = nb_swap_images;
		swap_info.imageFormat = m_surface_format;
		swap_info.imageColorSpace = m_color_space;

		swap_info.imageUsage = required_usage;
		swap_info.preTransform = pre_transform;
		swap_info.compositeAlpha = static_cast<VkCompositeAlphaFlagBitsKHR>(*composite_alpha);
		swap_info.imageArrayLayers = 1;
		swap_info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
		swap_info.presentMode = swapchain_present_mode;
		swap_info.oldSwapchain = old_swapchain;
		swap_info.clipped = true;

		swap_info.imageExtent = {extent->width, extent->height};

#ifdef _WIN32
		VkSurfaceFullScreenExclusiveInfoEXT full_screen_exclusive_info = {};
		if (should_specify_exclusive_full_screen_mode)
		{
			vk_exclusive_fs_mode fs_mode = g_cfg.video.vk.exclusive_fullscreen_mode;
			ensure(fs_mode == vk_exclusive_fs_mode::enable || fs_mode == vk_exclusive_fs_mode::disable);

			full_screen_exclusive_info.sType = VK_STRUCTURE_TYPE_SURFACE_FULL_SCREEN_EXCLUSIVE_INFO_EXT;
			full_screen_exclusive_info.fullScreenExclusive =
				fs_mode == vk_exclusive_fs_mode::enable ? VK_FULL_SCREEN_EXCLUSIVE_ALLOWED_EXT : VK_FULL_SCREEN_EXCLUSIVE_DISALLOWED_EXT;

			swap_info.pNext = &full_screen_exclusive_info;
		}

		rsx_log.notice("Swapchain: requesting full screen exclusive mode %d.", static_cast<int>(full_screen_exclusive_info.fullScreenExclusive));
#endif

		VkSwapchainKHR new_swapchain = VK_NULL_HANDLE;
		const VkResult status = _vkCreateSwapchainKHR(dev, &swap_info, nullptr, &new_swapchain);

		// Passing oldSwapchain retires it even when creation fails. Never reuse
		// that handle on a retry, or enumerate images through a failed output.
		m_vk_swapchain = VK_NULL_HANDLE;
		swapchain_images.clear();
		if (old_swapchain)
			_vkDestroySwapchainKHR(dev, old_swapchain, nullptr);

		if (status != VK_SUCCESS)
		{
			rsx_log.error("Swapchain: creation failed with VkResult %d", static_cast<int>(status));
			if (status == VK_ERROR_DEVICE_LOST)
				vk::die_with_error(status);
			return false;
		}

		m_vk_swapchain = new_swapchain;
		m_width = extent->width;
		m_height = extent->height;
		init_swapchain_images(dev);
		return true;
	}

	VkResult swapchain_WSI::present(VkSemaphore semaphore, u32 image)
	{
		VkPresentInfoKHR present = {};
		present.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
		present.pNext = nullptr;
		present.swapchainCount = 1;
		present.pSwapchains = &m_vk_swapchain;
		present.pImageIndices = &image;

		if (semaphore != VK_NULL_HANDLE)
		{
			present.waitSemaphoreCount = 1;
			present.pWaitSemaphores = &semaphore;
		}

		return _vkQueuePresentKHR(dev.get_present_queue(), &present);
	}
}
