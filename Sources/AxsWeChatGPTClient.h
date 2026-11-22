#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^AxsWeChatGPTCompletion)(NSString * _Nullable response, NSError * _Nullable error);
typedef void (^AxsWeChatGPTModelsCompletion)(NSArray<NSString *> * _Nullable models, NSError * _Nullable error);
@interface AxsWeChatGPTClient : NSObject
+ (instancetype)shared;
- (void)ask:(NSString *)question completion:(AxsWeChatGPTCompletion)completion;
- (void)askWithMessages:(NSArray<NSDictionary *> *)messages completion:(AxsWeChatGPTCompletion)completion;
// Analysis deliberately excludes the reply-only preset system prompt.
- (void)askForAnalysisWithMessages:(NSArray<NSDictionary *> *)messages completion:(AxsWeChatGPTCompletion)completion;
+ (nullable NSURL *)resolvedEndpointForBaseURL:(NSString *)baseURL error:(NSError * _Nullable __autoreleasing * _Nullable)error;
+ (nullable NSURL *)resolvedModelsEndpointForBaseURL:(NSString *)baseURL error:(NSError * _Nullable __autoreleasing * _Nullable)error;
- (void)fetchModelsForURL:(NSString *)baseURL apiKey:(NSString *)apiKey completion:(AxsWeChatGPTModelsCompletion)completion;
// Validate the fields currently entered in the provider editor, including unsaved changes.
- (void)testProviderURL:(NSString *)baseURL apiKey:(NSString *)apiKey
                   model:(NSString *)model completion:(AxsWeChatGPTCompletion)completion;
@end
NS_ASSUME_NONNULL_END
