#include "IOSPlatform.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <sys/sysctl.h>
#include <unistd.h>

#include <cstdlib>
#include <iomanip>
#include <sstream>

namespace
{
std::string utf8(NSString* value)
{
    const char* text = value.UTF8String;
    return text ? std::string(text) : std::string{};
}

std::string sysctl_string(const char* name)
{
    std::size_t size = 0;
    if (sysctlbyname(name, nullptr, &size, nullptr, 0) != 0 || size == 0)
    {
        return {};
    }

    std::string value(size, '\0');
    if (sysctlbyname(name, value.data(), &size, nullptr, 0) != 0)
    {
        return {};
    }
    while (!value.empty() && value.back() == '\0')
    {
        value.pop_back();
    }
    return value;
}

const char* thermal_name(rpcs3::ios::thermal_state state)
{
    using rpcs3::ios::thermal_state;
    switch (state)
    {
    case thermal_state::nominal: return "nominal";
    case thermal_state::fair: return "fair";
    case thermal_state::serious: return "serious";
    case thermal_state::critical: return "critical";
    case thermal_state::unknown: return "unknown";
    }
    return "unknown";
}

const char* pressure_name(rpcs3::ios::memory_pressure_level state)
{
    using rpcs3::ios::memory_pressure_level;
    switch (state)
    {
    case memory_pressure_level::normal: return "normal";
    case memory_pressure_level::warning: return "warning";
    case memory_pressure_level::critical: return "critical";
    case memory_pressure_level::unknown: return "unknown";
    }
    return "unknown";
}

std::string environment_value(const char* name)
{
    const char* value = std::getenv(name);
    return value ? std::string(value) : std::string("<unset>");
}
}

namespace rpcs3::ios
{
device_information get_device_information()
{
    NSProcessInfo* process = NSProcessInfo.processInfo;
    UIDevice* device = UIDevice.currentDevice;
    NSDictionary* info = NSBundle.mainBundle.infoDictionary;

    device_information result;
    result.model_identifier = sysctl_string("hw.model");
    if (result.model_identifier.empty())
    {
        result.model_identifier = sysctl_string("hw.machine");
    }
    result.operating_system = utf8(device.systemName);
    result.operating_system_version = utf8(device.systemVersion);

    NSString* short_version = info[@"CFBundleShortVersionString"] ?: @"0";
    NSString* build_version = info[@"CFBundleVersion"] ?: @"0";
    result.application_version = utf8([NSString stringWithFormat:@"%@ (%@)", short_version, build_version]);
    result.active_processor_count = static_cast<unsigned int>(process.activeProcessorCount);
    result.page_size = static_cast<unsigned int>(std::max<long>(sysconf(_SC_PAGESIZE), 0));
    result.physical_memory = process.physicalMemory;
    result.available_memory = get_performance_state().available_memory;
    return result;
}

std::string build_diagnostics_report()
{
    const device_information device = get_device_information();
    const runtime_paths paths = get_runtime_paths();
    const jit_capabilities jit = query_extended_jit_capabilities();
    const performance_state performance = get_performance_state();
    const external_display_state display = get_external_display_state();
    const std::vector<controller_state> controllers = get_combined_controller_states();

    std::ostringstream report;
    report << "RPCS3 iOS diagnostics\n";
    report << "=====================\n";
    report << "Application: " << device.application_version << '\n';
    report << "Device: " << device.model_identifier << '\n';
    report << "OS: " << device.operating_system << ' ' << device.operating_system_version << '\n';
    report << "Processors: " << device.active_processor_count << '\n';
    report << "Page size: " << device.page_size << '\n';
    report << "Physical memory: " << device.physical_memory << '\n';
    report << "Available memory: " << device.available_memory << '\n';
    report << "Thermal state: " << thermal_name(performance.thermal) << '\n';
    report << "Memory pressure: " << pressure_name(performance.memory_pressure) << '\n';
    report << "Low Power Mode: " << (performance.low_power_mode ? "enabled" : "disabled") << "\n\n";

    report << "Runtime paths\n";
    report << "-------------\n";
    report << "Application Support: " << paths.application_support << '\n';
    report << "Caches: " << paths.caches << '\n';
    report << "Documents: " << paths.documents << '\n';
    report << "Imports: " << paths.imports << '\n';
    report << "Temporary: " << paths.temporary << "\n\n";

    report << "Executable memory\n";
    report << "-----------------\n";
    report << jit.detail << "\n\n";

    report << "MoltenVK environment\n";
    report << "---------------------\n";
    for (const char* name : {
        "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS",
        "MVK_CONFIG_RESUME_LOST_DEVICE",
        "MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS",
        "MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER",
        "MVK_CONFIG_USE_COMMAND_POOLING",
        "MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE"})
    {
        report << name << '=' << environment_value(name) << '\n';
    }
    report << '\n';

    report << "Controllers\n";
    report << "-----------\n";
    if (controllers.empty())
    {
        report << "None\n";
    }
    for (std::size_t index = 0; index < controllers.size(); ++index)
    {
        const controller_capabilities capabilities = get_combined_controller_capabilities(index);
        report << index + 1 << ": " << controllers[index].vendor_name
            << ", motion=" << (capabilities.has_motion ? "yes" : "no")
            << ", haptics=" << (capabilities.has_haptics ? "yes" : "no");
        if (capabilities.has_battery)
        {
            report << ", battery=" << std::fixed << std::setprecision(0) << capabilities.battery_level * 100.0f << '%';
        }
        report << '\n';
    }
    report << '\n';

    report << "External display\n";
    report << "----------------\n";
    report << "Connected: " << (display.connected ? "yes" : "no") << '\n';
    if (display.connected)
    {
        report << "Resolution: " << display.width << 'x' << display.height << '\n';
        report << "Scale: " << display.scale << '\n';
        report << "Maximum refresh: " << display.maximum_frames_per_second << '\n';
    }
    return report.str();
}

bool write_diagnostics_report(std::string* report_path, std::string* error)
{
    const runtime_paths paths = get_runtime_paths();
    NSString* diagnostics_directory = [[NSString alloc] initWithUTF8String:(paths.caches + "Diagnostics").c_str()];
    NSError* file_error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:diagnostics_directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&file_error])
    {
        if (error)
        {
            *error = utf8(file_error.localizedDescription);
        }
        return false;
    }

    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString* filename = [NSString stringWithFormat:@"rpcs3-ios-%@.txt", [formatter stringFromDate:NSDate.date]];
    NSString* path = [diagnostics_directory stringByAppendingPathComponent:filename];
    NSString* report = [[NSString alloc] initWithUTF8String:build_diagnostics_report().c_str()];
    if (![report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&file_error])
    {
        if (error)
        {
            *error = utf8(file_error.localizedDescription);
        }
        return false;
    }

    if (report_path)
    {
        *report_path = utf8(path);
    }
    return true;
}
}
