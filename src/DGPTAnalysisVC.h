#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface DGPTAnalysisVC : UIViewController
+ (void)presentWithSessionContext:(NSDictionary<NSString *,id> *)context
                           window:(nullable UIWindow *)window;
@end
NS_ASSUME_NONNULL_END
