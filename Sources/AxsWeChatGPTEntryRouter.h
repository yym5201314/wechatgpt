#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Every WeChat entry (plugin list, Settings row, toolbar, drawer) opens the panel
// through axs_wechatgpt_presentPanel, so the follow gate and navigation live in one place.

BOOL axs_wechatgpt_pluginManagerAvailable(void);
UIViewController * _Nullable axs_wechatgpt_topMostViewController(void);
UIViewController * _Nullable axs_wechatgpt_hostForResponder(UIResponder * _Nullable responder);

void axs_wechatgpt_presentPanel(UIViewController * _Nullable host);
void axs_wechatgpt_presentPanelFromResponder(UIResponder * _Nullable responder);

NS_ASSUME_NONNULL_END
