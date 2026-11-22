#import "AxsWeChatGPTEntryRouter.h"

#import <objc/message.h>
#import <objc/runtime.h>

static UIWindow *axs_wechatgpt_keyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]] ||
            scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
        if (windowScene.windows.firstObject) {
            return windowScene.windows.firstObject;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
}

BOOL axs_wechatgpt_pluginManagerAvailable(void) {
    Class managerClass = objc_getClass("WCPluginsMgr");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if (!managerClass || ![managerClass respondsToSelector:sharedSelector]) {
        return NO;
    }
    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSelector);
    return [manager respondsToSelector:NSSelectorFromString(@"registerControllerWithTitle:version:controller:")];
}

UIViewController *axs_wechatgpt_topMostViewController(void) {
    UIViewController *top = axs_wechatgpt_keyWindow().rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    if ([top isKindOfClass:[UINavigationController class]]) {
        top = [(UINavigationController *)top topViewController];
    }
    return top;
}

UIViewController *axs_wechatgpt_hostForResponder(UIResponder *responder) {
    for (UIResponder *current = responder; current; current = current.nextResponder) {
        if ([current isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)current;
        }
    }
    return nil;
}

// Panels pushed by the router have already passed the gate (when one is generated).
static char AxsWeChatGPTGatePassedKey;

static void axs_wechatgpt_pushPanel(UIViewController *host) {
    Class panelClass = NSClassFromString(@"AxsWeChatGPTRootViewController");
    if (!panelClass) {
        return;
    }
    UIViewController *panel = [[panelClass alloc] init];
    objc_setAssociatedObject(panel, &AxsWeChatGPTGatePassedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (host.navigationController) {
        [host.navigationController pushViewController:panel animated:YES];
    } else {
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:panel];
        [host presentViewController:navigation animated:YES completion:nil];
    }
}

void axs_wechatgpt_presentPanel(UIViewController *host) {
    if (!host) {
        return;
    }

    axs_wechatgpt_pushPanel(host);
}

void axs_wechatgpt_presentPanelFromResponder(UIResponder *responder) {
    axs_wechatgpt_presentPanel(axs_wechatgpt_hostForResponder(responder) ?: axs_wechatgpt_topMostViewController());
}

