# SPDX-License-Identifier: GPL-2.0-only
"""Source-wiring regression guards, NOT runtime or Apple SDK validation.

Executable policy tests cover the algorithms. These deliberately small checks
ensure production paths still call them and preserve key ownership/order rules.
"""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]


def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


class SourceContracts(unittest.TestCase):
    def test_vulkan_presets_are_opt_in_and_sdk_specific(self):
        presets = json.loads(read("CMakePresets.json"))
        configure = {p["name"]: p for p in presets["configurePresets"]}
        self.assertEqual(configure["ios-base"]["cacheVariables"]["USE_VULKAN"], "OFF")
        for target, sdk in (("device", "iphoneos"), ("simulator", "iphonesimulator")):
            name = "ios-" + target + "-vulkan"
            preset = configure[name]
            self.assertEqual(preset["inherits"], "ios-" + target)
            self.assertEqual(preset["cacheVariables"]["USE_VULKAN"], "ON")
            self.assertEqual(preset["cacheVariables"]["USE_SYSTEM_MVK"], "ON")
            self.assertEqual(configure[preset["inherits"]]["cacheVariables"]["CMAKE_OSX_SYSROOT"], sdk)
            self.assertIn(name, [p["configurePreset"] for p in presets["buildPresets"]])

    def test_moltenvk_validation_is_in_build_path(self):
        source = read("3rdparty/CMakeLists.txt")
        self.assertIn("buildfiles/ios/check_moltenvk.py", source)
        self.assertIn('--platform "${RPCS3_IOS_PLATFORM}"', source)
        self.assertIn("if(NOT RPCS3_MVK_CHECK_RESULT EQUAL 0)", source)

    def test_metal_view_uses_arc_and_layout_driven_size(self):
        source = read("rpcs3/Emu/RSX/VK/vkutils/metal_layer.mm")
        self.assertIn("+ (Class)layerClass", source)
        self.assertIn("- (void)layoutSubviews", source)
        self.assertIn("- (void)didMoveToWindow", source)
        self.assertIn("CGSizeEqualToSize(metalLayer.drawableSize, size)", source)
        self.assertIn("setDisableActions:YES", source)
        cmake = read("rpcs3/Emu/CMakeLists.txt")
        self.assertRegex(cmake, r'set_source_files_properties\(RSX/VK/vkutils/metal_layer\.mm\s+PROPERTIES\s+COMPILE_OPTIONS "-fobjc-arc"')

    def test_present_semaphores_follow_acquired_images(self):
        source = read("rpcs3/Emu/RSX/VK/VKPresent.cpp")
        self.assertIn("m_present_semaphores.at(ctx->present_image)", source)
        self.assertIn("m_present_semaphores.at(m_current_frame->present_image)", source)
        self.assertNotIn("present_wait_semaphore", read("rpcs3/Emu/RSX/VK/VKGSRenderTypes.hpp"))
        self.assertNotIn("m_present_semaphores.at(m_current_queue_index)", source)

    def test_first_transition_and_acquire_wait_use_same_stage_mask(self):
        source = read("rpcs3/Emu/RSX/VK/VKPresent.cpp")
        self.assertIn("swapchain_acquire_stages, destination_stage, 0, destination_access, range", source)
        self.assertIn("m_present_semaphores.at(m_current_frame->present_image),\n\t\t\tswapchain_acquire_stages", source)
        self.assertIn("VkImageLayout target_layout = VK_IMAGE_LAYOUT_UNDEFINED", source)

    def test_initialization_does_not_clear_unacquired_images(self):
        constructor = read("rpcs3/Emu/RSX/VK/VKGSRender.cpp")
        constructor = constructor[constructor.index("VKGSRender::VKGSRender("):constructor.index("VKGSRender::~VKGSRender()")]
        self.assertNotIn("vkCmdClearColorImage", constructor)
        source = read("rpcs3/Emu/RSX/VK/VKPresent.cpp")
        resize = source[source.index("bool VKGSRender::reinitialize_swapchain()"):source.index("void VKGSRender::present(")]
        self.assertNotIn("vkCmdClearColorImage", resize)
        self.assertNotIn("resize_fence", resize)

    def test_framebuffer_views_retire_before_old_images(self):
        source = read("rpcs3/Emu/RSX/VK/VKPresent.cpp")
        resize = source[source.index("bool VKGSRender::reinitialize_swapchain()"):source.index("void VKGSRender::present(")]
        self.assertLess(resize.index("vkDeviceWaitIdle"), resize.index("vk::remove_framebuffers_with_image"))
        self.assertLess(resize.index("vkDeviceWaitIdle"), resize.index("m_upscaler.reset()"))
        self.assertLess(resize.index("vk::remove_framebuffers_with_image"), resize.index("m_swapchain->init("))
        cache = read("rpcs3/Emu/RSX/VK/VKFramebuffer.cpp")
        self.assertEqual(cache.count("rsx::framebuffer_cache_key("), 2)
        self.assertNotIn("union framebuffer_storage_key", cache)
        self.assertIn("e->attachments.size() == 1", cache)
        self.assertIn("e->attachments[0]->info.format == format", cache)

    def test_surface_and_input_policies_are_used_by_production(self):
        source = read("rpcs3/Emu/RSX/VK/vkutils/swapchain.cpp")
        for helper in ("choose_extent", "choose_image_count", "choose_composite_alpha", "enumerate"):
            self.assertIn("rsx::presentation::" + helper, source)
        self.assertIn("rsx::presentation::choose_surface_format", read("rpcs3/Emu/RSX/VK/vkutils/instance.cpp"))
        source = read("rpcs3/Input/ios_pad_handler.cpp")
        for helper in ("axis_value", "trigger_value", "sensor_value", "battery_level"):
            self.assertIn("ios_input::" + helper, source)
        source = read("rpcs3/Input/ios_controller_bridge.mm")
        for helper in ("normalize_stick", "update_slots", "finite_clamp"):
            self.assertIn("ios_input::" + helper, source)

    def test_configuration_only_handler_does_not_stop_active_manager(self):
        source = read("rpcs3/Input/ios_pad_handler.cpp")
        destructor = source[source.index("ios_pad_handler::~ios_pad_handler()"):source.index("std::string ios_pad_handler::device_name")]
        self.assertRegex(destructor, r"if \(m_is_init\)\s+ios_controller_stop\(\)")
        bridge = read("rpcs3/Input/ios_controller_bridge.mm")
        self.assertIn("++self.clientCount != 1", bridge)
        self.assertIn("--self.clientCount != 0", bridge)

    def test_background_and_disconnect_neutralize_input(self):
        source = read("rpcs3/Input/ios_controller_bridge.mm")
        self.assertIn("UIApplicationWillResignActiveNotification", source)
        self.assertIn("UIWindowDidBecomeKeyNotification", source)
        method = source[source.index("- (void)applicationInactive:"):source.index("- (void)applicationActive:")]
        self.assertIn("self.virtualPadActive = NO", method)
        self.assertIn("resetInputs", method)
        self.assertIn("stopAllHaptics", method)
        read_method = source[source.index("- (BOOL)readVirtualSnapshot:", source.index("@implementation RPCS3IOSControllerManager")):]
        read_method = read_method[:read_method.index("- (void)rumbleController:")]
        self.assertNotIn(".hidden", read_method)
        self.assertIn("@synchronized(self)", read_method)
        self.assertIn("@synchronized(pad)", read_method)

    def test_zero_rumble_stops_existing_player(self):
        source = read("rpcs3/Input/ios_controller_bridge.mm")
        method = source[source.index("- (void)rumbleController:", source.index("@implementation RPCS3IOSControllerManager")):]
        stop = method.index("[previous stopAtTime:")
        zero = method.index("if (intensity <= 0.f)")
        self.assertLess(stop, zero)
        self.assertIn("duration:0.4", method)
        self.assertIn("UIControlEventTouchDragExit", source)
        self.assertIn("self.activeTouch && [touches containsObject:self.activeTouch]", source)


if __name__ == "__main__":
    unittest.main()
