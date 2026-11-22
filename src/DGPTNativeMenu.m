#import "DGPTNativeMenu.h"
#import "DGPTMessageReply.h"
#import "DGPTConfig.h"
#import "DGPTWeChatBridge.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdlib.h>
#include <string.h>

// IMPORTANT: The first integration point is operationMenuItems, not a menu
// renderer. Different WeChat releases have entirely different menu views.
// generateOperationMenu is observed to diagnose whether that path is reached.
// Every hook is limited to text-cell code and checked at runtime. No app ID.
static NSMutableSet<NSString *> *gInstalled;
static NSString *gLastStatus;
static NSString *gLastCollection;
static NSUInteger gOperationCalls;
static NSUInteger gGenerationCalls;
static NSUInteger gItemsInserted;
static NSUInteger gModelFailures;
static __thread NSUInteger gInsideOperation;

static void DGPTStatus(NSString *message) {
    gLastStatus = [message copy];
    NSLog(@"[聊天助手][BubbleMenu] %@", message);
}

static Method DGPTOwnMethod(Class cls, SEL selector) {
    if (!cls || !selector) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method match = NULL;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) { match = methods[i]; break; }
    }
    if (methods) free(methods);
    return match;
}

static char DGPTReturnKind(Method method) {
    if (!method) return '\0';
    char *type = method_copyReturnType(method);
    char result = type && type[0] ? type[0] : '\0';
    if (type) free(type);
    return result;
}

static char DGPTArgKind(Method method, unsigned int argument) {
    if (!method || argument >= method_getNumberOfArguments(method)) return '\0';
    char *type = method_copyArgumentType(method, argument);
    char result = type && type[0] ? type[0] : '\0';
    if (type) free(type);
    return result;
}

static BOOL DGPTSignature(Method method, char returnKind, unsigned int argumentCount) {
    if (!method || method_getNumberOfArguments(method) != argumentCount) return NO;
    char *ret = method_copyReturnType(method);
    BOOL ok = ret && ret[0] == returnKind;
    if (ret) free(ret);
    return ok;
}

static NSString *DGPTMethodKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%@/%@", NSStringFromClass(cls), NSStringFromSelector(selector)];
}

// Only hook the original text bubble family. Group-chat bubble classes
// are deliberately not hooked; this plugin does not add group menu actions.
static BOOL DGPTIsMessageBubbleClass(Class cls) {
    if (!cls || ![cls isSubclassOfClass:UIView.class]) return NO;
    for (Class c=cls; c && c != UIView.class; c=class_getSuperclass(c)) {
        NSString *name=NSStringFromClass(c);
        if ([name isEqualToString:@"TextMessageCellView"] ||
            [name isEqualToString:@"TextMessageCell"] ||
            [name isEqualToString:@"TextMsgCellView"]) return YES;
    }
    return NO;
}
static BOOL DGPTMenuEnabledForCell(id cell) {
    return [cell isKindOfClass:UIView.class] &&
        DGPTIsMessageBubbleClass([cell class]) &&
        [[DGPTConfig shared] boolForKey:DGPTManualMenuEnabled] &&
        [DGPTWeChatBridge isSingleChatCell:(UIView *)cell];
}

// Support UIKit-style responder selectors without replacing the original
// message-menu long-press gesture. The selected cell is re-captured on click.
static SEL DGPTActionSelector(void) { return NSSelectorFromString(@"dgptStandaloneAIReply:"); }
static SEL DGPTAnalysisActionSelector(void) { return NSSelectorFromString(@"dgptStandaloneAIAnalysis:"); }
static void DGPTActionHandler(id cell, SEL command, id sender) {
    (void)command; (void)sender;
    if (DGPTMenuEnabledForCell(cell)) {
        [[DGPTMessageReply shared] captureNativeMenuCell:cell];
        [[DGPTMessageReply shared] activateCapturedNativeReply];
    }
}
static void DGPTAnalysisActionHandler(id cell, SEL command, id sender) {
    (void)command; (void)sender;
    if (DGPTMenuEnabledForCell(cell)) {
        [[DGPTMessageReply shared] captureNativeMenuCell:cell];
        [[DGPTMessageReply shared] activateCapturedNativeAnalysis];
    }
}
static void DGPTAddActionToCell(Class cls) {
    if (!cls) return;
    SEL reply = DGPTActionSelector(), analysis = DGPTAnalysisActionSelector();
    class_addMethod(cls, reply, (IMP)DGPTActionHandler, "v@:@");
    class_addMethod(cls, analysis, (IMP)DGPTAnalysisActionHandler, "v@:@");
    // canPerformAction: is an allowlist in some WeChat builds.
    SEL can = @selector(canPerformAction:withSender:);
    Method inherited = class_getInstanceMethod(cls, can);
    if (!inherited || method_getNumberOfArguments(inherited) != 4 ||
        DGPTArgKind(inherited, 2) != ':' || DGPTArgKind(inherited, 3) != '@') return;
    char ret = DGPTReturnKind(inherited);
    if (ret != 'B' && ret != 'c') return;
    NSString *key = DGPTMethodKey(cls, can);
    if ([gInstalled containsObject:key]) return;
    IMP old = method_getImplementation(inherited);
    IMP replacement = imp_implementationWithBlock(^BOOL(id obj, SEL requested, id sender) {
        if ((requested == reply || requested == analysis) && DGPTMenuEnabledForCell(obj)) return YES;
        return ((BOOL (*)(id, SEL, SEL, id))old)(obj, can, requested, sender);
    });
    if (DGPTOwnMethod(cls, can)) method_setImplementation(inherited, replacement);
    else if (!class_addMethod(cls, can, replacement, method_getTypeEncoding(inherited))) return;
    [gInstalled addObject:key];
}

static BOOL DGPTIsOurItem(id item) {
    if (!item) return NO;
    @try {
        if ([item respondsToSelector:@selector(title)]) {
            id title = ((id (*)(id, SEL))objc_msgSend)(item, @selector(title));
            if (![title isKindOfClass:NSString.class]) return NO;
            NSString *normalized = [[[[(NSString *)title
                stringByReplacingOccurrencesOfString:@" " withString:@""]
                stringByReplacingOccurrencesOfString:@"\u2060" withString:@""]
                stringByReplacingOccurrencesOfString:@"\n" withString:@""]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            return [normalized containsString:@"AI回复"] || [normalized containsString:@"AI分析"];
        }
    } @catch (__unused NSException *exception) {}
    return NO;
}

static BOOL DGPTIsNativeMenuItem(id item) {
    if (!item || [item isKindOfClass:NSString.class] ||
        [item isKindOfClass:NSNumber.class] || [item isKindOfClass:NSDictionary.class]) return NO;
    NSString *name = NSStringFromClass([item class]);
    return [name containsString:@"MenuItem"] || [item isKindOfClass:UIMenuItem.class] ||
           [item isKindOfClass:UIAction.class];
}

static BOOL DGPTBlockArgument(Method method, unsigned int index) {
    if (!method || index >= method_getNumberOfArguments(method)) return NO;
    char *type = method_copyArgumentType(method, index);
    // @? denotes an ObjC block; a plain @ may mean an arbitrary object and
    // handing it a callback block can crash when the native menu is clicked.
    BOOL yes = type && type[0] == '@' && type[1] == '?';
    if (type) free(type);
    return yes;
}

// The native bubble menu has its OWN layout and icon fields. A Unicode icon
// inside `title` is just text, so the old implementation rendered it INLINE.
// Prefer the same icon-bearing initializer used by the native menu model, and
// borrow an existing on-screen menu SVG name rather than inventing an asset.
// Never set unknown private ivars or globally hook the menu renderer.
static UIImage *DGPTMenuImage(BOOL analysis) {
    UIImage *image = [UIImage systemImageNamed:(analysis ? @"chart.bar.fill" : @"bubble.left.fill")];
    if (!image) image = [UIImage systemImageNamed:(analysis ? @"magnifyingglass" : @"bubble.left")];
    return image;
}

static NSString *DGPTPlainTitle(id item) {
    if (!item || ![item respondsToSelector:@selector(title)]) return nil;
    Method getter = class_getInstanceMethod([item class], @selector(title));
    if (!DGPTSignature(getter, '@', 2)) return nil;
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(item, @selector(title));
        return [value isKindOfClass:NSString.class] ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    } @catch (__unused NSException *exception) { return nil; }
}

static NSString *DGPTNativeSVGName(id item) {
    if (!DGPTIsNativeMenuItem(item)) return nil;
    for (NSString *name in @[@"svgName", @"iconName", @"imageName"]) {
        SEL getter = NSSelectorFromString(name);
        if (![item respondsToSelector:getter]) continue;
        Method method = class_getInstanceMethod([item class], getter);
        if (!DGPTSignature(method, '@', 2)) continue;
        @try {
            id value = ((id (*)(id, SEL))objc_msgSend)(item, getter);
            if ([value isKindOfClass:NSString.class] && [value length] > 0) return value;
        } @catch (__unused NSException *exception) {}
    }
    return nil;
}

// Search only the original operationMenuItems, never scan the ObjC runtime or
// unrelated views. Icon reuse is deliberately bounded to the SAME menu model.
static NSString *DGPTNativeIconForAction(NSArray *items, BOOL analysis) {
    NSMutableArray *all = [NSMutableArray array];
    for (id part in items) {
        if ([part isKindOfClass:NSArray.class]) [all addObjectsFromArray:(NSArray *)part];
        else [all addObject:part];
    }
    NSArray *priority = analysis ? @[@"搜一搜", @"翻译", @"多选"] : @[@"引用", @"转发", @"复制"];
    for (NSString *preferred in priority) {
        for (id item in all) {
            if ([DGPTPlainTitle(item) isEqualToString:preferred]) {
                NSString *svg = DGPTNativeSVGName(item);
                if (svg.length) return svg;
            }
        }
    }
    // Even when the translated menu labels change, prefer a known-working
    // native asset over a guessed SVG identifier.
    for (id item in all) {
        NSString *svg = DGPTNativeSVGName(item);
        if (svg.length) return svg;
    }
    return nil;
}

static BOOL DGPTArgIsUIImage(Method method, unsigned int index) {
    if (!method || index >= method_getNumberOfArguments(method)) return NO;
    char *type = method_copyArgumentType(method, index);
    BOOL result = type && strstr(type, "UIImage") != NULL;
    if (type) free(type);
    return result;
}

// Use actual native icon field (svgName / icon) rather than inserting emoji
// beside the label. If the target WeChat version has no compatible icon API,
// fall back to a two-line label so the glyph is ABOVE the title, not inline.
static id DGPTNewItemLike(id example, id cell, NSString *title, BOOL analysis, NSString *svgName) {
    if (!DGPTIsNativeMenuItem(example)) return nil;
    Class cls = [example class];
    UIImage *image = DGPTMenuImage(analysis);
    __weak id weakCell = cell;
    void (^callback)(id) = ^(__unused id sender) {
        id strongCell = weakCell;
        if (!DGPTMenuEnabledForCell(strongCell)) return;
        [[DGPTMessageReply shared] captureNativeMenuCell:strongCell];
        if (analysis) [[DGPTMessageReply shared] activateCapturedNativeAnalysis];
        else [[DGPTMessageReply shared] activateCapturedNativeReply];
    };
    if ([example isKindOfClass:UIAction.class]) {
        return [UIAction actionWithTitle:title image:image identifier:nil
                                handler:^(__unused UIAction *action) { callback(nil); }];
    }
    SEL action = analysis ? DGPTAnalysisActionSelector() : DGPTActionSelector();
    SEL selector;
    Method method;
    // Important: icon-bearing constructors MUST precede initWithTitle:action:
    // or UIKit will never be asked to render an image above the label.
    if (svgName.length) {
        selector = NSSelectorFromString(@"initWithTitle:svgName:action:");
        method = class_getInstanceMethod(cls, selector);
        if (DGPTSignature(method, '@', 5) && DGPTArgKind(method, 2) == '@' && DGPTArgKind(method, 3) == '@') {
            if (DGPTBlockArgument(method, 4))
                return ((id (*)(id, SEL, id, id, id))objc_msgSend)([cls alloc], selector, title, svgName, callback);
            if (DGPTArgKind(method, 4) == ':')
                return ((id (*)(id, SEL, id, id, SEL))objc_msgSend)([cls alloc], selector, title, svgName, action);
        }
        selector = NSSelectorFromString(@"initWithTitle:svgName:target:action:");
        method = class_getInstanceMethod(cls, selector);
        if (DGPTSignature(method, '@', 6) && DGPTArgKind(method, 2) == '@' &&
            DGPTArgKind(method, 3) == '@' && DGPTArgKind(method, 4) == '@' &&
            DGPTArgKind(method, 5) == ':') {
            return ((id (*)(id, SEL, id, id, id, SEL))objc_msgSend)(
                [cls alloc], selector, title, svgName, cell, action);
        }
    }
    // On builds whose native icon constructor explicitly expects a UIImage,
    // use SF Symbols rather than send a guessed string to an unknown API.
    selector = NSSelectorFromString(@"initWithTitle:icon:target:action:");
    method = class_getInstanceMethod(cls, selector);
    if (image && DGPTSignature(method, '@', 6) && DGPTArgKind(method, 2) == '@' &&
        DGPTArgIsUIImage(method, 3) && DGPTArgKind(method, 4) == '@' &&
        DGPTArgKind(method, 5) == ':') {
        return ((id (*)(id, SEL, id, id, id, SEL))objc_msgSend)(
            [cls alloc], selector, title, image, cell, action);
    }
    // Compatibility-only fallback. It is intentionally NOT presented as a
    // real native image: older text-only private menus have no icon API.
    NSString *fallbackTitle = analysis ? @"🔍\nAI分析" : @"💬\nAI回复";
    selector = NSSelectorFromString(@"initWithTitle:action:");
    method = class_getInstanceMethod(cls, selector);
    if (DGPTSignature(method, '@', 4) && DGPTArgKind(method, 2) == '@') {
        if (DGPTArgKind(method, 3) == ':')
            return ((id (*)(id, SEL, id, SEL))objc_msgSend)([cls alloc], selector, fallbackTitle, action);
        if (DGPTBlockArgument(method, 3))
            return ((id (*)(id, SEL, id, id))objc_msgSend)([cls alloc], selector, fallbackTitle, callback);
    }
    return nil;
}

// Returns a new array, not a mutated cached collection: the original menu
// builder will measure its rows after operationMenuItems returns.
static id DGPTAppendMenuItems(id original, id cell) {
    if (!DGPTMenuEnabledForCell(cell)) return original;
    if (![original isKindOfClass:NSArray.class]) {
        gModelFailures++;
        DGPTStatus([NSString stringWithFormat:@"operationMenuItems 不是数组：%@",
                    original ? NSStringFromClass([original class]) : @"nil"]);
        return original;
    }
    NSArray *items = (NSArray *)original;
    gLastCollection = NSStringFromClass([items class]);
    if (items.count == 0) { DGPTStatus(@"菜单项目数组为空"); return original; }

    // A nested menu array represents rows; native icon-bearing items preserve
    // the renderer's vertical icon + label alignment.
    BOOL nested = [items.firstObject isKindOfClass:NSArray.class];
    NSArray *leaf = nil;
    if (nested) {
        for (id row in items) {
            if (![row isKindOfClass:NSArray.class]) {
                DGPTStatus(@"菜单行不是数组"); return original;
            }
            for (id element in (NSArray *)row) if (DGPTIsOurItem(element)) return original;
            if (!leaf && [(NSArray *)row count] > 0) leaf = (NSArray *)row;
        }
        if (!leaf) { DGPTStatus(@"菜单各行均为空"); return original; }
    } else {
        leaf = items;
    }
    if (!leaf.count) { DGPTStatus(@"菜单行为空，已跳过"); return original; }
    for (id item in leaf) if (DGPTIsOurItem(item)) return original;
    id example = nil;
    for (id item in leaf) if (DGPTIsNativeMenuItem(item)) { example = item; break; }
    if (!example) {
        gModelFailures++;
        DGPTStatus([NSString stringWithFormat:@"菜单项类型不匹配：%@",
                    NSStringFromClass([leaf.firstObject class])]);
        return original;
    }
    NSString *replySVG = DGPTNativeIconForAction(items, NO);
    NSString *analysisSVG = DGPTNativeIconForAction(items, YES);
    DGPTStatus([NSString stringWithFormat:@"菜单图标资源：回复 %@ / 分析 %@",
                replySVG.length ? replySVG : @"未提供SVG",
                analysisSVG.length ? analysisSVG : @"未提供SVG"]);
    id created = nil, analysisItem = nil;
    @try {
        created = DGPTNewItemLike(example, cell, @"AI回复", NO, replySVG);
        analysisItem = DGPTNewItemLike(example, cell, @"AI分析", YES, analysisSVG);
    }
    @catch (NSException *exception) {
        DGPTStatus([NSString stringWithFormat:@"创建菜单项异常：%@", exception.name]);
        return original;
    }
    BOOL compatibleItem = created && analysisItem &&
        ([created isKindOfClass:[example class]] ||
         ([example isKindOfClass:UIAction.class] && [created isKindOfClass:UIAction.class])) &&
        ([analysisItem isKindOfClass:[example class]] ||
         ([example isKindOfClass:UIAction.class] && [analysisItem isKindOfClass:UIAction.class]));
    if (!compatibleItem) {
        gModelFailures++;
        DGPTStatus([NSString stringWithFormat:@"不支持的菜单项构造方法：%@",
                    NSStringFromClass([example class])]);
        return original;
    }
    NSMutableArray *result = [items mutableCopy];
    if (nested) {
        // Keep both actions in one row using their native menu item layout.
        [result addObject:@[created, analysisItem]];
    } else {
        // Flat menus do not expose row alignment; always place the item LAST.
        [result addObject:created];
        [result addObject:analysisItem];
    }
    gItemsInserted += 2;
    [[DGPTMessageReply shared] nativeMenuItemInserted];
    DGPTStatus([NSString stringWithFormat:@"已追加 AI 回复与 AI 分析：%@（%lu 项）",
                NSStringFromClass([created class]), (unsigned long)result.count]);
    return result;
}

static void DGPTInstallOperationHook(Class cls) {
    SEL selector = NSSelectorFromString(@"operationMenuItems");
    Method method = class_getInstanceMethod(cls, selector);
    if (!DGPTSignature(method, '@', 2)) return;
    NSString *key = DGPTMethodKey(cls, selector);
    if ([gInstalled containsObject:key]) return;
    IMP old = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^id(id cell) {
        if (!DGPTMenuEnabledForCell(cell) || gInsideOperation) {
            return ((id (*)(id, SEL))old)(cell, selector);
        }
        gInsideOperation++;
        gOperationCalls++;
        @try { [[DGPTMessageReply shared] captureNativeMenuCell:cell]; }
        @catch (__unused NSException *e) {}
        id result = ((id (*)(id, SEL))old)(cell, selector);
        @try { result = DGPTAppendMenuItems(result, cell); }
        @catch (NSException *e) { DGPTStatus([NSString stringWithFormat:@"追加时异常：%@", e.name]); }
        gInsideOperation--;
        return result;
    });
    // Hook ONLY the text cell. If its method is inherited, override it on
    // the text subclass instead of swizzling its CommonMessageCellView parent.
    if (DGPTOwnMethod(cls, selector)) method_setImplementation(method, replacement);
    else if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) return;
    [gInstalled addObject:key];
    DGPTStatus([NSString stringWithFormat:@"已接入 %@", key]);
}

static void DGPTInspectArrMenuItems(id cell) {
    // A diagnostic only: older WeChat versions store this array as an ivar.
    // Changing it after layout would corrupt caches or display nothing.
    @try {
        id value = [cell valueForKey:@"arrMenuItems"];
        if (value) {
            gLastCollection = NSStringFromClass([value class]);
            if ([value isKindOfClass:NSArray.class]) {
                DGPTStatus([NSString stringWithFormat:@"generateOperationMenu 已执行；arrMenuItems 有 %lu 项",
                            (unsigned long)[value count]]);
            }
        }
    } @catch (__unused NSException *e) {}
}

static void DGPTInstallGenerateHook(Class cls) {
    SEL selector = NSSelectorFromString(@"generateOperationMenu");
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 2) return;
    NSString *key = DGPTMethodKey(cls, selector);
    if ([gInstalled containsObject:key]) return;
    IMP old = method_getImplementation(method);
    if (DGPTSignature(method, 'v', 2)) {
        IMP replacement = imp_implementationWithBlock(^(id cell) {
            if (DGPTMenuEnabledForCell(cell)) {
                gGenerationCalls++;
                @try { [[DGPTMessageReply shared] captureNativeMenuCell:cell]; }
                @catch (__unused NSException *e) {}
            }
            ((void (*)(id, SEL))old)(cell, selector);
            if (DGPTMenuEnabledForCell(cell)) DGPTInspectArrMenuItems(cell);
        });
        if (DGPTOwnMethod(cls, selector)) method_setImplementation(method, replacement);
        else if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) return;
    } else if (DGPTSignature(method, '@', 2)) {
        IMP replacement = imp_implementationWithBlock(^id(id cell) {
            if (DGPTMenuEnabledForCell(cell)) {
                gGenerationCalls++;
                @try { [[DGPTMessageReply shared] captureNativeMenuCell:cell]; }
                @catch (__unused NSException *e) {}
            }
            id result = ((id (*)(id, SEL))old)(cell, selector);
            if (DGPTMenuEnabledForCell(cell)) {
                if ([result isKindOfClass:NSArray.class]) {
                    @try { result = DGPTAppendMenuItems(result, cell); }
                    @catch (__unused NSException *e) {}
                } else DGPTInspectArrMenuItems(cell);
            }
            return result;
        });
        if (DGPTOwnMethod(cls, selector)) method_setImplementation(method, replacement);
        else if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) return;
    } else return;
    [gInstalled addObject:key];
    DGPTStatus([NSString stringWithFormat:@"已接入 %@", key]);
}

@implementation DGPTNativeMenu
+ (void)installIfAvailable {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self installIfAvailable]; });
        return;
    }
    if (!objc_getClass("CMessageWrap")) return;
    if (!gInstalled) gInstalled = [NSMutableSet set];
    // Deliberately only install on the single text-bubble class. Never install
    // a hook on its ancestors or any group / common message-bubble class.
    Class textCell=objc_getClass("TextMessageCellView");
    if (textCell && [textCell isSubclassOfClass:UIView.class]) {
        DGPTAddActionToCell(textCell);
        DGPTInstallOperationHook(textCell);
        DGPTInstallGenerateHook(textCell);
    }
}

+ (NSString *)diagnosticSummary {
    return [NSString stringWithFormat:
       @"原生菜单 Hook：%lu 处\noperationMenuItems 调用：%lu 次\n"
        @"generateOperationMenu 调用：%lu 次\n追加成功：%lu 次\n"
        @"结构不兼容：%lu 次\n菜单数据类型：%@\n最后状态：%@",
        (unsigned long)gInstalled.count, (unsigned long)gOperationCalls,
        (unsigned long)gGenerationCalls, (unsigned long)gItemsInserted,
        (unsigned long)gModelFailures, gLastCollection ?: @"未观察到",
        gLastStatus ?: @"等待聊天气泡长按"];
}
@end
