#import <UIKit/UIKit.h>
// Called only by version-checked native WeChat menu integration.
@interface AxsWeChatGPTMessageReply : NSObject
+ (instancetype)shared;
- (void)captureNativeMenuCell:(id)cell;
- (BOOL)hasFreshNativeMenuMessage;
- (void)nativeMenuItemInserted;
- (void)activateCapturedNativeReply;
- (void)activateCapturedNativeAnalysis;
- (NSString *)menuDiagnosticSummary;
@end
