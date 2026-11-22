#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "AxsWeChatGPTEntryRouter.h"

// Entry 1: WeChat's plugin-center list (WCPluginsMgr). Does nothing when no
// plugin manager is installed; pair with the Settings entry for that case.

@interface MinimizeViewController : UIViewController
@end

%hook MinimizeViewController

- (void)viewDidLoad {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!axs_wechatgpt_pluginManagerAvailable()) {
            return;
        }
        id manager = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("WCPluginsMgr"),
                                                     NSSelectorFromString(@"sharedInstance"));
        ((void (*)(id, SEL, NSString *, NSString *, NSString *))objc_msgSend)(
            manager, NSSelectorFromString(@"registerControllerWithTitle:version:controller:"),
            @"WeChatGPT", @"5.2.0", @"AxsWeChatGPTRootViewController");
    });
}

%end
