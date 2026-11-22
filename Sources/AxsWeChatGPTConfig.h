#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posted on the main queue after the panel writes a value. Hooks read cached
// copies and refresh them when this arrives.
extern NSString * const AxsWeChatGPTConfigDidChangeNotification;

FOUNDATION_EXPORT NSString * const AxsWeChatGPTManualMenuEnabled;
FOUNDATION_EXPORT NSString * const AxsWeChatGPTChatHistoryCount;
FOUNDATION_EXPORT NSString * const AxsWeChatGPTPrefix;
FOUNDATION_EXPORT NSString * const AxsWeChatGPTPromptPresets;
FOUNDATION_EXPORT NSString * const AxsWeChatGPTActivePrompt;

// Settings live inside the WeChat sandbox (suite "com.axs.wechatgpt"). The tweak
// and its in-app panel share one process, so a single store serves both.
// Only the panel writes; hooks read.
@interface AxsWeChatGPTConfig : NSObject
+ (instancetype)shared;
- (BOOL)axs_wechatgpt_isEnabled;
- (void)axs_wechatgpt_setEnabled:(BOOL)enabled;
- (BOOL)boolForKey:(NSString *)key;
- (NSInteger)historyMessageCount;
- (void)setHistoryMessageCount:(NSInteger)count;
- (NSString *)stringForKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (void)setString:(nullable NSString *)value forKey:(NSString *)key;
- (NSArray *)arrayForKey:(NSString *)key;
- (void)setArray:(NSArray *)value forKey:(NSString *)key;
- (NSArray<NSDictionary *> *)providers;
- (nullable NSDictionary *)activeProvider;
- (NSString *)activeProviderID;
- (void)selectProviderWithID:(NSString *)providerID;
- (void)upsertProvider:(NSDictionary *)provider;
- (void)removeProviderWithID:(NSString *)providerID;
- (NSString *)apiKeyForProviderID:(NSString *)providerID;
- (BOOL)saveAPIKey:(NSString *)key forProviderID:(NSString *)providerID;
@end

NS_ASSUME_NONNULL_END
