#include "stdafx.h"

#include "VKFramebuffer.h"
#include "Emu/RSX/Common/framebuffer_key.h"
#include "vkutils/image.h"
#include "vkutils/image_helpers.h"

#include <algorithm>
#include <unordered_map>

namespace vk
{
	std::unordered_map<u64, std::vector<std::unique_ptr<vk::framebuffer_holder>>> g_framebuffers_cache;

	vk::framebuffer_holder* get_framebuffer(VkDevice dev, u16 width, u16 height, VkBool32 has_input_attachments, VkRenderPass renderpass, const std::vector<vk::image*>& image_list)
	{
		const auto key = rsx::framebuffer_cache_key(width, height, has_input_attachments != VK_FALSE);
		auto& queue = g_framebuffers_cache[key];

		for (const auto& fbo : queue)
		{
			if (fbo->matches(image_list, width, height))
			{
				return fbo.get();
			}
		}

		std::vector<std::unique_ptr<vk::image_view>> image_views;
		image_views.reserve(image_list.size());

		for (const auto& e : image_list)
		{
			const VkImageSubresourceRange subres = { e->aspect(), 0, 1, 0, 1 };
			image_views.push_back(std::make_unique<vk::image_view>(dev, e, e->format(), VK_IMAGE_VIEW_TYPE_2D, vk::default_component_map, subres));
		}

		auto value = std::make_unique<vk::framebuffer_holder>(dev, renderpass, width, height, std::move(image_views));
		auto ret = value.get();

		queue.push_back(std::move(value));
		return ret;
	}

	vk::framebuffer_holder* get_framebuffer(VkDevice dev, u16 width, u16 height, VkBool32 has_input_attachments, VkRenderPass renderpass, VkFormat format, VkImage attachment)
	{
		const auto key = rsx::framebuffer_cache_key(width, height, has_input_attachments != VK_FALSE);
		auto& queue = g_framebuffers_cache[key];

		for (const auto& e : queue)
		{
			if (e->attachments.size() == 1 && e->attachments[0]->info.image == attachment &&
				e->attachments[0]->info.format == format)
			{
				return e.get();
			}
		}

		VkImageSubresourceRange range = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
		std::vector<std::unique_ptr<vk::image_view>> views;

		views.push_back(std::make_unique<vk::image_view>(dev, attachment, VK_IMAGE_VIEW_TYPE_2D, format, vk::default_component_map, range));
		auto value = std::make_unique<vk::framebuffer_holder>(dev, renderpass, width, height, std::move(views));
		auto ret = value.get();

		queue.push_back(std::move(value));
		return ret;
	}

	void remove_unused_framebuffers()
	{
		// Remove stale framebuffers. Ref counted to prevent use-after-free
		for (auto It = g_framebuffers_cache.begin(); It != g_framebuffers_cache.end();)
		{
			It->second.erase(
				std::remove_if(It->second.begin(), It->second.end(), [](const auto& fbo)
				{
					return (fbo->unused_check_count() >= 2);
				}),
				It->second.end()
			);

			if (It->second.empty())
			{
				It = g_framebuffers_cache.erase(It);
			}
			else
			{
				++It;
			}
		}
	}

	void remove_framebuffers_with_image(VkImage attachment)
	{
		// Caller has drained GPU work. Keep unrelated render-target framebuffers.
		for (auto it = g_framebuffers_cache.begin(); it != g_framebuffers_cache.end();)
		{
			auto& bucket = it->second;
			std::erase_if(bucket, [attachment](const auto& fbo)
			{
				return std::any_of(fbo->attachments.begin(), fbo->attachments.end(), [attachment](const auto& view)
				{
					return view->info.image == attachment;
				});
			});
			if (bucket.empty())
				it = g_framebuffers_cache.erase(it);
			else
				++it;
		}
	}

	void clear_framebuffer_cache()
	{
		g_framebuffers_cache.clear();
	}
}
