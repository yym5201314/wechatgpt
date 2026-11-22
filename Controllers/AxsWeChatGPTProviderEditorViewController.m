#import "AxsWeChatGPTProviderEditorViewController.h"

#import "AxsWeChatGPTClient.h"
#import "AxsWeChatGPTConfig.h"
#import "AxsWeChatGPTModelPickerViewController.h"
#import "AxsWeChatGPTPrivate.h"

@implementation AxsWeChatGPTProviderEditorViewController {
    NSDictionary *_existing;
    UITextField *_nameField;
    UITextField *_urlField;
    UITextField *_keyField;
    UITextField *_modelField;
    BOOL _loading;
    BOOL _testing;
}

- (instancetype)initWithProvider:(NSDictionary *)provider {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _existing = [provider copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _existing ? @"编辑服务商" : @"新增服务商";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                             target:self
                             action:@selector(axs_wechatgpt_save)];
    _nameField = [self axs_wechatgpt_makeField:_existing[@"name"] placeholder:@"自定义服务商名称" secure:NO];
    _urlField = [self axs_wechatgpt_makeField:_existing[@"url"] placeholder:@"https://api.example.com/v1" secure:NO];
    _keyField = [self axs_wechatgpt_makeField:nil
                                  placeholder:_existing ? @"留空保留原密钥" : @"输入 API Key"
                                       secure:YES];
    _modelField = [self axs_wechatgpt_makeField:_existing[@"model"] placeholder:@"从接口拉取并选择模型" secure:NO];
}

- (UITextField *)axs_wechatgpt_makeField:(NSString *)value placeholder:(NSString *)placeholder secure:(BOOL)secure {
    UITextField *field = [UITextField new];
    field.font = [UIFont systemFontOfSize:15];
    field.text = value ?: @"";
    field.placeholder = placeholder;
    field.secureTextEntry = secure;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    return field;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? @"服务商资料" : @"模型";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                    reuseIdentifier:nil];
    if (indexPath.section == 1 && indexPath.row == 0) {
        cell.textLabel.text = _loading ? @"正在拉取模型…" : @"从接口拉取模型";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (indexPath.section == 1 && indexPath.row == 2) {
        cell.textLabel.text = _testing ? @"正在验证 API…" : @"验证 API";
        cell.textLabel.textColor = UIColor.systemBlueColor;
        cell.selectionStyle = _testing ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
        return cell;
    }
    UITextField *field;
    NSString *title;
    if (indexPath.section == 0) {
        if (indexPath.row == 0) { title = @"名称"; field = _nameField; }
        else if (indexPath.row == 1) { title = @"URL"; field = _urlField; }
        else { title = @"密钥"; field = _keyField; }
    } else {
        title = @"模型";
        field = _modelField;
    }
    cell.textLabel.text = title;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    field.frame = CGRectMake(86, 0, MAX(100, cell.contentView.bounds.size.width - 98), 44);
    [cell.contentView addSubview:field];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    if (indexPath.row == 2) { [self axs_wechatgpt_testCurrentAPI]; return; }
    if (indexPath.row != 0 || _loading) return;
    NSString *url = [_urlField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *key = _keyField.text.length ? _keyField.text
        : (_existing ? [[AxsWeChatGPTConfig shared] apiKeyForProviderID:_existing[@"id"]] : @"");
    if (!url.length || !key.length) {
        axs_wechatgpt_alert(self, @"无法拉取", @"请先填写 API URL 和 API Key。");
        return;
    }
    _loading = YES;
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [[AxsWeChatGPTClient shared] fetchModelsForURL:url apiKey:key
        completion:^(NSArray<NSString *> *models, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_loading = NO;
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            if (error || !models.count) {
                axs_wechatgpt_alert(self, @"拉取失败", error.localizedDescription ?: @"服务商未返回模型列表。");
                return;
            }
            AxsWeChatGPTModelPickerViewController *picker = [[AxsWeChatGPTModelPickerViewController alloc]
                initWithModels:models
                selected:self->_modelField.text ?: @""
                selection:^(NSString *model) { self->_modelField.text = model; }];
            [self.navigationController pushViewController:picker animated:YES];
        });
    }];
}

- (void)axs_wechatgpt_testCurrentAPI {
    if (_testing) return;
    NSString *url = [_urlField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *model = [_modelField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *key = _keyField.text.length ? _keyField.text
        : (_existing ? [[AxsWeChatGPTConfig shared] apiKeyForProviderID:_existing[@"id"]] : @"");
    if (!url.length || !key.length || !model.length) {
        axs_wechatgpt_alert(self, @"无法验证", @"请先填写 API URL、API Key 和模型。");
        return;
    }
    _testing = YES;
    NSIndexPath *row = [NSIndexPath indexPathForRow:2 inSection:1];
    [self.tableView reloadRowsAtIndexPaths:@[row] withRowAnimation:UITableViewRowAnimationNone];
    [[AxsWeChatGPTClient shared] testProviderURL:url apiKey:key model:model
        completion:^(NSString *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_testing = NO;
            if (!self.isViewLoaded || !self.view.window) return;
            [self.tableView reloadRowsAtIndexPaths:@[row] withRowAnimation:UITableViewRowAnimationNone];
            axs_wechatgpt_alert(self, error ? @"验证失败" : @"验证成功",
                                error.localizedDescription ?: response);
        });
    }];
}

- (void)axs_wechatgpt_save {
    NSString *name = [_nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *url = [_urlField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *model = [_modelField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length || !model.length) {
        axs_wechatgpt_alert(self, @"无法保存", @"服务商名称和模型不能为空。");
        return;
    }
    NSError *error = nil;
    if (![AxsWeChatGPTClient resolvedEndpointForBaseURL:url error:&error]) {
        axs_wechatgpt_alert(self, @"URL 错误", error.localizedDescription);
        return;
    }
    NSString *pid = _existing[@"id"] ?: NSUUID.UUID.UUIDString;
    AxsWeChatGPTConfig *config = [AxsWeChatGPTConfig shared];
    if (!_keyField.text.length && ![config apiKeyForProviderID:pid].length) {
        axs_wechatgpt_alert(self, @"缺少密钥", @"请填写该服务商的 API Key。");
        return;
    }
    if (_keyField.text.length && ![config saveAPIKey:_keyField.text forProviderID:pid]) {
        axs_wechatgpt_alert(self, @"保存失败", @"API Key 无法写入当前 App 钥匙串。");
        return;
    }
    [config upsertProvider:@{@"id":pid, @"name":name, @"url":url, @"model":model}];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
