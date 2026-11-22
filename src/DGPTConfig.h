#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const DGPTManualMenuEnabled;
FOUNDATION_EXPORT NSString * const DGPTReadChatHistoryEnabled;
FOUNDATION_EXPORT NSString * const DGPTChatHistoryCount;
FOUNDATION_EXPORT NSString * const DGPTPrefix;
FOUNDATION_EXPORT NSString * const DGPTPromptPresets;
FOUNDATION_EXPORT NSString * const DGPTActivePrompt;
@interface DGPTConfig : NSObject
+ (instancetype)shared;
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
