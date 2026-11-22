#import <UIKit/UIKit.h>
#import "AxsWeChatGPTSettingItem.h"

NS_ASSUME_NONNULL_BEGIN

// Draws one rounded, blurred card that holds a titled list of rows.
@interface AxsWeChatGPTCardCell : NSObject

+ (UITableViewCell *)cellForTableView:(UITableView *)tableView
                                title:(nullable NSString *)title
                                items:(NSArray<AxsWeChatGPTSettingItem *> *)items
                            rightView:(nullable UIView *)rightView;

+ (CGFloat)heightForItemCount:(NSInteger)itemCount;

@end

NS_ASSUME_NONNULL_END
