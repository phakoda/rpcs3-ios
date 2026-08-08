#include "IOSVulkanProbe.h"

#import <QuartzCore/CAMetalLayer.h>

#include <vulkan/vulkan.h>

#include <cstring>
#include <vector>

namespace
{
bool has_extension(const std::vector<VkExtensionProperties>& extensions, const char* name)
{
    for (const VkExtensionProperties& extension : extensions)
    {
        if (std::strcmp(extension.extensionName, name) == 0)
        {
            return true;
        }
    }
    return false;
}

NSString* result_description(VkResult result)
{
    return [NSString stringWithFormat:@"Vulkan error %d", static_cast<int>(result)];
}
}

NSString* RPCS3RunVulkanProbe(CAMetalLayer* layer)
{
    if (!layer)
    {
        return @"No CAMetalLayer was supplied.";
    }

    uint32_t extension_count = 0;
    VkResult result = vkEnumerateInstanceExtensionProperties(nullptr, &extension_count, nullptr);
    if (result != VK_SUCCESS)
    {
        return result_description(result);
    }

    std::vector<VkExtensionProperties> available_extensions(extension_count);
    result = vkEnumerateInstanceExtensionProperties(nullptr, &extension_count, available_extensions.data());
    if (result != VK_SUCCESS)
    {
        return result_description(result);
    }

    if (!has_extension(available_extensions, VK_KHR_SURFACE_EXTENSION_NAME))
    {
        return @"MoltenVK loaded, but VK_KHR_surface is unavailable.";
    }
    if (!has_extension(available_extensions, VK_EXT_METAL_SURFACE_EXTENSION_NAME))
    {
        return @"MoltenVK loaded, but VK_EXT_metal_surface is unavailable.";
    }

    std::vector<const char*> enabled_extensions = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME,
    };

    VkInstanceCreateFlags instance_flags = 0;
#ifdef VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME
    if (has_extension(available_extensions, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME))
    {
        enabled_extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        instance_flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }
#endif
#ifdef VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME
    if (has_extension(available_extensions, VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME))
    {
        enabled_extensions.push_back(VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);
    }
#endif

    VkApplicationInfo application_info{};
    application_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    application_info.pApplicationName = "RPCS3 iOS bring-up";
    application_info.applicationVersion = VK_MAKE_API_VERSION(0, 0, 3, 0);
    application_info.pEngineName = "RPCS3";
    application_info.engineVersion = VK_MAKE_API_VERSION(0, 0, 3, 0);
    application_info.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo instance_info{};
    instance_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    instance_info.flags = instance_flags;
    instance_info.pApplicationInfo = &application_info;
    instance_info.enabledExtensionCount = static_cast<uint32_t>(enabled_extensions.size());
    instance_info.ppEnabledExtensionNames = enabled_extensions.data();

    VkInstance instance = VK_NULL_HANDLE;
    result = vkCreateInstance(&instance_info, nullptr, &instance);
    if (result != VK_SUCCESS)
    {
        return result_description(result);
    }

    const auto create_metal_surface = reinterpret_cast<PFN_vkCreateMetalSurfaceEXT>(
        vkGetInstanceProcAddr(instance, "vkCreateMetalSurfaceEXT"));
    if (!create_metal_surface)
    {
        vkDestroyInstance(instance, nullptr);
        return @"vkCreateMetalSurfaceEXT was not exported by MoltenVK.";
    }

    VkMetalSurfaceCreateInfoEXT surface_info{};
    surface_info.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    surface_info.pLayer = layer;

    VkSurfaceKHR surface = VK_NULL_HANDLE;
    result = create_metal_surface(instance, &surface_info, nullptr, &surface);
    if (result != VK_SUCCESS)
    {
        vkDestroyInstance(instance, nullptr);
        return result_description(result);
    }

    uint32_t device_count = 0;
    result = vkEnumeratePhysicalDevices(instance, &device_count, nullptr);
    if (result != VK_SUCCESS || device_count == 0)
    {
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        return result == VK_SUCCESS ? @"Metal surface created, but no Vulkan device was enumerated." : result_description(result);
    }

    std::vector<VkPhysicalDevice> devices(device_count);
    result = vkEnumeratePhysicalDevices(instance, &device_count, devices.data());
    if (result != VK_SUCCESS)
    {
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        return result_description(result);
    }

    VkPhysicalDeviceProperties properties{};
    vkGetPhysicalDeviceProperties(devices.front(), &properties);
    const uint32_t api_version = properties.apiVersion;
    NSString* status = [NSString stringWithFormat:
        @"MoltenVK bring-up passed.\nGPU: %s\nVulkan: %u.%u.%u\nSurface: VK_EXT_metal_surface",
        properties.deviceName,
        VK_API_VERSION_MAJOR(api_version),
        VK_API_VERSION_MINOR(api_version),
        VK_API_VERSION_PATCH(api_version)];

    vkDestroySurfaceKHR(instance, surface, nullptr);
    vkDestroyInstance(instance, nullptr);
    return status;
}
