#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Searchable model list returned by the provider's /models endpoint.
@interface AxsWeChatGPTModelPickerViewController : UITableViewController <UISearchResultsUpdating>
- (instancetype)initWithModels:(NSArray<NSString *> *)models
                      selected:(NSString *)selected
                     selection:(void (^)(NSString *model))selection;
@end

NS_ASSUME_NONNULL_END
