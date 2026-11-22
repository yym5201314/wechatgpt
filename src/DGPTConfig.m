#import "DGPTConfig.h"
#import <Security/Security.h>

NSString * const DGPTManualMenuEnabled = @"manualMenuEnabled";
NSString * const DGPTReadChatHistoryEnabled = @"readChatHistoryEnabled.v075";
NSString * const DGPTChatHistoryCount = @"chatHistoryCount.v075";
NSString * const DGPTPrefix = @"prefix";
NSString * const DGPTPromptPresets = @"promptPresets";
NSString * const DGPTActivePrompt = @"activePrompt";
static NSString * const kSuite = @"com.standalone.wechatgpt.settings";
static NSString * const kProviders = @"providers.v050";
static NSString * const kActiveID = @"activeProviderID.v050";
static NSString * const kService = @"com.standalone.wechatgpt.provider-keys";

@implementation DGPTConfig {
    NSUserDefaults *_defaults;
}
+ (instancetype)shared {
    static DGPTConfig *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [DGPTConfig new]; });
    return shared;
}
- (instancetype)init {
    if ((self = [super init])) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
        [_defaults registerDefaults:@{
            DGPTManualMenuEnabled:@YES,
            DGPTReadChatHistoryEnabled:@NO, DGPTChatHistoryCount:@10,
            DGPTPrefix:@"",
            DGPTPromptPresets:@[], DGPTActivePrompt:@""
        }];
        // Import the existing single-provider settings once. Never persist API
        // keys in UserDefaults, only in the app-specific Keychain.
        if (![_defaults objectForKey:kProviders]) {
            NSString *url = [_defaults stringForKey:@"baseURL"] ?: @"https://api.openai.com/v1";
            NSString *model = [_defaults stringForKey:@"model"] ?: @"";
            NSString *pid = NSUUID.UUID.UUIDString;
            NSString *host = [NSURLComponents componentsWithString:url].host ?: @"";
            NSDictionary *provider = @{ @"id":pid, @"name": host.length ? host : @"默认服务商",
                                        @"url":url, @"model":model };
            [_defaults setObject:@[provider] forKey:kProviders];
            [_defaults setObject:pid forKey:kActiveID];
            NSString *oldKey = [self legacyAPIKey];
            if (oldKey.length) [self saveAPIKey:oldKey forProviderID:pid];
        }
    }
    return self;
}
- (BOOL)boolForKey:(NSString *)key { return [_defaults boolForKey:key]; }
- (NSInteger)historyMessageCount {
    // No arbitrary message-count ceiling. Still require a positive NSInteger.
    NSInteger n = [_defaults integerForKey:DGPTChatHistoryCount];
    return n > 0 ? n : 10;
}
- (void)setHistoryMessageCount:(NSInteger)count {
    if (count > 0) [_defaults setInteger:count forKey:DGPTChatHistoryCount];
}
- (NSString *)stringForKey:(NSString *)key { return [_defaults stringForKey:key] ?: @""; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { [_defaults setBool:value forKey:key]; }
- (void)setString:(NSString *)value forKey:(NSString *)key { [_defaults setObject:value ?: @"" forKey:key]; }
- (NSArray *)arrayForKey:(NSString *)key { return [_defaults arrayForKey:key] ?: @[]; }
- (void)setArray:(NSArray *)value forKey:(NSString *)key {
    [_defaults setObject:value ?: @[] forKey:key];
}
- (NSArray<NSDictionary *> *)providers {
    NSArray *stored = [_defaults arrayForKey:kProviders];
    NSMutableArray *result = [NSMutableArray array];
    for (id obj in stored) if ([obj isKindOfClass:NSDictionary.class] &&
        [obj[@"id"] isKindOfClass:NSString.class] &&
        [obj[@"url"] isKindOfClass:NSString.class]) [result addObject:obj];
    return result;
}
- (NSString *)activeProviderID { return [_defaults stringForKey:kActiveID] ?: @""; }
- (NSDictionary *)activeProvider {
    NSString *pid = [self activeProviderID];
    for (NSDictionary *p in [self providers]) if ([p[@"id"] isEqualToString:pid]) return p;
    return [self providers].firstObject;
}
- (void)selectProviderWithID:(NSString *)pid {
    for (NSDictionary *p in [self providers]) if ([p[@"id"] isEqualToString:pid]) {
        [_defaults setObject:pid forKey:kActiveID]; return;
    }
}
- (void)upsertProvider:(NSDictionary *)provider {
    NSString *pid = provider[@"id"];
    NSString *name = provider[@"name"];
    NSString *url = provider[@"url"];
    NSString *model = provider[@"model"];
    if (![pid isKindOfClass:NSString.class] || !pid.length ||
        ![name isKindOfClass:NSString.class] || !name.length ||
        ![url isKindOfClass:NSString.class] || !url.length ||
        ![model isKindOfClass:NSString.class]) return;
    NSDictionary *clean = @{@"id":pid, @"name":name, @"url":url, @"model":model};
    NSMutableArray *items = [[self providers] mutableCopy];
    BOOL replaced = NO;
    for (NSUInteger i = 0; i < items.count; i++) {
        if ([items[i][@"id"] isEqualToString:pid]) { items[i] = clean; replaced = YES; break; }
    }
    if (!replaced) [items addObject:clean];
    [_defaults setObject:items forKey:kProviders];
    if (![self activeProviderID].length) [_defaults setObject:pid forKey:kActiveID];
}
- (void)removeProviderWithID:(NSString *)pid {
    NSMutableArray *items = [[self providers] mutableCopy];
    NSIndexSet *indexes = [items indexesOfObjectsPassingTest:^BOOL(id object, NSUInteger idx, BOOL *stop) {
        (void)idx; (void)stop;
        NSDictionary *item = [object isKindOfClass:NSDictionary.class] ? object : nil;
        return [item[@"id"] isEqualToString:pid];
    }];
    if (!indexes.count) return;
    [items removeObjectsAtIndexes:indexes];
    [_defaults setObject:items forKey:kProviders];
    [self saveAPIKey:@"" forProviderID:pid];
    if ([[self activeProviderID] isEqualToString:pid])
        [_defaults setObject:(items.count ? items.firstObject[@"id"] : @"") forKey:kActiveID];
}
- (NSDictionary *)queryForAccount:(NSString *)account service:(NSString *)service {
    return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService:service, (__bridge id)kSecAttrAccount:account};
}
- (NSString *)readKeychainAccount:(NSString *)account service:(NSString *)service {
    NSMutableDictionary *query = [[self queryForAccount:account service:service] mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef raw = NULL;
    OSStatus result = SecItemCopyMatching((__bridge CFDictionaryRef)query, &raw);
    if (result != errSecSuccess || !raw) return @"";
    return [[NSString alloc] initWithData:CFBridgingRelease(raw) encoding:NSUTF8StringEncoding] ?: @"";
}
- (NSString *)legacyAPIKey {
    return [self readKeychainAccount:@"openai-api-key" service:@"com.standalone.wechatgpt"];
}
- (NSString *)apiKeyForProviderID:(NSString *)pid {
    if (!pid.length) return @"";
    return [self readKeychainAccount:pid service:kService];
}
- (BOOL)saveAPIKey:(NSString *)key forProviderID:(NSString *)pid {
    if (!pid.length) return NO;
    NSDictionary *query = [self queryForAccount:pid service:kService];
    if (!key.length) {
        OSStatus result = SecItemDelete((__bridge CFDictionaryRef)query);
        return result == errSecSuccess || result == errSecItemNotFound;
    }
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus updated = SecItemUpdate((__bridge CFDictionaryRef)query,
        (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    if (updated == errSecSuccess) return YES;
    if (updated != errSecItemNotFound) return NO;
    NSMutableDictionary *attributes = [query mutableCopy];
    attributes[(__bridge id)kSecValueData] = data;
    attributes[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)attributes, NULL) == errSecSuccess;
}
@end
