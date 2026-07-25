#include "IOSCoreFallbackCallbacks.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

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

std::u32string utf32_string(NSString* value)
{
    std::u32string result;
    result.reserve(value.length);

    for (NSUInteger index = 0; index < value.length; ++index)
    {
        const unichar first = [value characterAtIndex:index];
        if (CFStringIsSurrogateHighCharacter(first) && index + 1 < value.length)
        {
            const unichar second = [value characterAtIndex:index + 1];
            if (CFStringIsSurrogateLowCharacter(second))
            {
                result.push_back(static_cast<char32_t>(CFStringGetLongCharacterForSurrogatePair(first, second)));
                ++index;
                continue;
            }
        }
        result.push_back(static_cast<char32_t>(first));
    }
    return result;
}

@interface RPCS3CoreSoundPool : NSObject <AVAudioPlayerDelegate>
@property(nonatomic, strong) NSMutableSet<AVAudioPlayer*>* players;
+ (instancetype)sharedPool;
- (void)playPath:(NSString*)path volume:(float)volume;
@end

@implementation RPCS3CoreSoundPool

+ (instancetype)sharedPool
{
    static RPCS3CoreSoundPool* pool = nil;
    static dispatch_once_t once_token;
    dispatch_once(&once_token, ^{
        pool = [[RPCS3CoreSoundPool alloc] init];
        pool.players = [NSMutableSet set];
    });
    return pool;
}

- (void)playPath:(NSString*)path volume:(float)volume
{
    if (!path.length)
    {
        return;
    }

    NSError* error = nil;
    AVAudioPlayer* player = [[AVAudioPlayer alloc]
        initWithContentsOfURL:[NSURL fileURLWithPath:path]
                        error:&error];
    if (!player)
    {
        NSLog(@"RPCS3Core could not play sound %@: %@", path, error.localizedDescription);
        return;
    }

    player.delegate = self;
    player.volume = std::clamp(volume, 0.0f, 1.0f);
    [self.players addObject:player];
    [player prepareToPlay];
    if (![player play])
    {
        [self.players removeObject:player];
    }
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer*)player successfully:(BOOL)flag
{
    (void)flag;
    [self.players removeObject:player];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer*)player error:(NSError*)error
{
    NSLog(@"RPCS3Core sound decode failed: %@", error.localizedDescription);
    [self.players removeObject:player];
}

@end
}

namespace rpcs3::ios
{
void extend_core_fallback_callbacks(EmuCallbacks& callbacks)
{
    callbacks.get_localized_string = [](localized_string_id, const char* fallback)
    {
        return fallback ? std::string(fallback) : std::string{};
    };

    callbacks.get_localized_u32string = [](localized_string_id, const char* fallback)
    {
        if (!fallback || !*fallback)
        {
            return std::u32string{};
        }
        return utf32_string([NSString stringWithUTF8String:fallback] ?: @"");
    };

    callbacks.play_sound = [](const std::string& path, std::optional<f32> volume)
    {
        NSString* sound_path = ns_utf8(path);
        const float sound_volume = volume.value_or(1.0f);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[RPCS3CoreSoundPool sharedPool] playPath:sound_path volume:sound_volume];
        });
    };
}
}
