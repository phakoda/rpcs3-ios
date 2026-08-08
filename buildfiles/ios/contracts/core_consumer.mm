#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#include <RPCS3Core/RPCS3Core.h>
#include <RPCS3Core/RPCS3CoreStatus.h>

@interface RPCS3ConsumerMetalView : UIView
@end

@implementation RPCS3ConsumerMetalView
+ (Class)layerClass
{
    return CAMetalLayer.class;
}
@end

int main()
{
    @autoreleasepool
    {
        RPCS3ConsumerMetalView* view = [[RPCS3ConsumerMetalView alloc] init];
        const rpcs3_ios_core_result result =
            rpcs3_ios_core_set_render_view((__bridge void*)view);
        return result == RPCS3_IOS_CORE_NOT_INITIALIZED ||
            result == RPCS3_IOS_CORE_SUCCESS
            ? 0
            : 1;
    }
}
