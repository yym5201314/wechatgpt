#import "AxsWeChatGPTProvidersViewController.h"

#import "AxsWeChatGPTConfig.h"
#import "AxsWeChatGPTPrivate.h"
#import "AxsWeChatGPTProviderEditorViewController.h"
#import "AxsWeChatGPTSettingItem.h"

@implementation AxsWeChatGPTProvidersViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self configureAppearanceWithTitle:@"服务商与模型"];
    [self axs_wechatgpt_rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self axs_wechatgpt_rebuild];
}

- (void)axs_wechatgpt_rebuild {
    AxsWeChatGPTConfig *config = [AxsWeChatGPTConfig shared];
    __weak typeof(self) weakSelf = self;
    NSArray<NSDictionary *> *providers = [config providers];
    NSString *activeID = [config activeProviderID];

    NSMutableArray<AxsWeChatGPTSettingItem *> *providerItems = [NSMutableArray array];
    for (NSDictionary *provider in providers) {
        NSString *pid = provider[@"id"] ?: @"";
        BOOL active = [pid isEqualToString:activeID];
        NSString *name = provider[@"name"] ?: @"服务商";
        AxsWeChatGPTSettingItem *item =
            [AxsWeChatGPTSettingItem actionItemWithTitle:(active ? [NSString stringWithFormat:@"✓ %@", name] : name)
                                                iconName:@"server.rack"
                                               iconColor:active ? [UIColor systemGreenColor]
                                                                : [UIColor systemIndigoColor]];
        item.detail = [NSString stringWithFormat:@"%@ · %@", provider[@"model"] ?: @"", provider[@"url"] ?: @""];
        item.actionBlock = ^{ [weakSelf axs_wechatgpt_showActionsForProvider:provider]; };
        [providerItems addObject:item];
    }

    NSMutableArray<AxsWeChatGPTSettingSection *> *sections = [NSMutableArray array];
    if (providerItems.count) {
        [sections addObject:[AxsWeChatGPTSettingSection sectionWithHeader:@"服务商" items:providerItems]];
    } else {
        AxsWeChatGPTSettingItem *empty = [AxsWeChatGPTSettingItem
            itemWithTitle:@"还没有服务商"
               iconName:@"exclamationmark.triangle"
              iconColor:[UIColor systemOrangeColor]
                 detail:@"先在下方添加一个"];
        [sections addObject:[AxsWeChatGPTSettingSection sectionWithHeader:@"服务商" items:@[empty]]];
    }

    AxsWeChatGPTSettingItem *add = [AxsWeChatGPTSettingItem actionItemWithTitle:@"新增服务商"
                                                                       iconName:@"plus.circle.fill"
                                                                      iconColor:[UIColor systemBlueColor]];
    add.detail = @"URL + API Key";
    add.actionBlock = ^{ [weakSelf axs_wechatgpt_addProvider]; };
    [sections addObject:[AxsWeChatGPTSettingSection sectionWithHeader:@"管理" items:@[add]]];

    self.sections = sections;
    [self.tableView reloadData];
}

- (void)axs_wechatgpt_addProvider {
    [self.navigationController
        pushViewController:[[AxsWeChatGPTProviderEditorViewController alloc] initWithProvider:nil]
                  animated:YES];
}

- (void)axs_wechatgpt_showActionsForProvider:(NSDictionary *)provider {
    AxsWeChatGPTConfig *config = [AxsWeChatGPTConfig shared];
    NSString *pid = provider[@"id"] ?: @"";
    NSString *name = provider[@"name"] ?: @"服务商";
    __weak typeof(self) weakSelf = self;
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:name
                         message:[NSString stringWithFormat:@"%@ · %@", provider[@"model"] ?: @"", provider[@"url"] ?: @""]
                  preferredStyle:UIAlertControllerStyleActionSheet];
    if (![pid isEqualToString:[config activeProviderID]]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"设为当前服务商" style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *action) {
            [[AxsWeChatGPTConfig shared] selectProviderWithID:pid];
            [weakSelf axs_wechatgpt_rebuild];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"编辑" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        [weakSelf.navigationController
            pushViewController:[[AxsWeChatGPTProviderEditorViewController alloc] initWithProvider:provider]
                      animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *action) {
        [[AxsWeChatGPTConfig shared] removeProviderWithID:pid];
        [weakSelf axs_wechatgpt_rebuild];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect =
        CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
