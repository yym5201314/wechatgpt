#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "AxsWeChatGPTEntryRouter.h"

// Entry 2: a row in WeChat's own Settings page (NewSettingViewController).

@interface WCTableViewNormalCellManager : NSObject
+ (instancetype)normalCellForSel:(SEL)sel
                          target:(id)target
                           title:(NSString *)title
                      rightValue:(NSString *)rightValue
                   accessoryType:(int)accessoryType;
@end

@interface WCTableViewSectionManager : NSObject
- (void)addCell:(id)cell;
@end

@interface WCTableViewManager : NSObject
- (WCTableViewSectionManager *)getSectionAt:(int)section;
- (void)reloadTableView;
@end

@interface NewSettingViewController : UIViewController
@end

static char AxsWeChatGPTSettingsRowKey;

static WCTableViewManager *axs_wechatgpt_tableManager(UIViewController *controller) {
    static const char *names[] = {"m_tableViewMgr", "_tableViewMgr", "m_tableMgr", "_tableMgr"};
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        Ivar ivar = class_getInstanceVariable([controller class], names[i]);
        id value = ivar ? object_getIvar(controller, ivar) : nil;
        if (value) {
            return value;
        }
    }
    return nil;
}

static void axs_wechatgpt_ensureSettingsRow(UIViewController *controller) {
    // When the plugin-center entry is generated too, it owns the case where a manager exists.
    if (1 && axs_wechatgpt_pluginManagerAvailable()) {
        return;
    }
    if (objc_getAssociatedObject(controller, &AxsWeChatGPTSettingsRowKey)) {
        return;
    }
    WCTableViewManager *manager = axs_wechatgpt_tableManager(controller);
    WCTableViewSectionManager *section = [manager getSectionAt:0];
    Class cellClass = objc_getClass("WCTableViewNormalCellManager");
    if (!section || !cellClass) {
        return;
    }
    id cell = [cellClass normalCellForSel:@selector(axs_wechatgpt_openPanel)
                                   target:controller
                                    title:@"WeChatGPT"
                               rightValue:@"5.2.0"
                            accessoryType:1];
    if (!cell) {
        return;
    }
    [section addCell:cell];
    [manager reloadTableView];
    objc_setAssociatedObject(controller, &AxsWeChatGPTSettingsRowKey, cell, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook NewSettingViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    axs_wechatgpt_ensureSettingsRow(self);
}

%new
- (void)axs_wechatgpt_openPanel {
    axs_wechatgpt_presentPanel(self);
}

%end
