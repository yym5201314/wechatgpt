#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Form for one OpenAI-compatible provider: name, base URL, key and model.
// The model is fetched from the provider so it never has to be typed by hand.
@interface AxsWeChatGPTProviderEditorViewController : UITableViewController
- (instancetype)initWithProvider:(nullable NSDictionary *)provider;
@end

NS_ASSUME_NONNULL_END
