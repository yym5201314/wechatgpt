#import "AxsWeChatGPTPromptsViewController.h"

#import "AxsWeChatGPTConfig.h"
#import "AxsWeChatGPTPrivate.h"
#import "AxsWeChatGPTSettingItem.h"

@implementation AxsWeChatGPTPromptsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self configureAppearanceWithTitle:@"提示词模板"];
    [self axs_wechatgpt_rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self axs_wechatgpt_rebuild];
}

- (NSArray<NSDictionary *> *)axs_wechatgpt_presets {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (id value in [[AxsWeChatGPTConfig shared] arrayForKey:AxsWeChatGPTPromptPresets]) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *item = (NSDictionary *)value;
        if ([item[@"name"] isKindOfClass:NSString.class] &&
            [item[@"prompt"] isKindOfClass:NSString.class]) [result addObject:item];
    }
    return result;
}

- (void)axs_wechatgpt_rebuild {
    AxsWeChatGPTConfig *config = [AxsWeChatGPTConfig shared];
    __weak typeof(self) weakSelf = self;
    NSString *active = [config stringForKey:AxsWeChatGPTActivePrompt];

    NSMutableArray<AxsWeChatGPTSettingItem *> *items = [NSMutableArray array];
    for (NSDictionary *preset in [self axs_wechatgpt_presets]) {
        NSString *name = preset[@"name"];
        NSString *prompt = preset[@"prompt"];
        BOOL isActive = [name isEqualToString:active];
        AxsWeChatGPTSettingItem *item =
            [AxsWeChatGPTSettingItem actionItemWithTitle:(isActive ? [NSString stringWithFormat:@"✓ %@", name] : name)
                                                iconName:@"text.quote"
                                               iconColor:isActive ? [UIColor systemGreenColor]
                                                                  : [UIColor systemPurpleColor]];
        item.detail = prompt.length > 30 ? [[prompt substringToIndex:30] stringByAppendingString:@"…"] : prompt;
        item.actionBlock = ^{ [weakSelf axs_wechatgpt_showActionsForPreset:preset]; };
        [items addObject:item];
    }

    NSMutableArray<AxsWeChatGPTSettingSection *> *sections = [NSMutableArray array];
    if (items.count) {
        [sections addObject:[AxsWeChatGPTSettingSection sectionWithHeader:@"提示词模板" items:items]];
    } else {
        AxsWeChatGPTSettingItem *empty = [AxsWeChatGPTSettingItem
            itemWithTitle:@"还没有模板"
               iconName:@"exclamationmark.triangle"
              iconColor:[UIColor systemOrangeColor]
                 detail:@"点下方新增一条"];
        [sections addObject:[AxsWeChatGPTSettingSection sectionWithHeader:@"提示词模板" items:@[empty]]];
    }

    AxsWeChatGPTSettingItem *add = [AxsWeChatGPTSettingItem actionItemWithTitle:@"新增提示词模板"
                                                                       iconName:@"plus.circle.fill"
                                                                      iconColor:[UIColor systemBlueColor]];
    add.detail = active.length ? [NSString stringWithFormat:@"当前：%@", active] : @"当前：默认";
    add.actionBlock = ^{ [weakSelf axs_wechatgpt_editPreset:nil]; };
    [sections addObject:[AxsWeChatGPTSettingSection sectionWithHeader:@"管理" items:@[add]]];

    self.sections = sections;
    [self.tableView reloadData];
}

- (void)axs_wechatgpt_showActionsForPreset:(NSDictionary *)preset {
    NSString *name = preset[@"name"];
    BOOL isActive = [name isEqualToString:[[AxsWeChatGPTConfig shared] stringForKey:AxsWeChatGPTActivePrompt]];
    __weak typeof(self) weakSelf = self;
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:name
                         message:preset[@"prompt"]
                  preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:(isActive ? @"取消启用" : @"启用此模板")
                                             style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        [[AxsWeChatGPTConfig shared] setString:isActive ? @"" : name forKey:AxsWeChatGPTActivePrompt];
        [weakSelf axs_wechatgpt_rebuild];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"编辑" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        [weakSelf axs_wechatgpt_editPreset:preset];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *action) {
        NSArray *current = [weakSelf axs_wechatgpt_presets];
        NSMutableArray *items = [current mutableCopy];
        for (NSUInteger i = 0; i < items.count; i++) {
            if ([items[i][@"name"] isEqualToString:name]) {
                [items removeObjectAtIndex:i];
                break;
            }
        }
        AxsWeChatGPTConfig *config = [AxsWeChatGPTConfig shared];
        [config setArray:items forKey:AxsWeChatGPTPromptPresets];
        if ([[config stringForKey:AxsWeChatGPTActivePrompt] isEqualToString:name]) {
            [config setString:@"" forKey:AxsWeChatGPTActivePrompt];
        }
        [weakSelf axs_wechatgpt_rebuild];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect =
        CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)axs_wechatgpt_editPreset:(NSDictionary *)existing {
    NSString *oldName = existing[@"name"];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:(existing ? @"编辑提示词模板" : @"新增提示词模板")
                         message:@"输入模板名称和内容。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"模板名称";
        field.text = oldName ?: @"";
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"提示词内容（可粘贴）";
        field.text = existing[@"prompt"] ?: @"";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *prompt = [alert.textFields.lastObject.text
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length || !prompt.length) {
            axs_wechatgpt_alert(weakSelf, @"不能保存", @"名称和提示词内容均不能为空。");
            return;
        }
        NSArray *current = [weakSelf axs_wechatgpt_presets];
        NSMutableArray *items = [current mutableCopy];
        for (NSDictionary *item in items) {
            if ([item[@"name"] isEqualToString:name] && ![item[@"name"] isEqualToString:oldName]) {
                axs_wechatgpt_alert(weakSelf, @"名称重复", @"请换一个模板名称。");
                return;
            }
        }
        BOOL found = NO;
        for (NSUInteger i = 0; i < items.count; i++) {
            if (oldName && [items[i][@"name"] isEqualToString:oldName]) {
                items[i] = @{@"name":name, @"prompt":prompt};
                found = YES;
                break;
            }
        }
        if (!found) [items addObject:@{@"name":name, @"prompt":prompt}];
        AxsWeChatGPTConfig *config = [AxsWeChatGPTConfig shared];
        [config setArray:items forKey:AxsWeChatGPTPromptPresets];
        if (oldName && [[config stringForKey:AxsWeChatGPTActivePrompt] isEqualToString:oldName]) {
            [config setString:name forKey:AxsWeChatGPTActivePrompt];
        }
        [weakSelf axs_wechatgpt_rebuild];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
