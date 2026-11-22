#import "AxsWeChatGPTMessageReply.h"
#import "AxsWeChatGPTClient.h"
#import "AxsWeChatGPTConfig.h"
#import "AxsWeChatGPTMenuInjector.h"
#import "AxsWeChatGPTWeChatBridge.h"
// The analysis page lives in Controllers/; it is looked up by class name so this
// source file only depends on the router-free, UI-free part of the plugin.
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdlib.h>
#include <string.h>


// Runtime type checks avoid arbitrary KVC/private message-method invocations.
static id axs_wechatgpt_readValue(id object, NSString *name) {
    if (!object || !name.length) return nil;
    Ivar ivar = class_getInstanceVariable([object class], name.UTF8String);
    if (!ivar) ivar = class_getInstanceVariable([object class],
        [@"_" stringByAppendingString:name].UTF8String);
    if (ivar && ivar_getTypeEncoding(ivar)[0] == '@') {
        @try { return object_getIvar(object, ivar); }
        @catch (__unused NSException *e) { return nil; }
    }
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([object class], selector);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char *type = method_copyReturnType(method);
    BOOL objectReturn = type && type[0] == '@';
    if (type) free(type);
    if (!objectReturn) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *e) { return nil; }
}

static long long axs_wechatgpt_readNumber(id object, NSString *name) {
    if (!object || !name.length) return 0;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([object class], selector);
    if (method && method_getNumberOfArguments(method) == 2) {
        char *ret = method_copyReturnType(method);
        BOOL numeric = ret && strchr("cCsSiIlLqQB", ret[0]) != NULL;
        if (ret) free(ret);
        if (numeric) {
            @try { return ((long long (*)(id, SEL))objc_msgSend)(object, selector); }
            @catch (__unused NSException *e) { return 0; }
        }
    }
    Ivar ivar = class_getInstanceVariable([object class], name.UTF8String);
    if (!ivar) ivar = class_getInstanceVariable([object class],
        [@"_" stringByAppendingString:name].UTF8String);
    if (ivar) {
        const char *type = ivar_getTypeEncoding(ivar);
        if (type && strchr("cCsSiIlLqQB", type[0])) {
            size_t width = 0;
            switch (type[0]) {
                case 'c': case 'C': case 'B': width=1; break;
                case 's': case 'S': width=2; break;
                case 'i': case 'I': width=4; break;
                case 'l': case 'L': width=sizeof(long); break;
                case 'q': case 'Q': width=8; break;
            }
            if (width) {
                unsigned long long n=0;
                memcpy(&n, ((const uint8_t *)(__bridge const void *)object) + ivar_getOffset(ivar), width);
                return (long long)n;
            }
        }
    }
    return 0;
}

static NSString *axs_wechatgpt_readString(id object, NSString *name) {
    id value = axs_wechatgpt_readValue(object, name);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static id axs_wechatgpt_extractWrap(id cell) {
    if (!cell) return nil;
    Class wrapClass = objc_getClass("CMessageWrap");
    if (!wrapClass) return nil;
    for (NSString *name in @[@"m_msgWrap", @"msgWrap", @"messageWrap", @"m_messageWrap", @"message", @"getMessageWrap", @"getMsgWrap"]) {
        id wrap = axs_wechatgpt_readValue(cell, name);
        if ([wrap isKindOfClass:wrapClass]) return wrap;
    }
    for (NSString *name in @[@"viewModel", @"m_viewModel", @"messageModel", @"m_messageModel", @"m_msgViewModel"]) {
        id model = axs_wechatgpt_readValue(cell, name);
        for (NSString *key in @[@"m_msgWrap", @"msgWrap", @"messageWrap", @"message"]) {
            id wrap = axs_wechatgpt_readValue(model, key);
            if ([wrap isKindOfClass:wrapClass]) return wrap;
        }
    }
    // Group-chat cells often own an intermediate content/container view.
    // Search only a small bounded subtree, with typed CMessageWrap checks.
    if ([cell isKindOfClass:UIView.class]) {
        NSMutableArray<UIView *> *frontier = [NSMutableArray arrayWithObject:cell];
        NSUInteger scanned = 0;
        for (NSUInteger depth=0; depth<4 && frontier.count && scanned<72; depth++) {
            NSMutableArray<UIView *> *next=[NSMutableArray array];
            for (UIView *parent in frontier) {
                for (UIView *child in parent.subviews) {
                    if (++scanned > 72) break;
                    for (NSString *key in @[@"m_msgWrap", @"msgWrap", @"messageWrap",
                                           @"m_messageWrap", @"message", @"m_msg",
                                           @"getMessageWrap", @"getMsgWrap"]) {
                        id result=axs_wechatgpt_readValue(child,key);
                        if ([result isKindOfClass:wrapClass]) return result;
                    }
                    if (child.subviews.count && depth<3) [next addObject:child];
                }
                if (scanned>72) break;
            }
            frontier=next;
        }
    }
    return nil;
}

static NSString *axs_wechatgpt_messageText(id wrap) {
    if (!wrap || axs_wechatgpt_readNumber(wrap, @"m_uiMessageType") != 1) return nil;
    NSString *content = axs_wechatgpt_readString(wrap, @"m_nsContent");
    if (!content.length || content.length > 12000) return nil;
    NSRange range = [content rangeOfString:@":\n"];
    NSString *from = axs_wechatgpt_readString(wrap, @"m_nsFromUsr");
    NSString *to = axs_wechatgpt_readString(wrap, @"m_nsToUsr");
    if (([from hasSuffix:@"@chatroom"] || [to hasSuffix:@"@chatroom"]) &&
        range.location != NSNotFound && range.location > 0 && range.location < 160)
        content = [content substringFromIndex:NSMaxRange(range)];
    return content;
}

// Different WeChat builds expose message models through different views.
// Only accept visible text as a fallback for a view whose runtime class
// clearly identifies it as a text-message cell; never guess from a random
// UILabel elsewhere in WeChat. In this case the send target stays unknown.
static BOOL axs_wechatgpt_isTextMessageCellView(UIView *view) {
    for (Class cls = [view class]; cls && cls != UIView.class; cls = class_getSuperclass(cls)) {
        NSString *name = NSStringFromClass(cls);
        if ([name containsString:@"TextMessageCellView"] ||
            [name containsString:@"TextMessageCell"] ||
            [name containsString:@"TextMsgCellView"]) return YES;
    }
    return NO;
}

static void axs_wechatgpt_findVisibleText(UIView *view, NSString **best) {
    if (!view || view.hidden || view.alpha < 0.1) return;
    NSString *candidate = nil;
    if ([view isKindOfClass:UILabel.class]) candidate = ((UILabel *)view).text;
    else if ([view isKindOfClass:UITextView.class] && !((UITextView *)view).editable)
        candidate = ((UITextView *)view).text;
    candidate = [candidate stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (candidate.length && candidate.length <= 12000 && candidate.length > (*best).length) *best = candidate;
    for (UIView *child in view.subviews) axs_wechatgpt_findVisibleText(child, best);
}

static NSString *axs_wechatgpt_textForCell(id cell) {
    if (![cell isKindOfClass:UIView.class]) return nil;
    NSString *text = axs_wechatgpt_messageText(axs_wechatgpt_extractWrap(cell));
    if (text.length) return text;
    BOOL hasTextView = axs_wechatgpt_isTextMessageCellView((UIView *)cell);
    if (!hasTextView) {
        for (UIView *child in ((UIView *)cell).subviews) {
            if (axs_wechatgpt_isTextMessageCellView(child)) { hasTextView=YES; break; }
        }
    }
    if (!hasTextView) return nil;
    NSString *visibleText = nil;
    axs_wechatgpt_findVisibleText((UIView *)cell, &visibleText);
    return visibleText;
}

// UI helpers are deliberately UIKit-only. The manual AI reply must never call
// CMessageMgr, sendText: or any private WeChat send API.
static UIViewController *axs_wechatgpt_topInWindow(UIWindow *window) {
    UIViewController *controller = window.rootViewController;
    for (NSUInteger i = 0; controller && i < 24; i++) {
        if (controller.presentedViewController) {
            controller = controller.presentedViewController;
        } else if ([controller isKindOfClass:UINavigationController.class] &&
                   ((UINavigationController *)controller).visibleViewController) {
            controller = ((UINavigationController *)controller).visibleViewController;
        } else if ([controller isKindOfClass:UITabBarController.class] &&
                   ((UITabBarController *)controller).selectedViewController) {
            controller = ((UITabBarController *)controller).selectedViewController;
        } else break;
    }
    return controller;
}

static void axs_wechatgpt_showNotice(UIWindow *window, NSString *title, NSString *description) {
    UIViewController *host = axs_wechatgpt_topInWindow(window);
    if (!host || host.isBeingDismissed || host.isBeingPresented) {
        NSLog(@"[StandaloneGPT] %@: %@", title, description);
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"AI 回复"
        message:description ?: @"操作完成" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [host presentViewController:alert animated:YES completion:nil];
}
static void axs_wechatgpt_showAnalysisError(UIWindow *window, NSString *description) {
    axs_wechatgpt_showNotice(window, @"AI 分析无法打开", description);
}

static BOOL axs_wechatgpt_viewIsVisible(UIView *view, UIWindow *window) {
    if (!view || !window || view.window != window) return NO;
    for (UIView *v = view; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.05) return NO;
        if (v == window) break;
    }
    return YES;
}

// Find the bottom, visible, editable text input in the current chat screen.
// Refuse to guess an editor in a search/alert view or another window.
static void axs_wechatgpt_collectTextEditors(UIView *view, UIWindow *window,
                                   NSMutableArray<UITextView *> *editors, NSUInteger depth) {
    if (!view || depth > 45 || view.hidden || view.alpha < 0.05) return;
    if ([view isKindOfClass:UITextView.class]) {
        UITextView *editor = (UITextView *)view;
        if (editor.editable && editor.userInteractionEnabled && editor.bounds.size.width >= 90 &&
            editor.bounds.size.height >= 20 && editor.bounds.size.height <= 260 &&
            axs_wechatgpt_viewIsVisible(editor, window)) {
            BOOL searchField = NO;
            for (UIView *v = editor; v && v != window; v = v.superview) {
                NSString *name = NSStringFromClass(v.class).lowercaseString;
                if ([name containsString:@"searchbar"] || [name containsString:@"searchfield"]) {
                    searchField = YES;
                    break;
                }
            }
            CGRect rect = [editor convertRect:editor.bounds toView:window];
            if (!searchField && (!CGRectIsNull(rect) && !CGRectIsInfinite(rect)) &&
                CGRectIntersectsRect(rect, window.bounds) &&
                CGRectGetMidY(rect) >= CGRectGetHeight(window.bounds) * 0.33 &&
                CGRectGetMaxY(rect) <= CGRectGetHeight(window.bounds) + 5) {
                [editors addObject:editor];
            }
        }
    }
    for (UIView *subview in view.subviews) {
        axs_wechatgpt_collectTextEditors(subview, window, editors, depth + 1);
    }
}

static UITextView *axs_wechatgpt_chatInputForWindow(UIWindow *window) {
    if (!window || window.hidden || !window.rootViewController) return nil;
    NSMutableArray<UITextView *> *editors = [NSMutableArray array];
    axs_wechatgpt_collectTextEditors(window.rootViewController.view, window, editors, 0);
    UITextView *best = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    for (UITextView *editor in editors) {
        CGRect rect = [editor convertRect:editor.bounds toView:window];
        CGFloat score = CGRectGetMidY(rect);
        // Prefer the actual chat composer; custom WeChat classes change names
        // between versions, so this is only a preference, not a dependency.
        for (UIView *ancestor = editor; ancestor && ancestor != window;
             ancestor = ancestor.superview) {
            NSString *name = NSStringFromClass(ancestor.class).lowercaseString;
            if ([name containsString:@"inputtool"] || [name containsString:@"growtext"] ||
                [name containsString:@"chatinput"]) { score += 200; break; }
        }
        if (score > bestScore) { best = editor; bestScore = score; }
    }
    return best;
}

// Replace the current chat draft with AI content. No WeChat send API is called.
// Only write after AI succeeds. Do not compare conversation/session identifiers.
static BOOL axs_wechatgpt_fillChatInput(UITextView *editor, UIWindow *window, NSString *newText) {
    if (!editor || !newText.length || !axs_wechatgpt_viewIsVisible(editor, window) ||
        !editor.editable || !editor.userInteractionEnabled) return NO;
    // Requirement: clear any existing draft, then fill with ONLY the AI reply.
    // Do this on the main thread; publish only the final edit to the delegate.
    editor.text = newText;
    editor.selectedRange = NSMakeRange(newText.length, 0);
    id<UITextViewDelegate> delegate = editor.delegate;
    if ([delegate respondsToSelector:@selector(textViewDidChange:)]) {
        [delegate textViewDidChange:editor];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:editor];
    [editor becomeFirstResponder];
    return YES;
}

@interface AxsWeChatGPTMessageReply ()
@property (nonatomic, copy) NSString *capturedText;
@property (nonatomic, strong) id capturedWrap;
@property (nonatomic, weak) UIWindow *capturedWindow;
@property (nonatomic, weak) UIView *capturedCell;
@property (nonatomic, assign) NSTimeInterval capturedAt;
@property (nonatomic, assign) NSUInteger capturedCount;
@property (nonatomic, assign) NSUInteger insertedCount;
@property (nonatomic, assign) NSUInteger requestSerial;
@property (nonatomic, assign) NSUInteger lastContextCount;
@property (nonatomic, assign) BOOL generatingReply;
@property (nonatomic, copy) NSString *lastMenuStatus;
@end

@implementation AxsWeChatGPTMessageReply
+ (instancetype)shared {
    static AxsWeChatGPTMessageReply *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [AxsWeChatGPTMessageReply new]; });
    return instance;
}
- (NSString *)menuDiagnosticSummary {
    return [NSString stringWithFormat:
        @"模式：仅长按气泡手动 AI 回复\n气泡消息捕获：%lu 次\n菜单插入：%lu 次\n"
         @"正在生成：%@\n历史读取：%@\n最后读取：%lu 条（双方）\n最后状态：%@\n\n%@",
        (unsigned long)self.capturedCount, (unsigned long)self.insertedCount,
        self.generatingReply ? @"是" : @"否",
        [[AxsWeChatGPTConfig shared] boolForKey:AxsWeChatGPTReadChatHistoryEnabled] ? @"开启" : @"关闭",
        (unsigned long)self.lastContextCount,
        self.lastMenuStatus ?: @"等待点击 AI 回复",
        [AxsWeChatGPTNativeMenu diagnosticSummary]];
}

- (void)captureNativeMenuCell:(id)cell {
    if (![[AxsWeChatGPTConfig shared] boolForKey:AxsWeChatGPTManualMenuEnabled]) return;
    if (![cell isKindOfClass:UIView.class]) return;
    id messageWrap = axs_wechatgpt_extractWrap(cell);
    NSString *text = [axs_wechatgpt_textForCell(cell) copy];
    if (!text.length && messageWrap)
        text = [[AxsWeChatGPTWeChatBridge messagePlaceholderForWrap:messageWrap] copy];
    if (!text.length) {
        self.lastMenuStatus = @"无法取得当前气泡消息对象";
        return;
    }
    self.capturedText = text;
    self.capturedWrap = messageWrap;
    self.capturedWindow = ((UIView *)cell).window;
    self.capturedCell = cell;
    self.capturedAt = NSDate.date.timeIntervalSince1970;
    self.capturedCount++;
    self.lastMenuStatus = @"已捕获气泡消息，等待原生菜单渲染";
}

- (BOOL)hasFreshNativeMenuMessage {
    if (![[AxsWeChatGPTConfig shared] boolForKey:AxsWeChatGPTManualMenuEnabled]) return NO;
    if (!self.capturedText.length || !self.capturedWindow) return NO;
    if (NSDate.date.timeIntervalSince1970 - self.capturedAt > 45.0) return NO;
    return YES;
}

- (void)nativeMenuItemInserted {
    self.insertedCount++;
    self.lastMenuStatus = @"AI 回复与 AI 分析已追加到原生气泡菜单";
}

- (void)activateCapturedNativeAnalysis {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self activateCapturedNativeAnalysis]; });
        return;
    }
    if (![self hasFreshNativeMenuMessage]) return;
    UIWindow *window = self.capturedWindow;
    UIView *cell = self.capturedCell;
    id wrap = self.capturedWrap;
    self.capturedWrap = nil;
    self.capturedText = nil;
    self.capturedAt = 0;
    if (!window || !cell) return;
    NSDictionary *context = [AxsWeChatGPTWeChatBridge sessionContextForCell:cell selectedWrap:wrap];
    NSString *failure = context[@"error"];
    if (failure.length) { axs_wechatgpt_showAnalysisError(window, failure); return; }
    // Dismiss WeChat's native long-press menu before modal presentation.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.28 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        Class analysisClass = NSClassFromString(@"AxsWeChatGPTAnalysisViewController");
        SEL present = NSSelectorFromString(@"presentWithSessionContext:window:");
        if (analysisClass && [analysisClass respondsToSelector:present]) {
            ((void (*)(id, SEL, NSDictionary *, UIWindow *))objc_msgSend)(analysisClass, present,
                context, window);
        }
    });
}

- (void)activateCapturedNativeReply {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self activateCapturedNativeReply]; });
        return;
    }
    if (![self hasFreshNativeMenuMessage]) return;
    NSString *selectedText = [self.capturedText copy];
    UIWindow *window = self.capturedWindow;
    UIView *cell = self.capturedCell;
    id tappedWrap = self.capturedWrap;
    self.capturedWrap = nil;
    self.capturedText = nil;
    self.capturedAt = 0;
    if (!window || !cell || !selectedText.length) return;
    NSUInteger serial = ++self.requestSerial;
    AxsWeChatGPTConfig *settings = [AxsWeChatGPTConfig shared];
    BOOL includeHistory = [settings boolForKey:AxsWeChatGPTReadChatHistoryEnabled];
    NSUInteger wanted = (NSUInteger)[settings historyMessageCount];

    // Allow the native menu to close before locating WeChat's input field.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (serial != self.requestSerial) return;
        UITextView *input = axs_wechatgpt_chatInputForWindow(window);
        if (!input) { self.lastMenuStatus = @"没找到微信聊天输入框"; return; }
        NSArray<NSDictionary *> *history = @[];
        BOOL group = NO;
        self.lastContextCount = 0;
        if (includeHistory) {
            NSDictionary *snapshot = [AxsWeChatGPTWeChatBridge recentOpenChatHistoryForCell:cell
                selectedWrap:tappedWrap limit:wanted];
            history = [snapshot[@"messages"] isKindOfClass:NSArray.class] ? snapshot[@"messages"] : @[];
            group = [snapshot[@"isGroup"] boolValue];
            self.lastContextCount = history.count;
            if (!history.count) {
                self.lastMenuStatus = snapshot[@"error"] ?: @"历史读取失败，未请求 AI";
                return;
            }
        }
        NSMutableArray<NSDictionary *> *messages = [NSMutableArray array];
        if (includeHistory) {
            NSMutableString *transcript = [NSMutableString string];
            NSUInteger mineCount = 0, otherCount = 0, unknownCount = 0;
            for (NSDictionary *entry in history) {
                NSString *content = entry[@"content"];
                if (![content isKindOfClass:NSString.class] || !content.length) continue;
                NSString *direction = entry[@"direction"];
                NSString *speaker = @"发送者未识别";
                if ([direction isEqualToString:@"mine"]) {
                    speaker = @"我"; ++mineCount;
                } else if ([direction isEqualToString:@"other"]) {
                    speaker = @"对方"; ++otherCount;
                    if (group && [entry[@"sender"] isKindOfClass:NSString.class] &&
                        [entry[@"sender"] length] < 160 && [entry[@"sender"] length])
                        speaker = [NSString stringWithFormat:@"群成员 %@", entry[@"sender"]];
                } else { ++unknownCount; }
                [transcript appendFormat:@"%@：%@\n", speaker, content];
            }
            [messages addObject:@{ @"role":@"system", @"content":
                @"你是微信聊天回复助手。下面的「我」表示当前微信账号主人，"
                 @"「对方」表示聊天联系人；未知发送者不可随意归因。"
                 @"结合双方真实消息起草简短自然的回复，只输出回复正文，不捏造事实。" }];
            [messages addObject:@{ @"role":@"user", @"content":[NSString stringWithFormat:
                @"已读取%lu条文字聊天（我%lu条，对方%lu条，未识别%lu条，按时间排序）：\n%@\n"
                 @"请根据这些上下文替我回复选中的消息：\n%@",
                (unsigned long)history.count, (unsigned long)mineCount,
                (unsigned long)otherCount, (unsigned long)unknownCount,
                transcript, selectedText] }];
        } else {
            [messages addObject:@{ @"role":@"system", @"content":
                @"你是微信聊天的回复助手。只根据点选的这条文字消息起草简短自然的回复。不要编造其他上下文，只输出回复正文。" }];
            [messages addObject:@{ @"role":@"user", @"content":
                [NSString stringWithFormat:@"请替我回复这条微信消息：\n%@", selectedText] }];
        }
        self.generatingReply = YES;
        self.lastMenuStatus = includeHistory ?
            [NSString stringWithFormat:@"已读取 %lu 条，等待 AI", (unsigned long)history.count] :
            @"未启用历史读取，等待 AI";
        __weak UITextView *weakInput = input;
        __weak UIWindow *weakWindow = window;
        [[AxsWeChatGPTClient shared] askWithMessages:messages completion:^(NSString *answer, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (serial != self.requestSerial) return;
                self.generatingReply = NO;
                if (error || !answer.length) {
                    self.lastMenuStatus = [NSString stringWithFormat:@"AI 请求失败：%@",
                        error.localizedDescription ?: @"没有返回文字"];
                    return;
                }
                NSString *trimmed = [answer stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (!trimmed.length) { self.lastMenuStatus = @"AI 返回空内容"; return; }
                NSString *draft = [[[AxsWeChatGPTConfig shared] stringForKey:AxsWeChatGPTPrefix] stringByAppendingString:trimmed];
                BOOL filled = axs_wechatgpt_fillChatInput(weakInput, weakWindow, draft);
                self.lastMenuStatus = filled ? @"回复已填入（未发送）" : @"输入框已失效，未写入";
            });
        }];
    });
}

@end
