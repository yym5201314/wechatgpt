#import "AxsWeChatGPTPromptsViewController.h"

#import "AxsWeChatGPTConfig.h"
#import "AxsWeChatGPTPrivate.h"

@implementation AxsWeChatGPTPromptsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"提示词模板";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self
                             action:@selector(axs_wechatgpt_addPreset)];
}

- (NSArray<NSDictionary *> *)presets {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (id value in [[AxsWeChatGPTConfig shared] arrayForKey:AxsWeChatGPTPromptPresets]) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *item = (NSDictionary *)value;
        if ([item[@"name"] isKindOfClass:NSString.class] &&
            [item[@"prompt"] isKindOfClass:NSString.class]) [result addObject:item];
    }
    return result;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return (NSInteger)self.presets.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return @"点击模板启用，再次点击取消。左滑可编辑或删除；选中的提示词会用于手动对话及气泡 AI 回复。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                    reuseIdentifier:nil];
    NSDictionary *item = self.presets[indexPath.row];
    NSString *name = item[@"name"];
    cell.textLabel.text = name;
    cell.detailTextLabel.text = item[@"prompt"];
    cell.detailTextLabel.numberOfLines = 2;
    if ([name isEqualToString:[[AxsWeChatGPTConfig shared] stringForKey:AxsWeChatGPTActivePrompt]]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *name = self.presets[indexPath.row][@"name"];
    AxsWeChatGPTConfig *config = [AxsWeChatGPTConfig shared];
    NSString *active = [config stringForKey:AxsWeChatGPTActivePrompt];
    [config setString:[name isEqualToString:active] ? @"" : name forKey:AxsWeChatGPTActivePrompt];
    [tableView reloadData];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath; return YES;
}

- (NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView
                  editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    __weak typeof(self) weakSelf = self;
    UITableViewRowAction *remove = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive
        title:@"删除"
        handler:^(__unused UITableViewRowAction *action, NSIndexPath *path) {
        NSMutableArray *items = [weakSelf.presets mutableCopy];
        if (path.row >= (NSInteger)items.count) return;
        NSString *name = items[path.row][@"name"];
        [items removeObjectAtIndex:path.row];
        AxsWeChatGPTConfig *config = [AxsWeChatGPTConfig shared];
        [config setArray:items forKey:AxsWeChatGPTPromptPresets];
        if ([name isEqualToString:[config stringForKey:AxsWeChatGPTActivePrompt]]) {
            [config setString:@"" forKey:AxsWeChatGPTActivePrompt];
        }
        [weakSelf.tableView reloadData];
    }];
    UITableViewRowAction *edit = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal
        title:@"编辑"
        handler:^(__unused UITableViewRowAction *action, NSIndexPath *path) {
        NSArray *items = weakSelf.presets;
        if (path.row < (NSInteger)items.count) [weakSelf axs_wechatgpt_editPreset:items[path.row]];
    }];
    return @[remove, edit];
}

- (void)axs_wechatgpt_addPreset {
    [self axs_wechatgpt_editPreset:nil];
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
        NSMutableArray *items = [weakSelf.presets mutableCopy];
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
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
