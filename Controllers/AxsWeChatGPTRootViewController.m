#import "AxsWeChatGPTRootViewController.h"

#import "AxsWeChatGPTConfig.h"
#import "AxsWeChatGPTPrivate.h"
#import "AxsWeChatGPTProvidersViewController.h"
#import "AxsWeChatGPTPromptsViewController.h"
#import "AxsWeChatGPTSettingItem.h"

@implementation AxsWeChatGPTRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self configureAppearanceWithTitle:@"WeChatGPT"];
    if (self.presentingViewController) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                 target:self
                                 action:@selector(axs_wechatgpt_close)];
    }
    [self axs_wechatgpt_rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self axs_wechatgpt_rebuild];
}

- (void)axs_wechatgpt_close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)axs_wechatgpt_rebuild {
    AxsWeChatGPTConfig *config = [AxsWeChatGPTConfig shared];
    __weak typeof(self) weakSelf = self;
    NSMutableArray<AxsWeChatGPTSettingSection *> *sections = [NSMutableArray array];

    NSMutableArray<AxsWeChatGPTSettingItem *> *featureItems = [NSMutableArray array];
    [featureItems addObject:
        [AxsWeChatGPTSettingItem switchItemWithTitle:@"启用插件"
                                            iconName:@"power"
                                           iconColor:[UIColor systemGreenColor]
                                         switchValue:[config axs_wechatgpt_isEnabled]
                                   valueChangedBlock:^(BOOL isOn) {
            [config axs_wechatgpt_setEnabled:isOn];
        }]];
    [featureItems addObject:
        [AxsWeChatGPTSettingItem switchItemWithTitle:@"长按气泡AI回复"
                                            iconName:@"bubble.left.fill"
                                           iconColor:[UIColor systemBlueColor]
                                         switchValue:[config boolForKey:AxsWeChatGPTManualMenuEnabled]
                                   valueChangedBlock:^(BOOL isOn) {
            [config setBool:isOn forKey:AxsWeChatGPTManualMenuEnabled];
        }]];
    AxsWeChatGPTSettingItem *countItem =
        [AxsWeChatGPTSettingItem actionItemWithTitle:@"读取条数"
                                            iconName:@"clock.arrow.circlepath"
                                           iconColor:[UIColor systemOrangeColor]];
    countItem.detail = [NSString stringWithFormat:@"%ld 条", (long)[config historyMessageCount]];
    countItem.actionBlock = ^{ [weakSelf axs_wechatgpt_editHistoryCount]; };
    [featureItems addObject:countItem];
    [sections addObject:[AxsWeChatGPTSettingSection sectionWithHeader:@"功能面板" items:featureItems]];

    NSDictionary *provider = [config activeProvider];
    AxsWeChatGPTSettingItem *providerItem =
        [AxsWeChatGPTSettingItem actionItemWithTitle:@"服务商与模型"
                                            iconName:@"server.rack"
                                           iconColor:[UIColor systemIndigoColor]];
    providerItem.detail = provider
        ? [NSString stringWithFormat:@"%@ · %@", provider[@"model"], provider[@"name"]]
        : @"未配置";
    providerItem.actionBlock = ^{
        [weakSelf.navigationController
            pushViewController:[[AxsWeChatGPTProvidersViewController alloc] init]
                      animated:YES];
    };

    NSString *prefix = [config stringForKey:AxsWeChatGPTPrefix];
    AxsWeChatGPTSettingItem *prefixItem =
        [AxsWeChatGPTSettingItem actionItemWithTitle:@"回复消息前缀"
                                            iconName:@"textformat"
                                           iconColor:[UIColor systemTealColor]];
    prefixItem.detail = prefix.length
        ? (prefix.length > 16 ? [[prefix substringToIndex:16] stringByAppendingString:@"…"] : prefix)
        : @"未设置";
    prefixItem.actionBlock = ^{ [weakSelf axs_wechatgpt_editPrefix]; };

    NSString *activePrompt = [config stringForKey:AxsWeChatGPTActivePrompt];
    AxsWeChatGPTSettingItem *promptItem =
        [AxsWeChatGPTSettingItem actionItemWithTitle:@"提示词模板"
                                            iconName:@"doc.text"
                                           iconColor:[UIColor systemPurpleColor]];
    promptItem.detail = activePrompt.length ? activePrompt : @"默认";
    promptItem.actionBlock = ^{
        [weakSelf.navigationController
            pushViewController:[[AxsWeChatGPTPromptsViewController alloc] init]
                      animated:YES];
    };
    [sections addObject:[AxsWeChatGPTSettingSection sectionWithHeader:@"AI 接口"
                                                                items:@[providerItem, prefixItem, promptItem]]];

    self.sections = sections;
    [self.tableView reloadData];
}

- (void)axs_wechatgpt_editHistoryCount {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"读取条数"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [NSString stringWithFormat:@"%ld", (long)[[AxsWeChatGPTConfig shared] historyMessageCount]];
        field.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        NSString *value = [alert.textFields.firstObject.text
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        NSCharacterSet *nondigits = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
        NSString *maxValue = [NSString stringWithFormat:@"%lld", (long long)NSIntegerMax];
        NSString *normalized = value;
        while (normalized.length > 1 && [normalized hasPrefix:@"0"]) {
            normalized = [normalized substringFromIndex:1];
        }
        BOOL tooLarge = normalized.length > maxValue.length ||
            (normalized.length == maxValue.length &&
             [normalized compare:maxValue options:NSLiteralSearch] == NSOrderedDescending);
        if (!normalized.length || [normalized rangeOfCharacterFromSet:nondigits].location != NSNotFound ||
            tooLarge || normalized.longLongValue < 1) {
            axs_wechatgpt_alert(weakSelf, @"条数无效", @"请输入正整数（最大为当前系统的 NSIntegerMax）。");
            return;
        }
        [[AxsWeChatGPTConfig shared] setHistoryMessageCount:(NSInteger)normalized.longLongValue];
        [weakSelf axs_wechatgpt_rebuild];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)axs_wechatgpt_editPrefix {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"回复消息前缀"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [[AxsWeChatGPTConfig shared] stringForKey:AxsWeChatGPTPrefix];
        field.placeholder = @"可留空";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        [[AxsWeChatGPTConfig shared] setString:alert.textFields.firstObject.text ?: @"" forKey:AxsWeChatGPTPrefix];
        [weakSelf axs_wechatgpt_rebuild];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
