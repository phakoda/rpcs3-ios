#include "IOSPlatform.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <unistd.h>

#include <algorithm>
#include <cmath>
#include <memory>

namespace
{
NSString* bundle_identifier()
{
    return NSBundle.mainBundle.bundleIdentifier ?: @"net.rpcs3.ios";
}

NSURL* provider_url(rpcs3::ios::jit_provider provider)
{
    NSString* identifier = [bundle_identifier() stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    const int pid = getpid();

    switch (provider)
    {
    case rpcs3::ios::jit_provider::apple_magnifier:
        return [NSURL URLWithString:[NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@", identifier]];
    case rpcs3::ios::jit_provider::stikjit:
        return [NSURL URLWithString:@"stikjit://enable-jit"];
    case rpcs3::ios::jit_provider::jitstreamer:
        return [NSURL URLWithString:[NSString stringWithFormat:@"http://[fd00::]:9172/attach/%d", pid]];
    }
    return nil;
}

bool jit_is_effectively_enabled(const rpcs3::ios::jit_capabilities& capabilities)
{
    return capabilities.map_jit_available &&
        capabilities.map_jit_allocation_succeeded &&
        (capabilities.dynamic_codesigning_entitlement ||
         capabilities.allow_jit_entitlement ||
         capabilities.debugger_entitlement ||
         capabilities.process_is_debugged);
}
}

namespace rpcs3::ios
{
std::vector<jit_provider_state> get_jit_provider_states()
{
    __block std::vector<jit_provider_state> states;
    const auto collect = ^{
        UIApplication* application = UIApplication.sharedApplication;
        states = {
            {
                .provider = jit_provider::apple_magnifier,
                .display_name = "TrollStore / Apple Magnifier",
                .available = [application canOpenURL:provider_url(jit_provider::apple_magnifier)],
            },
            {
                .provider = jit_provider::stikjit,
                .display_name = "StikJIT / StikDebug",
                .available = [application canOpenURL:provider_url(jit_provider::stikjit)],
            },
            {
                .provider = jit_provider::jitstreamer,
                .display_name = "JitStreamer network service",
                .available = true,
            },
        };
    };

    if (NSThread.isMainThread)
    {
        collect();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), collect);
    }
    return states;
}

bool request_jit(jit_provider provider, std::string* error)
{
    NSURL* url = provider_url(provider);
    if (!url)
    {
        if (error)
        {
            *error = "Could not construct the external JIT provider URL.";
        }
        return false;
    }

    if (provider == jit_provider::jitstreamer)
    {
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        request.timeoutInterval = 8.0;

        NSURLSessionDataTask* task = [NSURLSession.sharedSession dataTaskWithRequest:request
            completionHandler:^(NSData* data, NSURLResponse* response, NSError* request_error)
        {
            if (request_error)
            {
                NSLog(@"RPCS3 JitStreamer request failed: %@", request_error.localizedDescription);
                return;
            }

            NSHTTPURLResponse* http_response = [response isKindOfClass:NSHTTPURLResponse.class]
                ? (NSHTTPURLResponse*)response : nil;
            NSString* body = data.length > 0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            NSLog(@"RPCS3 JitStreamer response: HTTP %ld %@", (long)http_response.statusCode, body);
        }];
        [task resume];
        return true;
    }

    __block bool opened = false;
    const auto open_provider = ^{
        UIApplication* application = UIApplication.sharedApplication;
        if (![application canOpenURL:url])
        {
            return;
        }

        [application openURL:url options:@{} completionHandler:^(BOOL success)
        {
            if (!success)
            {
                NSLog(@"RPCS3 could not open JIT provider URL: %@", url);
            }
        }];
        opened = true;
    };

    if (NSThread.isMainThread)
    {
        open_provider();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), open_provider);
    }

    if (!opened && error)
    {
        *error = "The selected external JIT provider is not installed or its URL scheme is unavailable.";
    }
    return opened;
}

void wait_for_jit_enablement(double timeout_seconds, jit_enablement_callback callback)
{
    if (!callback)
    {
        return;
    }

    timeout_seconds = std::clamp(timeout_seconds, 1.0, 120.0);
    const unsigned int poll_count = static_cast<unsigned int>(std::ceil(timeout_seconds * 4.0));
    auto callback_holder = std::make_shared<jit_enablement_callback>(std::move(callback));

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        jit_capabilities capabilities;
        for (unsigned int attempt = 0; attempt < poll_count; ++attempt)
        {
            capabilities = query_extended_jit_capabilities();
            if (jit_is_effectively_enabled(capabilities))
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    (*callback_holder)(true, capabilities, "Executable-memory capability was detected.");
                });
                return;
            }
            usleep(250000);
        }

        capabilities = query_extended_jit_capabilities();
        dispatch_async(dispatch_get_main_queue(), ^{
            (*callback_holder)(false, capabilities,
                "Timed out waiting for an external debugger or JIT entitlement. The provider may not have attached.");
        });
    });
}
}
