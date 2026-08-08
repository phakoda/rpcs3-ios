#include "IOSPlatform.h"

#import <Metal/Metal.h>

#include <cstdlib>
#include <string>

namespace
{
void set_boolean_environment(const char* name, bool value)
{
    setenv(name, value ? "1" : "0", 1);
}
}

namespace rpcs3::ios
{
void configure_moltenvk(const moltenvk_options& options)
{
    bool use_argument_buffers = false;
    if (options.configure_argument_buffers)
    {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device && [device respondsToSelector:@selector(argumentBuffersSupport)])
        {
            use_argument_buffers = device.argumentBuffersSupport >= MTLArgumentBuffersTier2;
        }
    }

    set_boolean_environment("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", use_argument_buffers);
    set_boolean_environment("MVK_CONFIG_RESUME_LOST_DEVICE", options.resume_lost_device);
    set_boolean_environment("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", options.synchronous_queue_submits);
    set_boolean_environment("MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER", options.present_with_command_buffer);
    set_boolean_environment("MVK_CONFIG_USE_COMMAND_POOLING", options.use_command_pooling);

    const std::string command_buffer_count = std::to_string(options.max_active_command_buffers);
    setenv("MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE", command_buffer_count.c_str(), 1);
}
}
