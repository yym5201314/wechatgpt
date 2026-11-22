#import "AxsWeChatGPTWeChatBridge.h"
#import "AxsWeChatGPTConfig.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>
#include <limits.h>
#include <string.h>

// Read-only bridge to WeChat's native message manager. Only the known
// GetLastMsgByCreateTime selector is invoked; no UI scan, alternate query,
// database cache, send hooks or automatic reply.

static const char *axs_wechatgpt_unqualify(const char *t) {
    while (t && *t && strchr("rnNoORV", *t)) t++;
    return t;
}
static BOOL axs_wechatgpt_isInteger(const char *t) {
    t = axs_wechatgpt_unqualify(t);
    return t && t[0] && strchr("cCsSiIlLqQB", t[0]) != NULL;
}
static id axs_wechatgpt_slot(id obj, NSString *name) {
    if (!obj || !name.length) return nil;
    Ivar ivar = class_getInstanceVariable([obj class], name.UTF8String);
    if (!ivar) ivar = class_getInstanceVariable([obj class], [@"_" stringByAppendingString:name].UTF8String);
    if (ivar && ivar_getTypeEncoding(ivar)[0] == '@') {
        @try { return object_getIvar(obj, ivar); } @catch (__unused NSException *e) { return nil; }
    }
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([obj class], selector);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char *ret = method_copyReturnType(method);
    BOOL ok = ret && axs_wechatgpt_unqualify(ret)[0] == '@';
    if (ret) free(ret);
    if (!ok) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(obj, selector); }
    @catch (__unused NSException *e) { return nil; }
}
static NSString *axs_wechatgpt_string(id obj, NSString *name) {
    id v = axs_wechatgpt_slot(obj, name);
    return [v isKindOfClass:NSString.class] ? v : @"";
}
static long long axs_wechatgpt_int(id obj, NSString *name) {
    if (!obj || !name.length) return 0;
    Ivar ivar = class_getInstanceVariable([obj class], name.UTF8String);
    if (!ivar) ivar = class_getInstanceVariable([obj class], [@"_" stringByAppendingString:name].UTF8String);
    if (ivar && axs_wechatgpt_isInteger(ivar_getTypeEncoding(ivar))) {
        const char *type = axs_wechatgpt_unqualify(ivar_getTypeEncoding(ivar));
        size_t width = 0;
        switch (*type) {
            case 'c': case 'C': case 'B': width = 1; break;
            case 's': case 'S': width = 2; break;
            case 'i': case 'I': width = 4; break;
            case 'l': case 'L': width = sizeof(long); break;
            case 'q': case 'Q': width = 8; break;
        }
        unsigned long long n = 0;
        if (width) {
            memcpy(&n, ((const unsigned char *)(__bridge const void *)obj) + ivar_getOffset(ivar), width);
            return (long long)n;
        }
    }
    SEL sel = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([obj class], sel);
    if (!method || method_getNumberOfArguments(method) != 2) return 0;
    char *ret = method_copyReturnType(method);
    BOOL ok = axs_wechatgpt_isInteger(ret);
    if (ret) free(ret);
    if (!ok) return 0;
    @try { return ((long long (*)(id, SEL))objc_msgSend)(obj, sel); }
    @catch (__unused NSException *e) { return 0; }
}
static BOOL axs_wechatgpt_wrap(id obj) {
    Class cls = objc_getClass("CMessageWrap");
    return cls && obj && [obj isKindOfClass:cls];
}
static id axs_wechatgpt_wrapFrom(id obj) {
    if (axs_wechatgpt_wrap(obj)) return obj;
    if (!obj || [obj isKindOfClass:NSString.class] || [obj isKindOfClass:NSNumber.class]) return nil;
    for (NSString *key in @[@"m_msgWrap", @"msgWrap", @"messageWrap", @"m_messageWrap", @"message", @"m_msg", @"getMessageWrap", @"getMsgWrap"]) {
        id candidate = axs_wechatgpt_slot(obj, key);
        if (axs_wechatgpt_wrap(candidate)) return candidate;
    }
    for (NSString *key in @[@"viewModel", @"m_viewModel", @"messageModel", @"m_messageModel", @"m_msgViewModel"]) {
        id model = axs_wechatgpt_slot(obj, key);
        if (!model || model == obj) continue;
        for (NSString *inner in @[@"m_msgWrap", @"msgWrap", @"messageWrap", @"m_messageWrap", @"message", @"m_msg"]) {
            id candidate = axs_wechatgpt_slot(model, inner);
            if (axs_wechatgpt_wrap(candidate)) return candidate;
        }
    }
    return nil;
}
static id axs_wechatgpt_mmService(Class serviceClass) {
    Class contextClass = objc_getClass("MMContext");
    SEL active = NSSelectorFromString(@"activeUserContext");
    if (!contextClass || !serviceClass) return nil;
    Method cm = class_getClassMethod(contextClass, active);
    if (!cm || method_getNumberOfArguments(cm) != 2) return nil;
    char *rt = method_copyReturnType(cm);
    BOOL ok = rt && axs_wechatgpt_unqualify(rt)[0] == '@';
    if (rt) free(rt);
    if (!ok) return nil;
    @try {
        id ctx = ((id (*)(id, SEL))objc_msgSend)(contextClass, active);
        SEL get = NSSelectorFromString(@"getService:");
        Method m = ctx ? class_getInstanceMethod([ctx class], get) : NULL;
        if (!m || method_getNumberOfArguments(m) != 3) return nil;
        char *ret = method_copyReturnType(m);
        char *arg = method_copyArgumentType(m, 2);
        BOOL typesOK = ret && axs_wechatgpt_unqualify(ret)[0] == '@' && arg && strchr("@#", axs_wechatgpt_unqualify(arg)[0]) != NULL;
        if (ret) free(ret);
        if (arg) free(arg);
        if (!typesOK) return nil;
        return ((id (*)(id, SEL, id))objc_msgSend)(ctx, get, serviceClass);
    } @catch (__unused NSException *e) { return nil; }
}
static UIViewController *axs_wechatgpt_owner(UIView *cell) {
    UIResponder *cur = cell;
    for (NSUInteger i = 0; cur && i < 70; ++i, cur = cur.nextResponder)
        if ([cur isKindOfClass:UIViewController.class]) return (UIViewController *)cur;
    return nil;
}
static NSString *axs_wechatgpt_fromController(UIView *cell) {
    UIViewController *vc = axs_wechatgpt_owner(cell);
    for (NSUInteger depth = 0; vc && depth < 6; ++depth, vc = vc.parentViewController) {
        for (NSString *key in @[@"m_nsChatUsr", @"m_nsChatUserName", @"m_nsUsrName", @"m_chatUserName", @"m_nsTalker"]) {
            NSString *name = axs_wechatgpt_string(vc, key);
            if (name.length) return name;
        }
        for (NSString *key in @[@"m_contact", @"m_chatContact", @"m_oChatContact", @"m_currentContact", @"contact"]) {
            id c = axs_wechatgpt_slot(vc, key);
            NSString *name = axs_wechatgpt_string(c, @"m_nsUsrName");
            if (name.length) return name;
        }
        // These selectors may return a display label instead of a stable
        // conversation identifier; validate it against the selected message.
        for (NSString *key in @[@"getCurrentChatName", @"GetChatName"]) {
            NSString *name = axs_wechatgpt_string(vc, key);
            if (name.length) return name;
        }
    }
    return @"";
}
// Only stable contact/chat-ID fields are accepted as fallback when no wrap
// exists. Do not use getCurrentChatName/GetChatName here: those may be a group
// display title that is missing the @chatroom suffix.
static NSString *axs_wechatgpt_stableIDFromController(UIView *cell) {
    UIViewController *vc = axs_wechatgpt_owner(cell);
    for (NSUInteger depth = 0; vc && depth < 6; ++depth, vc = vc.parentViewController) {
        for (NSString *key in @[@"m_nsChatUsr", @"m_nsChatUserName", @"m_nsUsrName", @"m_chatUserName", @"m_nsTalker"]) {
            NSString *name = axs_wechatgpt_string(vc, key);
            if (name.length) return name;
        }
        for (NSString *key in @[@"m_contact", @"m_chatContact", @"m_oChatContact", @"m_currentContact", @"contact"]) {
            id contact = axs_wechatgpt_slot(vc, key);
            NSString *name = axs_wechatgpt_string(contact, @"m_nsUsrName");
            if (name.length) return name;
        }
    }
    return @"";
}
// The current chat controller is the primary source of the conversation ID.
// No local-account lookup or stored account identifier is used.
static NSString *axs_wechatgpt_session(id wrap, UIView *cell) {
    NSString *from = axs_wechatgpt_string(wrap, @"m_nsFromUsr");
    NSString *to = axs_wechatgpt_string(wrap, @"m_nsToUsr");
    if ([from hasSuffix:@"@chatroom"]) return from;
    if ([to hasSuffix:@"@chatroom"]) return to;
    NSString *onScreen = axs_wechatgpt_fromController(cell);
    if (onScreen.length && ((!from.length && !to.length) ||
        [onScreen isEqualToString:from] || [onScreen isEqualToString:to])) return onScreen;
    // A fallback for older WeChat builds without a readable chat controller.
    // These status values are version-specific, so prefer the controller ID.
    if (from.length && to.length) {
        long long status = axs_wechatgpt_int(wrap, @"m_uiStatus");
        if (status == 3) return from;
        if (status == 1 || status == 2 || status == 5) return to;
    }
    return @"";
}

// Only the verified native "last messages" selector is used. No screen
// scraping, no alternate time-query selector, no plugin history database.
static BOOL axs_wechatgpt_setInteger(NSInvocation *inv, NSUInteger index, const char *type, long long value) {
    type = axs_wechatgpt_unqualify(type);
    if (!axs_wechatgpt_isInteger(type)) return NO;
    switch (*type) {
        case 'c': { signed char v=(signed char)value; [inv setArgument:&v atIndex:index]; return YES; }
        case 'C': case 'B': { unsigned char v=(unsigned char)value; [inv setArgument:&v atIndex:index]; return YES; }
        case 's': { short v=(short)value; [inv setArgument:&v atIndex:index]; return YES; }
        case 'S': { unsigned short v=(unsigned short)value; [inv setArgument:&v atIndex:index]; return YES; }
        case 'i': { int v=(int)value; [inv setArgument:&v atIndex:index]; return YES; }
        case 'I': { unsigned int v=(unsigned int)value; [inv setArgument:&v atIndex:index]; return YES; }
        case 'l': { long v=(long)value; [inv setArgument:&v atIndex:index]; return YES; }
        case 'L': { unsigned long v=(unsigned long)value; [inv setArgument:&v atIndex:index]; return YES; }
        case 'q': { long long v=value; [inv setArgument:&v atIndex:index]; return YES; }
        case 'Q': { unsigned long long v=(unsigned long long)value; [inv setArgument:&v atIndex:index]; return YES; }
        default: return NO;
    }
}
static BOOL axs_wechatgpt_fitsUnsigned(NSUInteger number, const char *type) {
    type = axs_wechatgpt_unqualify(type);
    if (!type || !number || number > (NSUInteger)NSIntegerMax) return NO;
    switch (*type) {
        case 'c': return number <= SCHAR_MAX;
        case 'C': case 'B': return number <= UCHAR_MAX;
        case 's': return number <= SHRT_MAX;
        case 'S': return number <= USHRT_MAX;
        case 'i': return number <= INT_MAX;
        case 'I': return number <= UINT_MAX;
        case 'l': return number <= LONG_MAX;
        case 'L': return number <= ULONG_MAX;
        case 'q': return number <= LLONG_MAX;
        case 'Q': return YES;
        default: return NO;
    }
}
static BOOL axs_wechatgpt_fitsCursor(long long number, const char *type) {
    type = axs_wechatgpt_unqualify(type);
    if (!type || number < 0) return NO;
    switch (*type) {
        case 'c': return number <= SCHAR_MAX;
        case 'C': case 'B': return number <= UCHAR_MAX;
        case 's': return number <= SHRT_MAX;
        case 'S': return number <= USHRT_MAX;
        case 'i': return number <= INT_MAX;
        case 'I': return number <= UINT_MAX;
        case 'l': return number <= LONG_MAX;
        case 'L': return YES;
        case 'q': case 'Q': return YES;
        default: return NO;
    }
}
static NSArray *axs_wechatgpt_queryLast(NSString *session, NSUInteger limit, long long fromID,
                              long long fromTime, long long *left, NSString **failure) {
    if (failure) *failure = @"";
    if (left) *left = -1;
    id manager = axs_wechatgpt_mmService(objc_getClass("CMessageMgr"));
    if (!manager) { if (failure) *failure = @"无法获取 CMessageMgr"; return nil; }
    if (!session.length) { if (failure) *failure = @"当前会话 ID 为空"; return nil; }
    SEL sel = NSSelectorFromString(@"GetLastMsgByCreateTime:FromID:FromCreateTime:Limit:LeftCount:");
    NSMethodSignature *sig = [manager methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments != 7) {
        if (failure) *failure = @"当前微信版本不支持原生最近消息接口";
        return nil;
    }
    const char *ret = axs_wechatgpt_unqualify(sig.methodReturnType);
    const char *argSession = axs_wechatgpt_unqualify([sig getArgumentTypeAtIndex:2]);
    const char *output = axs_wechatgpt_unqualify([sig getArgumentTypeAtIndex:6]);
    if (!ret || *ret!='@' || !argSession || *argSession!='@' ||
        !axs_wechatgpt_isInteger([sig getArgumentTypeAtIndex:3]) ||
        !axs_wechatgpt_isInteger([sig getArgumentTypeAtIndex:4]) ||
        !axs_wechatgpt_isInteger([sig getArgumentTypeAtIndex:5]) ||
        !output || *output!='^' || !axs_wechatgpt_isInteger(output+1)) {
        if (failure) *failure = @"原生查询 ABI 参数签名不兼容";
        return nil;
    }
    if (!axs_wechatgpt_fitsUnsigned(limit, [sig getArgumentTypeAtIndex:5]) ||
        !axs_wechatgpt_fitsCursor(fromID, [sig getArgumentTypeAtIndex:3]) ||
        !axs_wechatgpt_fitsCursor(fromTime, [sig getArgumentTypeAtIndex:4])) {
        if (failure) *failure = @"数量或分页游标超过接口整数范围";
        return nil;
    }
    @try {
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:manager]; [inv setSelector:sel];
        id stringArg = session;
        [inv setArgument:&stringArg atIndex:2];
        if (!axs_wechatgpt_setInteger(inv, 3, [sig getArgumentTypeAtIndex:3], fromID) ||
            !axs_wechatgpt_setInteger(inv, 4, [sig getArgumentTypeAtIndex:4], fromTime) ||
            !axs_wechatgpt_setInteger(inv, 5, [sig getArgumentTypeAtIndex:5], (long long)limit)) {
            if (failure) *failure = @"无法设置原生查询参数";
            return nil;
        }
        long long remaining = -1;
        void *ptr = &remaining;
        [inv setArgument:&ptr atIndex:6];
        [inv invoke];
        __unsafe_unretained id result = nil;
        [inv getReturnValue:&result];
        if (![result isKindOfClass:NSArray.class]) {
            if (failure) *failure = @"接口没有返回 NSArray";
            return nil;
        }
        // Keep the native output-pointer width: an int32 write into our
        // 8-byte buffer must not leave stale upper bytes from -1.
        const char *pointee = axs_wechatgpt_unqualify(output+1);
        long long decoded = remaining;
        if (*pointee == 'i') decoded = (int)(uint32_t)remaining;
        else if (*pointee == 'I') decoded = (unsigned int)(uint32_t)remaining;
        else if (*pointee == 's') decoded = (short)(uint16_t)remaining;
        else if (*pointee == 'S') decoded = (unsigned short)(uint16_t)remaining;
        else if (*pointee == 'c') decoded = (signed char)(uint8_t)remaining;
        else if (*pointee == 'C' || *pointee == 'B') decoded = (unsigned char)(uint8_t)remaining;
        if (left) *left = decoded;
        return [result copy];
    } @catch (NSException *exception) {
        if (failure) *failure = [NSString stringWithFormat:@"原生读取异常：%@", exception.name ?: @"未知"];
        return nil;
    }
}

static NSString *axs_wechatgpt_normalizedText(id wrap, BOOL *truncated) {
    if (truncated) *truncated = NO;
    if (axs_wechatgpt_int(wrap, @"m_uiMessageType") != 1) return @"";
    NSString *content = axs_wechatgpt_string(wrap, @"m_nsContent");
    NSString *from = axs_wechatgpt_string(wrap, @"m_nsFromUsr");
    NSString *to = axs_wechatgpt_string(wrap, @"m_nsToUsr");
    if ([from hasSuffix:@"@chatroom"] || [to hasSuffix:@"@chatroom"]) {
        NSRange range = [content rangeOfString:@":\n"];
        if (range.location != NSNotFound && range.location < 160)
            content = [content substringFromIndex:NSMaxRange(range)];
    }
    if (content.length > 16000) {
        content = [content substringToIndex:16000];
        if (truncated) *truncated = YES;
    }
    return [content stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
// WeChat stores several rich cards as message type 49. Classify the appmsg
// subtype from the already-retrieved CMessageWrap content; do not download
// media, consult the local database, or claim to recognize image pixels.
static NSString *axs_wechatgpt_appXMLValue(NSString *xml, NSString *tag) {
    if (![xml isKindOfClass:NSString.class] || !xml.length || xml.length > 400000) return @"";
    NSRange app = [xml rangeOfString:@"<appmsg" options:NSCaseInsensitiveSearch];
    if (app.location == NSNotFound) return @"";
    NSRange end = [xml rangeOfString:@"</appmsg>" options:NSCaseInsensitiveSearch
        range:NSMakeRange(app.location, xml.length - app.location)];
    NSUInteger boundary = end.location == NSNotFound ? xml.length : end.location;
    NSString *open = [NSString stringWithFormat:@"<%@>",tag];
    NSString *close = [NSString stringWithFormat:@"</%@>",tag];
    NSRange opening = [xml rangeOfString:open options:NSCaseInsensitiveSearch
        range:NSMakeRange(app.location, boundary-app.location)];
    if (opening.location == NSNotFound) return @"";
    NSUInteger start = NSMaxRange(opening);
    NSRange ending = [xml rangeOfString:close options:NSCaseInsensitiveSearch
        range:NSMakeRange(start,boundary-start)];
    if (ending.location == NSNotFound || ending.location < start) return @"";
    NSString *value = [[xml substringWithRange:NSMakeRange(start,ending.location-start)]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value hasPrefix:@"<![CDATA["] && [value hasSuffix:@"]]>"] && value.length>=12)
        value = [value substringWithRange:NSMakeRange(9,value.length-12)];
    return value.length <= 180 ? value : [value substringToIndex:180];
}
static NSString *axs_wechatgpt_messageCategory(NSInteger type, NSString *xml, NSInteger *subtype) {
    NSInteger appType=0;
    if (type == 49) {
        NSString *number = axs_wechatgpt_appXMLValue(xml,@"type");
        if (number.length && number.length < 12) {
            NSScanner *scanner = [NSScanner scannerWithString:number];
            NSInteger candidate=0;
            if ([scanner scanInteger:&candidate] && scanner.isAtEnd && candidate>=0)
                appType=candidate;
        }
    }
    if (subtype) *subtype=appType;
    switch (type) {
        case 1: return @"text";
        case 3: return @"image";
        case 34: return @"voice";
        case 43: case 62: return @"video";
        case 47: return @"sticker";
        case 48: return @"location";
        case 49: {
            switch (appType) {
                case 2000: return @"transfer";
                case 2001: return @"redPacket";
                case 33: case 36: return @"miniProgram";
                case 5: return @"link";
                case 6: return @"file";
                case 19: return @"forwardedChat";
                case 57: return @"quote";
                default: {
                    // Fallback clues are used only when the subtype is missing.
                    NSString *lower = xml.lowercaseString ?: @"";
                    if ([lower containsString:@"redenvelope"] || [lower containsString:@"redpacket"])
                        return @"redPacket";
                    if ([lower containsString:@"transferid"] || [lower containsString:@"pay_memo"])
                        return @"transfer";
                    if ([lower containsString:@"weappinfo"] || [lower containsString:@"miniprogram"])
                        return @"miniProgram";
                    return @"appOther";
                }
            }
        }
        default: return @"other";
    }
}
static NSString *axs_wechatgpt_categoryLabel(NSString *category) {
    static NSDictionary<NSString *,NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{ @"text":@"文字", @"image":@"图片", @"video":@"视频",
          @"voice":@"语音", @"sticker":@"表情", @"location":@"位置",
          @"transfer":@"转账", @"redPacket":@"红包", @"miniProgram":@"小程序链接",
          @"link":@"网页链接", @"file":@"文件", @"forwardedChat":@"聊天记录转发",
          @"quote":@"引用消息", @"appOther":@"其他分享卡片", @"other":@"其他消息" };
    });
    return names[category] ?: @"其他消息";
}
static NSDictionary *axs_wechatgpt_normalizeMessage(id row, NSString *session) {
    id wrap = axs_wechatgpt_wrapFrom(row);
    if (!wrap || !session.length) return nil;
    NSString *from = axs_wechatgpt_string(wrap, @"m_nsFromUsr");
    NSString *to = axs_wechatgpt_string(wrap, @"m_nsToUsr");
    if (![from isEqualToString:session] && ![to isEqualToString:session]) return nil;
    BOOL group = [session hasSuffix:@"@chatroom"];
    NSString *real = axs_wechatgpt_string(wrap, @"m_nsRealChatUsr");
    // Sender/recipient are relative to the current conversation, not any
    // account identifier. Ambiguous messages are never assigned a direction.
    NSString *direction = @"unknown";
    if ([from isEqualToString:session] && ![to isEqualToString:session])
        direction = @"other";
    else if ([to isEqualToString:session] && ![from isEqualToString:session])
        direction = @"mine";
    // In group messages the real sender is retained for descriptive labels;
    // do not classify a group member as the account owner using that field.
    long long time = axs_wechatgpt_int(wrap, @"m_uiCreateTime");
    if (time > 100000000000LL) time /= 1000;
    long long local = axs_wechatgpt_int(wrap, @"m_uiMesLocalID");
    long long server = axs_wechatgpt_int(wrap, @"m_n64MesSvrID");
    NSInteger type = (NSInteger)axs_wechatgpt_int(wrap, @"m_uiMessageType");
    BOOL cut = NO;
    NSString *text = axs_wechatgpt_normalizedText(wrap, &cut);
    NSString *raw = type == 49 ? axs_wechatgpt_string(wrap, @"m_nsContent") : @"";
    if (raw.length > 400000) raw = [raw substringToIndex:400000];
    NSInteger subtype=0;
    NSString *category = axs_wechatgpt_messageCategory(type, raw, &subtype);
    NSString *description = @"";
    if ([category isEqualToString:@"text"]) {
        description = text;
    } else {
        NSString *title = (type == 49 && ([category isEqualToString:@"miniProgram"] ||
            [category isEqualToString:@"link"] || [category isEqualToString:@"file"])) ?
            axs_wechatgpt_appXMLValue(raw, @"title") : @"";
        description = title.length ? [NSString stringWithFormat:@"[%@：%@]",
            axs_wechatgpt_categoryLabel(category), title] :
            [NSString stringWithFormat:@"[%@，仅识别消息类型，未读取媒体内容]",axs_wechatgpt_categoryLabel(category)];
    }
    NSString *key = server > 0 ? [NSString stringWithFormat:@"s%lld",server] :
        (local > 0 ? [NSString stringWithFormat:@"l%lld",local] :
        [NSString stringWithFormat:@"%@/%@/%lld/%ld/%@",from,to,time,(long)type,text]);
    return @{ @"key":key, @"content":text ?: @"",
              @"direction":direction, @"sender":(group ? (real.length ? real : from) : from),
              @"timestamp":@(time), @"localID":@(local), @"serverID":@(server),
              @"messageType":@(type), @"appMessageType":@(subtype),
              @"category":category, @"categoryLabel":axs_wechatgpt_categoryLabel(category),
              @"analysisText":description ?: @"", @"truncated":@(cut) };
}
static NSArray<NSDictionary *> *axs_wechatgpt_chronological(NSArray<NSDictionary *> *rows) {
    return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        long long x=[a[@"timestamp"] longLongValue], y=[b[@"timestamp"] longLongValue];
        if (x != y) return x<y ? NSOrderedAscending:NSOrderedDescending;
        long long l=[a[@"localID"] longLongValue], r=[b[@"localID"] longLongValue];
        if (l != r) return l<r ? NSOrderedAscending:NSOrderedDescending;
        return [a[@"key"] compare:b[@"key"]];
    }];
}

@implementation AxsWeChatGPTWeChatBridge
+ (BOOL)isSingleChatCell:(UIView *)cell {
    if (![cell isKindOfClass:UIView.class] || !NSThread.isMainThread) return NO;
    // Use the same private message and chat-controller fields already read
    // by the existing native-history bridge. No group-specific hooks, no wxid.
    id wrap = axs_wechatgpt_wrapFrom(cell);
    NSString *from = axs_wechatgpt_string(wrap, @"m_nsFromUsr");
    NSString *to = axs_wechatgpt_string(wrap, @"m_nsToUsr");
    if ([from hasSuffix:@"@chatroom"] || [to hasSuffix:@"@chatroom"]) return NO;
    NSString *stableID = axs_wechatgpt_stableIDFromController(cell);
    if ([stableID hasSuffix:@"@chatroom"]) return NO;
    if (wrap) {
        NSString *session = axs_wechatgpt_session(wrap, cell);
        return session.length > 0 && ![session hasSuffix:@"@chatroom"];
    }
    // With no message wrap, only a stable user/contact ID qualifies.
    // A display name alone must not enable custom actions in a group chat.
    return stableID.length > 0;
}
+ (NSString *)messagePlaceholderForWrap:(id)wrap {
    if (!axs_wechatgpt_wrap(wrap)) return @"";
    NSInteger type=(NSInteger)axs_wechatgpt_int(wrap,@"m_uiMessageType");
    if (type==1) return axs_wechatgpt_normalizedText(wrap,NULL);
    NSString *raw=axs_wechatgpt_string(wrap,@"m_nsContent");
    NSInteger appType=0;
    NSString *category=axs_wechatgpt_messageCategory(type,raw,&appType);
    (void)appType;
    return [NSString stringWithFormat:@"[%@消息，未读取媒体内容]",axs_wechatgpt_categoryLabel(category)];
}

+ (NSDictionary<NSString *,id> *)sessionContextForCell:(UIView *)cell selectedWrap:(id)selectedWrap {
    if (!NSThread.isMainThread || ![cell isKindOfClass:UIView.class])
        return @{ @"error":@"请从微信聊天文字气泡打开" };
    id anchor = axs_wechatgpt_wrapFrom(selectedWrap) ?: axs_wechatgpt_wrapFrom(cell);
    NSString *session = axs_wechatgpt_session(anchor, cell);
    if (!session.length) {
        NSString *controllerGroup = axs_wechatgpt_fromController(cell);
        if ([controllerGroup hasSuffix:@"@chatroom"]) session = controllerGroup;
    }
    if (!session.length) return @{ @"error":@"未能识别当前会话 ID，请从聊天文字气泡打开" };
    return @{ @"session":session, @"isGroup":@([session hasSuffix:@"@chatroom"]) };
}
+ (NSDictionary<NSString *,id> *)historyPageForSession:(NSString *)session
                                             limit:(NSUInteger)limit
                                              fromID:(long long)fromID
                                            fromTime:(long long)fromTime {
    if (!NSThread.isMainThread) return @{ @"error":@"历史查询必须在微信主线程调度", @"messages":@[] };
    CFTimeInterval start = CACurrentMediaTime();
    NSString *failure = @"";
    long long left = -1;
    NSArray *raw = axs_wechatgpt_queryLast(session, limit, fromID, fromTime, &left, &failure);
    NSTimeInterval seconds = CACurrentMediaTime()-start;
    if (!raw) return @{ @"messages":@[], @"error":failure.length ? failure : @"查询失败", @"seconds":@(seconds) };
    NSMutableDictionary<NSString *,NSDictionary *> *unique = [NSMutableDictionary dictionary];
    long long earliestTime = LLONG_MAX, earliestID = 0;
    for (id row in raw) {
        NSDictionary *record = axs_wechatgpt_normalizeMessage(row, session);
        if (!record) continue;
        NSString *key = record[@"key"];
        if (key.length && !unique[key]) unique[key] = record;
        long long timestamp = [record[@"timestamp"] longLongValue];
        if (timestamp > 0 && timestamp <= earliestTime) {
            if (timestamp < earliestTime || [record[@"localID"] longLongValue] < earliestID || !earliestID) {
                earliestTime = timestamp; earliestID = [record[@"localID"] longLongValue];
            }
        }
    }
    return @{ @"messages":axs_wechatgpt_chronological(unique.allValues), @"rawCount":@(raw.count),
              @"leftCount":@(left), @"fromID":@(earliestID),
              @"fromTime":@(earliestTime == LLONG_MAX ? 0 : earliestTime),
              @"seconds":@(seconds), @"error":@"" };
}
+ (NSDictionary<NSString *,id> *)recentOpenChatHistoryForCell:(UIView *)cell
                                                selectedWrap:(id)selectedWrap limit:(NSUInteger)limit {
    if (!limit || limit > (NSUInteger)NSIntegerMax)
        return @{ @"messages":@[], @"error":@"读取条数无效" };
    CFTimeInterval started = CACurrentMediaTime();
    NSDictionary *context = [self sessionContextForCell:cell selectedWrap:selectedWrap];
    NSString *session = context[@"session"];
    if (!session.length)
        return @{ @"messages":@[], @"error":context[@"error"] ?: @"会话识别失败", @"details":@"原生① 未执行" };
    NSTimeInterval identify = CACurrentMediaTime()-started;
    NSDictionary *page = [self historyPageForSession:session limit:limit fromID:0 fromTime:0];
    NSMutableArray<NSDictionary *> *textMessages = [NSMutableArray array];
    NSUInteger mine=0, others=0, unknown=0;
    for (NSDictionary *entry in page[@"messages"] ?: @[]) {
        NSString *content = entry[@"content"];
        if (!content.length) continue;
        NSString *who = entry[@"direction"];
        if ([who isEqualToString:@"mine"]) ++mine;
        else if ([who isEqualToString:@"other"]) ++others;
        else ++unknown;
        [textMessages addObject:entry];
    }
    if (textMessages.count > limit)
        [textMessages removeObjectsInRange:NSMakeRange(0, textMessages.count-limit)];
    NSString *failure = page[@"error"] ?: @"";
    NSString *details = [NSString stringWithFormat:
        @"原生① CMessageMgr 最近消息：请求%lu / 返回%@ / 可用文字%lu，%.3f秒\n"
         @"方向：我%lu条 / 对方%lu条 / 未识别%lu条\n会话定位 %.3f秒（无其他读取方式）",
        (unsigned long)limit, page[@"rawCount"] ?: @0, (unsigned long)textMessages.count,
        [page[@"seconds"] doubleValue], (unsigned long)mine, (unsigned long)others,
        (unsigned long)unknown, identify];
    if (failure.length) details = [details stringByAppendingFormat:@"\n错误：%@",failure];
    return @{ @"messages":textMessages, @"isGroup":context[@"isGroup"],
              @"source":@"微信 CMessageMgr 原生①", @"details":details,
              @"error":textMessages.count ? @"" : (failure.length ? failure : @"原生查询没有返回文字消息"),
              @"timing":@{ @"identity":@(identify), @"nativeLast":page[@"seconds"] ?: @0,
                            @"filter":@0 } };
}
@end
