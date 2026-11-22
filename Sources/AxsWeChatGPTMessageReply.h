#import <UIKit/UIKit.h>
// Called only by version-checked native WeChat menu integration.
@interface DGPTMessageReply : NSObject
+ (instancetype)shared;
- (void)captureNativeMenuCell:(id)cell;
- (BOOL)hasFreshNativeMenuMessage;
- (void)nativeMenuItemInserted;
- (void)activateCapturedNativeReply;
- (void)activateCapturedNativeAnalysis;
- (NSString *)menuDiagnosticSummary;
@end
