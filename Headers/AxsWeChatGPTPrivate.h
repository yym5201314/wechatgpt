#pragma once

#import <UIKit/UIKit.h>

#import "AxsWeChatGPTConfig.h"

// Shared alert helper for the in-app panel pages. Hooks never put UI on screen
// on their own, so this stays header-only and is not exported from a library.
static inline void axs_wechatgpt_alert(UIViewController *host, NSString *title, NSString *message) {
    if (!host) {
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [host presentViewController:alert animated:YES completion:nil];
}
