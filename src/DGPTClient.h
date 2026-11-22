#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^DGPTCompletion)(NSString * _Nullable response, NSError * _Nullable error);
typedef void (^DGPTModelsCompletion)(NSArray<NSString *> * _Nullable models, NSError * _Nullable error);
@interface DGPTClient : NSObject
+ (instancetype)shared;
- (void)ask:(NSString *)question completion:(DGPTCompletion)completion;
- (void)askWithMessages:(NSArray<NSDictionary *> *)messages completion:(DGPTCompletion)completion;
// Analysis deliberately excludes the reply-only preset system prompt.
- (void)askForAnalysisWithMessages:(NSArray<NSDictionary *> *)messages completion:(DGPTCompletion)completion;
+ (nullable NSURL *)resolvedEndpointForBaseURL:(NSString *)baseURL error:(NSError * _Nullable __autoreleasing * _Nullable)error;
+ (nullable NSURL *)resolvedModelsEndpointForBaseURL:(NSString *)baseURL error:(NSError * _Nullable __autoreleasing * _Nullable)error;
- (void)fetchModelsForURL:(NSString *)baseURL apiKey:(NSString *)apiKey completion:(DGPTModelsCompletion)completion;
// Validate the fields currently entered in the provider editor, including unsaved changes.
- (void)testProviderURL:(NSString *)baseURL apiKey:(NSString *)apiKey
                   model:(NSString *)model completion:(DGPTCompletion)completion;
@end
NS_ASSUME_NONNULL_END
