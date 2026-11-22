#import "DGPTUI.h"
#import "DGPTConfig.h"
#import "DGPTClient.h"
#import "DGPTMessageReply.h"
#import "DGPTWeChatBridge.h"
#import <objc/runtime.h>

@interface DGPTSettingsVC : UITableViewController
@end

@interface DGPTPromptsVC : UITableViewController
- (void)editPreset:(NSDictionary *)existing;
@end

// Universal settings entry for UIKit windows; no application bundle ID filter.
// Two-finger double tap is a fallback if a chat's private long press gesture
// prevents the two-finger long press from recognizing.
static char kDGPTTwoFingerPressKey;
static char kDGPTTwoFingerDoubleTapKey;

@interface DGPTUI () <UIGestureRecognizerDelegate>
@end

static void DGPTAlert(UIViewController *vc, NSString *title, NSString *message) {
    if (!vc) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

@implementation DGPTUI

+ (instancetype)shared {
    static DGPTUI *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [DGPTUI new]; });
    return instance;
}

- (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[
            UIApplicationDidBecomeActiveNotification,
            UIApplicationWillEnterForegroundNotification,
            UIApplicationDidFinishLaunchingNotification,
            UIWindowDidBecomeVisibleNotification,
            UIWindowDidBecomeKeyNotification,
            UISceneDidActivateNotification
        ]) {
            [center addObserver:self selector:@selector(handleWindowNotification:)
                         name:name object:nil];
        }
        NSLog(@"[StandaloneGPT] Universal UIKit two-finger entry started");
    });
    [self installTwoFingerGestures];
    // Windows might not yet exist when %ctor runs. Retry after launch.
    for (NSNumber *delay in @[@0.5, @1.0, @3.0, @8.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self installTwoFingerGestures]; });
    }
}

- (void)handleWindowNotification:(NSNotification *)notification {
    (void)notification;
    [self installTwoFingerGestures];
}

- (void)installTwoFingerGestures {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self installTwoFingerGestures]; });
        return;
    }

    UIApplication *app = UIApplication.sharedApplication;
    NSMutableSet<UIWindow *> *windows = [NSMutableSet setWithArray:app.windows ?: @[]];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) [windows addObject:window];
        }
    }

    for (UIWindow *window in windows) {
        // Also cover controls, tables, sheets, alerts and non-normal windows.
        // Do not attach to invisible/non-interactive windows.
        if (window.hidden || !window.userInteractionEnabled) continue;
        if (!objc_getAssociatedObject(window, &kDGPTTwoFingerPressKey)) {
            UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
                initWithTarget:self action:@selector(handleTwoFingerLongPress:)];
            press.numberOfTouchesRequired = 2;
            press.minimumPressDuration = 1.0;
            press.allowableMovement = 22.0;
            // Keep the host app and the message-cell recognizer working.
            press.cancelsTouchesInView = NO;
            press.delaysTouchesBegan = NO;
            press.delaysTouchesEnded = NO;
            press.delegate = self;
            [window addGestureRecognizer:press];
            objc_setAssociatedObject(window, &kDGPTTwoFingerPressKey, press,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSLog(@"[StandaloneGPT] Two-finger long press installed on %@", window);
        }
        if (!objc_getAssociatedObject(window, &kDGPTTwoFingerDoubleTapKey)) {
            UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc]
                initWithTarget:self action:@selector(handleTwoFingerDoubleTap:)];
            doubleTap.numberOfTouchesRequired = 2;
            doubleTap.numberOfTapsRequired = 2;
            doubleTap.cancelsTouchesInView = NO;
            doubleTap.delaysTouchesBegan = NO;
            doubleTap.delegate = self;
            [window addGestureRecognizer:doubleTap];
            objc_setAssociatedObject(window, &kDGPTTwoFingerDoubleTapKey, doubleTap,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSLog(@"[StandaloneGPT] Two-finger double tap installed on %@", window);
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer;
    (void)otherGestureRecognizer;
    return YES;
}

- (void)openSettingsFromGesture:(UIGestureRecognizer *)gesture {
    UIWindow *window = [gesture.view isKindOfClass:UIWindow.class]
        ? (UIWindow *)gesture.view : gesture.view.window;
    if (!window) {
        NSLog(@"[StandaloneGPT] Settings gesture recognized, but its window was nil");
        return;
    }
    UIWindow *hostWindow = [self presentationWindowForGestureWindow:window];
    if (!hostWindow) {
        NSLog(@"[StandaloneGPT] Settings gesture recognized, but no presentation window found");
        return;
    }
    [self openSettingsFromWindow:hostWindow];
}

- (void)handleTwoFingerLongPress:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    NSLog(@"[StandaloneGPT] Universal two-finger long press recognized");
    [self openSettingsFromGesture:press];
}

- (void)handleTwoFingerDoubleTap:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateRecognized) return;
    NSLog(@"[StandaloneGPT] Universal two-finger double tap recognized");
    [self openSettingsFromGesture:tap];
}

// An event may originate in an elevated alert/keyboard/auxiliary window.
// Present from the app's normal window where possible, using the same scene.
- (UIWindow *)presentationWindowForGestureWindow:(UIWindow *)source {
    if (!source) return nil;
    if (source.rootViewController && source.windowLevel == UIWindowLevelNormal) return source;
    UIApplication *app = [UIApplication sharedApplication];
    NSArray<UIWindow *> *candidates = app.windows ?: @[];
    if (@available(iOS 13.0, *)) {
        if ([source.windowScene isKindOfClass:[UIWindowScene class]]) {
            candidates = source.windowScene.windows;
        }
    }
    UIWindow *fallback = nil;
    for (UIWindow *candidate in candidates) {
        if (candidate.hidden || !candidate.rootViewController) continue;
        if (candidate.windowLevel != UIWindowLevelNormal) continue;
        if (candidate.isKeyWindow) return candidate;
        if (!fallback) fallback = candidate;
    }
    return fallback ?: (source.rootViewController ? source : nil);
}

- (UIViewController *)topControllerInWindow:(UIWindow *)window {
    UIViewController *vc = window.rootViewController;
    for (NSUInteger i = 0; i < 16 && vc; i++) {
        if (vc.presentedViewController) { vc = vc.presentedViewController; continue; }
        if ([vc isKindOfClass:UINavigationController.class]) {
            UIViewController *next = [(UINavigationController *)vc visibleViewController];
            if (next && next != vc) { vc = next; continue; }
        }
        if ([vc isKindOfClass:UITabBarController.class]) {
            UIViewController *next = [(UITabBarController *)vc selectedViewController];
            if (next && next != vc) { vc = next; continue; }
        }
        break;
    }
    return vc;
}

- (void)openSettingsFromWindow:(UIWindow *)window {
    UIViewController *top = [self topControllerInWindow:window];
    if (!top || top.isBeingDismissed || top.isBeingPresented) return;
    if ([top isKindOfClass:DGPTSettingsVC.class]) return;
    UINavigationController *existingNav = top.navigationController;
    if ([existingNav.viewControllers.firstObject isKindOfClass:DGPTSettingsVC.class]) return;

    DGPTSettingsVC *settings = [[DGPTSettingsVC alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [top presentViewController:nav animated:YES completion:nil];
}

@end


@interface DGPTProvidersVC : UITableViewController
@end
@interface DGPTProviderEditorVC : UITableViewController
- (instancetype)initWithProvider:(nullable NSDictionary *)provider;
@end
@interface DGPTModelPickerVC : UITableViewController <UISearchResultsUpdating>
- (instancetype)initWithModels:(NSArray<NSString *> *)models
                      selected:(NSString *)selected
                     selection:(void (^)(NSString *model))selection;
@end

@implementation DGPTSettingsVC {
    NSArray<NSArray<NSDictionary *> *> *_rows;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"聊天助手";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    _rows = @[
        @[@{@"title":@"AI回复", @"key":DGPTManualMenuEnabled, @"type":@"bool"},
          @{@"title":@"读取聊天记录", @"key":DGPTReadChatHistoryEnabled, @"type":@"bool"},
          @{@"title":@"读取条数", @"key":DGPTChatHistoryCount, @"type":@"count"}],
        @[@{@"title":@"AI接口", @"key":@"providers", @"type":@"action"}]
    ];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return _rows.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; return _rows[section].count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    NSDictionary *item = _rows[indexPath.section][indexPath.row];
    NSString *kind = item[@"type"];
    NSString *key = item[@"key"];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = item[@"title"];
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    if ([kind isEqualToString:@"bool"]) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = [[DGPTConfig shared] boolForKey:key];
        toggle.tag = indexPath.section * 100 + indexPath.row;
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        if ([kind isEqualToString:@"count"]) {
            BOOL enabled = [[DGPTConfig shared] boolForKey:DGPTReadChatHistoryEnabled];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 条", (long)[[DGPTConfig shared] historyMessageCount]];
            cell.textLabel.enabled = enabled;
            cell.detailTextLabel.enabled = enabled;
            cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)toggleChanged:(UISwitch *)sender {
    NSInteger section = sender.tag / 100;
    NSInteger row = sender.tag % 100;
    if (section < 0 || section >= (NSInteger)_rows.count || row < 0 || row >= (NSInteger)_rows[section].count) return;
    NSString *key = _rows[section][row][@"key"];
    DGPTConfig *config = [DGPTConfig shared];
    [config setBool:sender.on forKey:key];
    if ([key isEqualToString:DGPTReadChatHistoryEnabled]) [self.tableView reloadData];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = _rows[indexPath.section][indexPath.row];
    NSString *key = item[@"key"];
    if ([item[@"type"] isEqualToString:@"bool"] || [item[@"type"] isEqualToString:@"info"]) return;
    if ([item[@"type"] isEqualToString:@"count"]) {
        if ([[DGPTConfig shared] boolForKey:DGPTReadChatHistoryEnabled]) [self editHistoryCount];
        return;
    }
    if ([key isEqualToString:@"providers"]) {
        [self.navigationController pushViewController:[[DGPTProvidersVC alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
    }
}
- (void)editHistoryCount {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"读取聊天记录条数"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [NSString stringWithFormat:@"%ld", (long)[[DGPTConfig shared] historyMessageCount]];
        field.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        NSCharacterSet *nondigits = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
        NSString *maxValue = [NSString stringWithFormat:@"%lld", (long long)NSIntegerMax];
        NSString *normalized = value;
        while (normalized.length > 1 && [normalized hasPrefix:@"0"]) normalized = [normalized substringFromIndex:1];
        BOOL tooLarge = normalized.length > maxValue.length ||
            (normalized.length == maxValue.length && [normalized compare:maxValue options:NSLiteralSearch] == NSOrderedDescending);
        if (!normalized.length || [normalized rangeOfCharacterFromSet:nondigits].location != NSNotFound ||
            tooLarge || normalized.longLongValue < 1) {
            DGPTAlert(weakSelf, @"条数无效", @"请输入正整数（最大为当前系统的 NSIntegerMax）。");
            return;
        }
        [[DGPTConfig shared] setHistoryMessageCount:(NSInteger)normalized.longLongValue];
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@implementation DGPTProvidersVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AI接口";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addProvider)];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)addProvider {
    [self.navigationController pushViewController:[[DGPTProviderEditorVC alloc] initWithProvider:nil] animated:YES];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? @"服务商和模型" : @"回复设置";
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? [[DGPTConfig shared] providers].count : 2;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"回复消息前缀";
            NSString *prefix = [[DGPTConfig shared] stringForKey:DGPTPrefix];
            cell.detailTextLabel.text = prefix.length > 16 ?
                [[prefix substringToIndex:16] stringByAppendingString:@"…"] : prefix;
        } else {
            cell.textLabel.text = @"提示词模板管理";
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    NSDictionary *p = [[DGPTConfig shared] providers][indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    BOOL active = [p[@"id"] isEqualToString:[[DGPTConfig shared] activeProviderID]];
    cell.textLabel.text = [NSString stringWithFormat:@"%@%@", active ? @"✓ " : @"", p[@"name"]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", p[@"model"], p[@"url"]];
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    return cell;
}
- (void)editReplyPrefix {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"回复消息前缀"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [[DGPTConfig shared] stringForKey:DGPTPrefix];
        field.placeholder = @"可留空";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *value = alert.textFields.firstObject.text ?: @"";
        [[DGPTConfig shared] setString:value forKey:DGPTPrefix];
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        if (indexPath.row == 0) [self editReplyPrefix];
        else [self.navigationController pushViewController:[[DGPTPromptsVC alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
        return;
    }
    NSDictionary *p = [[DGPTConfig shared] providers][indexPath.row];
    [[DGPTConfig shared] selectProviderWithID:p[@"id"]];
    [tableView reloadData];
}
- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section != 0) return;
    NSDictionary *p = [[DGPTConfig shared] providers][indexPath.row];
    [self.navigationController pushViewController:[[DGPTProviderEditorVC alloc] initWithProvider:p] animated:YES];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; return indexPath.section == 0;
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0 || style != UITableViewCellEditingStyleDelete) return;
    NSDictionary *p = [[DGPTConfig shared] providers][indexPath.row];
    [[DGPTConfig shared] removeProviderWithID:p[@"id"]];
    [tableView reloadData];
}
@end

@implementation DGPTProviderEditorVC {
    NSDictionary *_existing;
    UITextField *_nameField;
    UITextField *_urlField;
    UITextField *_keyField;
    UITextField *_modelField;
    BOOL _loading;
    BOOL _testing;
}
- (instancetype)initWithProvider:(NSDictionary *)provider {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _existing = [provider copy];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _existing ? @"编辑服务商" : @"新增服务商";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
    _nameField = [self makeField:_existing[@"name"] placeholder:@"自定义服务商名称" secure:NO];
    _urlField = [self makeField:_existing[@"url"] placeholder:@"https://api.example.com/v1" secure:NO];
    _keyField = [self makeField:nil placeholder:_existing ? @"留空保留原密钥" : @"输入 API Key" secure:YES];
    _modelField = [self makeField:_existing[@"model"] placeholder:@"从接口拉取并选择模型" secure:NO];
}
- (UITextField *)makeField:(NSString *)value placeholder:(NSString *)placeholder secure:(BOOL)secure {
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
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
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
    } else { title = @"模型"; field = _modelField; }
    cell.textLabel.text = title;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    field.frame = CGRectMake(86, 0, MAX(100, cell.contentView.bounds.size.width - 98), 44);
    [cell.contentView addSubview:field];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    if (indexPath.row == 2) { [self testCurrentAPI]; return; }
    if (indexPath.row != 0 || _loading) return;
    NSString *url = [_urlField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *key = _keyField.text.length ? _keyField.text :
        (_existing ? [[DGPTConfig shared] apiKeyForProviderID:_existing[@"id"]] : @"");
    if (!url.length || !key.length) {
        DGPTAlert(self, @"无法拉取", @"请先填写 API URL 和 API Key。"); return;
    }
    _loading = YES;
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [[DGPTClient shared] fetchModelsForURL:url apiKey:key completion:^(NSArray<NSString *> *models, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_loading = NO;
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            if (error || !models.count) {
                DGPTAlert(self, @"拉取失败", error.localizedDescription ?: @"服务商未返回模型列表。"); return;
            }
            DGPTModelPickerVC *picker = [[DGPTModelPickerVC alloc] initWithModels:models
                selected:self->_modelField.text ?: @"" selection:^(NSString *model) {
                    self->_modelField.text = model;
                }];
            [self.navigationController pushViewController:picker animated:YES];
        });
    }];
}
- (void)testCurrentAPI {
    if (_testing) return;
    NSString *url = [_urlField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *model = [_modelField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *key = _keyField.text.length ? _keyField.text :
        (_existing ? [[DGPTConfig shared] apiKeyForProviderID:_existing[@"id"]] : @"");
    if (!url.length || !key.length || !model.length) {
        DGPTAlert(self, @"无法验证", @"请先填写 API URL、API Key 和模型。");
        return;
    }
    _testing = YES;
    NSIndexPath *row = [NSIndexPath indexPathForRow:2 inSection:1];
    [self.tableView reloadRowsAtIndexPaths:@[row] withRowAnimation:UITableViewRowAnimationNone];
    [[DGPTClient shared] testProviderURL:url apiKey:key model:model completion:^(NSString *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_testing = NO;
            if (!self.isViewLoaded || !self.view.window) return;
            [self.tableView reloadRowsAtIndexPaths:@[row] withRowAnimation:UITableViewRowAnimationNone];
            DGPTAlert(self, error ? @"验证失败" : @"验证成功", error.localizedDescription ?: response);
        });
    }];
}
- (void)save {
    NSString *name = [_nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *url = [_urlField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *model = [_modelField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length || !model.length) { DGPTAlert(self, @"无法保存", @"服务商名称和模型不能为空。"); return; }
    NSError *error = nil;
    if (![DGPTClient resolvedEndpointForBaseURL:url error:&error]) {
        DGPTAlert(self, @"URL 错误", error.localizedDescription); return;
    }
    NSString *pid = _existing[@"id"] ?: NSUUID.UUID.UUIDString;
    DGPTConfig *config = [DGPTConfig shared];
    if (!_keyField.text.length && ![config apiKeyForProviderID:pid].length) {
        DGPTAlert(self, @"缺少密钥", @"请填写该服务商的 API Key。"); return;
    }
    if (_keyField.text.length && ![config saveAPIKey:_keyField.text forProviderID:pid]) {
        DGPTAlert(self, @"保存失败", @"API Key 无法写入当前 App 钥匙串。"); return;
    }
    [config upsertProvider:@{@"id":pid, @"name":name, @"url":url, @"model":model}];
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@implementation DGPTModelPickerVC {
    NSArray<NSString *> *_models;
    NSArray<NSString *> *_filtered;
    NSString *_selected;
    void (^_choose)(NSString *);
    UISearchController *_search;
}
- (instancetype)initWithModels:(NSArray<NSString *> *)models selected:(NSString *)selected
                     selection:(void (^)(NSString *))selection {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _models = [models copy]; _filtered = _models;
        _selected = [selected copy]; _choose = [selection copy];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择模型";
    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.searchResultsUpdater = self;
    _search.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = _search;
    self.definesPresentationContext = YES;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    if (!query.length) _filtered = _models;
    else _filtered = [_models filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id value, NSDictionary *bindings) {
        (void)bindings;
        return [value isKindOfClass:NSString.class] &&
            [value rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
    }]];
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return _filtered.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSString *name = _filtered[indexPath.row];
    cell.textLabel.text = name;
    cell.accessoryType = [name isEqualToString:_selected] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *model = _filtered[indexPath.row];
    if (_choose) _choose(model);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

// Restored from the original named prompt-template list. Uses its original keys
// and storage suite so previously saved templates remain available.
@implementation DGPTPromptsVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"提示词模板";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addPreset)];
}
- (NSArray<NSDictionary *> *)presets {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (id value in [[DGPTConfig shared] arrayForKey:DGPTPromptPresets]) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *item = (NSDictionary *)value;
        if ([item[@"name"] isKindOfClass:NSString.class] &&
            [item[@"prompt"] isKindOfClass:NSString.class]) [result addObject:item];
    }
    return result;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return self.presets.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return @"点击模板启用，再次点击取消。左滑可编辑或删除；选中的提示词会用于手动对话及气泡 AI 回复。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSDictionary *item = self.presets[indexPath.row];
    NSString *name = item[@"name"];
    cell.textLabel.text = name;
    cell.detailTextLabel.text = item[@"prompt"];
    cell.detailTextLabel.numberOfLines = 2;
    if ([name isEqualToString:[[DGPTConfig shared] stringForKey:DGPTActivePrompt]])
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *name = self.presets[indexPath.row][@"name"];
    DGPTConfig *config = [DGPTConfig shared];
    NSString *active = [config stringForKey:DGPTActivePrompt];
    [config setString:[name isEqualToString:active] ? @"" : name forKey:DGPTActivePrompt];
    [tableView reloadData];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath; return YES;
}
- (NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    __weak typeof(self) weakSelf = self;
    UITableViewRowAction *remove = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive
        title:@"删除" handler:^(__unused UITableViewRowAction *action, NSIndexPath *path) {
        NSMutableArray *items = [weakSelf.presets mutableCopy];
        if (path.row >= (NSInteger)items.count) return;
        NSString *name = items[path.row][@"name"];
        [items removeObjectAtIndex:path.row];
        DGPTConfig *config = [DGPTConfig shared];
        [config setArray:items forKey:DGPTPromptPresets];
        if ([name isEqualToString:[config stringForKey:DGPTActivePrompt]])
            [config setString:@"" forKey:DGPTActivePrompt];
        [weakSelf.tableView reloadData];
    }];
    UITableViewRowAction *edit = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal
        title:@"编辑" handler:^(__unused UITableViewRowAction *action, NSIndexPath *path) {
        NSArray *items = weakSelf.presets;
        if (path.row < (NSInteger)items.count) [weakSelf editPreset:items[path.row]];
    }];
    return @[remove, edit];
}
- (void)addPreset { [self editPreset:nil]; }
- (void)editPreset:(NSDictionary *)existing {
    NSString *oldName = existing[@"name"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:(existing ? @"编辑提示词模板" : @"新增提示词模板")
        message:@"输入模板名称和内容。" preferredStyle:UIAlertControllerStyleAlert];
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
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *prompt = [alert.textFields.lastObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length || !prompt.length) {
            DGPTAlert(weakSelf, @"不能保存", @"名称和提示词内容均不能为空。"); return;
        }
        NSMutableArray *items = [weakSelf.presets mutableCopy];
        for (NSDictionary *item in items) {
            if ([item[@"name"] isEqualToString:name] && ![item[@"name"] isEqualToString:oldName]) {
                DGPTAlert(weakSelf, @"名称重复", @"请换一个模板名称。"); return;
            }
        }
        BOOL found = NO;
        for (NSUInteger i = 0; i < items.count; i++) {
            if (oldName && [items[i][@"name"] isEqualToString:oldName]) {
                items[i] = @{@"name":name, @"prompt":prompt}; found = YES; break;
            }
        }
        if (!found) [items addObject:@{@"name":name, @"prompt":prompt}];
        DGPTConfig *config = [DGPTConfig shared];
        [config setArray:items forKey:DGPTPromptPresets];
        if (oldName && [[config stringForKey:DGPTActivePrompt] isEqualToString:oldName])
            [config setString:name forKey:DGPTActivePrompt];
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
