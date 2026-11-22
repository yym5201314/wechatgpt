#import <Foundation/Foundation.h>

// Adds a real item to the host app's existing bubble menu model. No
// single-finger gesture, second popup, or fixed bundle identifier is used.
@interface AxsWeChatGPTMenuInjector : NSObject
+ (void)installIfAvailable;
+ (NSString *)diagnosticSummary;
@end
