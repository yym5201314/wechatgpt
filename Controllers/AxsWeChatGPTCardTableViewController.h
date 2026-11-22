#import <UIKit/UIKit.h>
#import "AxsWeChatGPTSettingItem.h"

NS_ASSUME_NONNULL_BEGIN

// Base controller for card-style settings pages: one card per section.
@interface AxsWeChatGPTCardTableViewController : UITableViewController

@property (nonatomic, copy) NSArray<AxsWeChatGPTSettingSection *> *sections;

- (void)configureAppearanceWithTitle:(NSString *)title;

// Subclasses may put a view (button, status label) at the right of a card title.
- (nullable UIView *)rightViewForSection:(NSInteger)section;

@end

NS_ASSUME_NONNULL_END
