#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "src/DGPTUI.h"
#import "src/DGPTNativeMenu.h"

// Manual bubble-menu AI reply and on-demand analysis: no incoming hooks,
// no background reply worker and no automatic message send APIs.
static void DGPTInstallMenu(void) {
    [DGPTNativeMenu installIfAvailable];
}

%ctor {
    @autoreleasepool {
        if (!objc_getClass("UIApplication")) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[DGPTUI shared] start];
            DGPTInstallMenu();
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            for (NSString *name in @[UIApplicationDidFinishLaunchingNotification,
                                      UIApplicationDidBecomeActiveNotification,
                                      UIWindowDidBecomeKeyNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                               usingBlock:^(__unused NSNotification *note) {
                    DGPTInstallMenu();
                }];
            }
            for (NSNumber *delay in @[@0.5, @2.0, @5.0]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ DGPTInstallMenu(); });
            }
        });
    }
}
