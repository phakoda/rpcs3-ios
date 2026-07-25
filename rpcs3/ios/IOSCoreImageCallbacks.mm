#include "IOSCoreImageCallbacks.h"

#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "Emu/System.h"

#include <algorithm>
#include <string>

namespace
{
NSString* ns_utf8(const std::string& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

s32 rpc3_orientation(NSNumber* exif_orientation)
{
    switch (exif_orientation ? exif_orientation.intValue : 1)
    {
    case 1: return 1; // top-left, 0°
    case 6: return 2; // top-right, 90°
    case 3: return 3; // bottom-right, 180°
    case 8: return 4; // bottom-left, 270°
    default: return 0; // mirrored/unknown transformations are not represented
    }
}

bool image_info(const std::string& filename, std::string& subtype, s32& width, s32& height, s32& orientation)
{
    subtype.clear();
    width = 0;
    height = 0;
    orientation = 0;

    NSURL* url = [NSURL fileURLWithPath:ns_utf8(filename)];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    if (!source)
    {
        return false;
    }

    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nullptr);
    if (properties)
    {
        NSNumber* pixel_width = (__bridge NSNumber*)CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
        NSNumber* pixel_height = (__bridge NSNumber*)CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
        NSNumber* image_orientation = (__bridge NSNumber*)CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
        width = pixel_width.intValue;
        height = pixel_height.intValue;
        orientation = rpc3_orientation(image_orientation);
        CFRelease(properties);
    }

    CFStringRef identifier = CGImageSourceGetType(source);
    if (identifier)
    {
        UTType* type = [UTType typeWithIdentifier:(__bridge NSString*)identifier];
        subtype = type.preferredFilenameExtension.UTF8String ?: "";
    }
    CFRelease(source);
    return width > 0 && height > 0;
}

bool scaled_image(
    const std::string& path,
    s32 target_width,
    s32 target_height,
    s32& width,
    s32& height,
    u8* destination,
    bool force_fit)
{
    width = 0;
    height = 0;
    if (target_width <= 0 || target_height <= 0 || !destination)
    {
        return false;
    }

    NSURL* url = [NSURL fileURLWithPath:ns_utf8(path)];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    if (!source)
    {
        return false;
    }

    s32 source_width = 0;
    s32 source_height = 0;
    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nullptr);
    if (properties)
    {
        source_width = [(__bridge NSNumber*)CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth) intValue];
        source_height = [(__bridge NSNumber*)CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight) intValue];
        CFRelease(properties);
    }
    if (source_width <= 0 || source_height <= 0)
    {
        CFRelease(source);
        return false;
    }

    const double target_ratio = target_width / static_cast<double>(target_height);
    const double source_ratio = source_width / static_cast<double>(source_height);
    const double conversion = source_ratio / target_ratio;
    width = source_width;
    height = source_height;
    if (force_fit || width > target_width || height > target_height)
    {
        if (conversion > 1.0)
        {
            width = target_width;
            height = std::max<s32>(1, static_cast<s32>(target_height / conversion));
        }
        else if (conversion < 1.0)
        {
            width = std::max<s32>(1, static_cast<s32>(target_width * conversion));
            height = target_height;
        }
        else
        {
            width = target_width;
            height = target_height;
        }
    }

    NSDictionary* options = @{
        (__bridge NSString*)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString*)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString*)kCGImageSourceThumbnailMaxPixelSize: @(std::max(width, height)),
        (__bridge NSString*)kCGImageSourceShouldCacheImmediately: @YES,
    };
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!image)
    {
        return false;
    }

    width = static_cast<s32>(CGImageGetWidth(image));
    height = static_cast<s32>(CGImageGetHeight(image));
    if (width <= 0 || height <= 0 || width > target_width || height > target_height)
    {
        CGImageRelease(image);
        return false;
    }

    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        destination,
        width,
        height,
        8,
        static_cast<size_t>(width) * 4,
        color_space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(color_space);
    if (!context)
    {
        CGImageRelease(image);
        return false;
    }

    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1, -1);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGImageRelease(image);

    // CoreGraphics writes premultiplied RGBA. RPCS3's QImage callback returns
    // straight RGBA8888, so restore color channels before returning the buffer.
    const usz pixel_count = static_cast<usz>(width) * static_cast<usz>(height);
    for (usz index = 0; index < pixel_count; ++index)
    {
        u8* pixel = destination + index * 4;
        const u32 alpha = pixel[3];
        if (alpha > 0 && alpha < 255)
        {
            pixel[0] = static_cast<u8>(std::min<u32>((pixel[0] * 255u + alpha / 2u) / alpha, 255));
            pixel[1] = static_cast<u8>(std::min<u32>((pixel[1] * 255u + alpha / 2u) / alpha, 255));
            pixel[2] = static_cast<u8>(std::min<u32>((pixel[2] * 255u + alpha / 2u) / alpha, 255));
        }
    }
    return true;
}
}

namespace rpcs3::ios
{
void extend_core_image_callbacks(EmuCallbacks& callbacks)
{
    callbacks.get_image_info = image_info;
    callbacks.get_scaled_image = scaled_image;
}
}
