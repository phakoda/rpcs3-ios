#pragma once

#include "swapchain_core.h"

namespace vk
{
#if defined(__APPLE__)
#include <TargetConditionals.h>
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
	using swapchain_iOS = native_swapchain_base;
	using swapchain_NATIVE = swapchain_iOS;

	[[maybe_unused]] static
	VkSurfaceKHR make_WSI_surface(VkInstance vk_instance, display_handle_t window_handle, WSI_config* /*config*/)
	{
		VkSurfaceKHR result = VK_NULL_HANDLE;
		VkIOSSurfaceCreateInfoMVK createInfo = {};
		createInfo.sType = VK_STRUCTURE_TYPE_IOS_SURFACE_CREATE_INFO_MVK;
		createInfo.pView = window_handle; // UIView*

		CHECK_RESULT(vkCreateIOSSurfaceMVK(vk_instance, &createInfo, NULL, &result));
		return result;
	}
#endif
#endif
}