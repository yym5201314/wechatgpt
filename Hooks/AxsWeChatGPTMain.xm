#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "AxsWeChatGPTConfig.h"
#import "AxsWeChatGPTMenuInjector.h"

// Manual bubble-menu reply and on-demand analysis: no incoming hooks, no
// background reply worker and no automatic message send APIs. The panel is
// opened from WeChat's own settings page or the plugin list (see Entry hooks).
static void axs_wechatgpt_installMenu(void) {
    [AxsWeChatGPTMenuInjector installIfAvailable];
}

%ctor {
    @autoreleasepool {
        if (!objc_getClass("UIApplication")) return;
        // Create the store once so the first long press never touches defaults
        // while the menu is being measured.
        [AxsWeChatGPTConfig shared];
        dispatch_async(dispatch_get_main_queue(), ^{
            axs_wechatgpt_installMenu();
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            for (NSString *name in @[UIApplicationDidFinishLaunchingNotification,
                                      UIApplicationDidBecomeActiveNotification,
                                      UIWindowDidBecomeKeyNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                usingBlock:^(__unused NSNotification *note) {
                    axs_wechatgpt_installMenu();
                }];
            }
            // WeChat recreates text cell classes after launch; retry a few times.
            for (NSNumber *delay in @[@0.5, @2.0, @5.0]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ axs_wechatgpt_installMenu(); });
            }
        });
    }
}
