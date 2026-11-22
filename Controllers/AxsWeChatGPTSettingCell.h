#import <UIKit/UIKit.h>
#import "AxsWeChatGPTSettingItem.h"

NS_ASSUME_NONNULL_BEGIN

// A single row drawn inside a card: icon, title, detail, chevron or switch.
@interface AxsWeChatGPTSettingCell : UITableViewCell

@property (nonatomic, strong, readonly, nullable) AxsWeChatGPTSettingItem *item;
@property (nonatomic, strong, nullable) UIColor *detailTextColor;
// Replaces the detail text and chevron. Give the view an explicit frame size.
@property (nonatomic, strong, nullable) UIView *customTrailingView;

- (void)configureWithItem:(AxsWeChatGPTSettingItem *)item;

@end

NS_ASSUME_NONNULL_END
