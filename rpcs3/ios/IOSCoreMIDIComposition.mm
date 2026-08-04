#include "IOSCoreMIDI.h"

#import <Foundation/Foundation.h>

#include <string>

namespace
{
NSString* const midi_assignments_key = @"RPCS3Core.MIDI.Assignments";
NSString* const midi_name_key = @"Name";

std::string utf8_string(NSString* value)
{
    const char* bytes = value.UTF8String;
    return bytes ? std::string(bytes) : std::string{};
}

NSString* ns_utf8(const std::string& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

void migrate_assignments()
{
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    NSArray* stored = [defaults arrayForKey:midi_assignments_key];
    if (!stored.count)
    {
        return;
    }

    BOOL changed = NO;
    NSMutableArray* migrated = [NSMutableArray arrayWithCapacity:stored.count];
    for (id value in stored)
    {
        if (![value isKindOfClass:NSDictionary.class])
        {
            [migrated addObject:value];
            continue;
        }

        NSMutableDictionary* entry = [(NSDictionary*)value mutableCopy];
        NSString* name = entry[midi_name_key];
        if ([name isKindOfClass:NSString.class] && name.length)
        {
            const std::string original = utf8_string(name);
            const std::string resolved = rpcs3::ios::resolve_core_midi_source_identity(original);
            if (resolved != original)
            {
                entry[midi_name_key] = ns_utf8(resolved);
                changed = YES;
            }
        }
        [migrated addObject:entry];
    }

    if (changed)
    {
        [defaults setObject:migrated forKey:midi_assignments_key];
    }
}
}

namespace rpcs3::ios
{
void apply_core_midi_configuration()
{
    migrate_assignments();
    apply_core_midi_configuration_base();
}
}
