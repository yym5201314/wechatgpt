#import "AxsWeChatGPTCardCell.h"
#import "AxsWeChatGPTSettingCell.h"
#import <objc/runtime.h>

static const CGFloat AxsWeChatGPTCardItemHeight = 46.0f;
static const CGFloat AxsWeChatGPTCardHeaderHeight = 54.0f;
static const CGFloat AxsWeChatGPTCardPadding = 18.0f;
static const CGFloat AxsWeChatGPTCardInset = 20.0f;
static const CGFloat AxsWeChatGPTCardCornerRadius = 25.0f;
static NSInteger const AxsWeChatGPTCardContainerTag = 1001;
static char AxsWeChatGPTCardItemKey;

static UIColor *axs_wechatgpt_dynamicColor(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

@implementation AxsWeChatGPTCardCell

+ (CGFloat)heightForItemCount:(NSInteger)itemCount {
    return AxsWeChatGPTCardHeaderHeight + itemCount * AxsWeChatGPTCardItemHeight + AxsWeChatGPTCardPadding;
}

+ (UITableViewCell *)cellForTableView:(UITableView *)tableView
                                title:(NSString *)title
                                items:(NSArray<AxsWeChatGPTSettingItem *> *)items
                            rightView:(UIView *)rightView {
    static NSString *identifier = @"AxsWeChatGPTCardCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = [UIColor clearColor];
        cell.contentView.backgroundColor = [UIColor clearColor];
    }
    // Cards are rebuilt on every dequeue so row blocks always match the current data.
    for (UIView *subview in [cell.contentView.subviews copy]) {
        [subview removeFromSuperview];
    }

    // Auto Layout instead of frames: the first layout pass can happen before the
    // table has its final width, and frame+autoresizing then stretched the card
    // past the right screen edge until the page was rebuilt.
    UIView *card = [[UIView alloc] init];
    card.tag = AxsWeChatGPTCardContainerTag;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = AxsWeChatGPTCardCornerRadius;
    card.backgroundColor = axs_wechatgpt_dynamicColor([UIColor colorWithWhite:1.0 alpha:0.95],
                                                     [UIColor colorWithWhite:0.15 alpha:0.95]);
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOffset = CGSizeMake(0, 2);
    card.layer.shadowRadius = 8;
    card.layer.shadowOpacity = tableView.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.4 : 0.15;
    [cell.contentView addSubview:card];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = AxsWeChatGPTCardCornerRadius;
    blur.layer.masksToBounds = YES;
    blur.alpha = 0.6;
    [card addSubview:blur];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.backgroundColor = [UIColor clearColor];
    [card addSubview:content];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:16.0f weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];
    [content addSubview:titleLabel];

    NSLayoutConstraint *titleTrailing =
        [titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20.0f];

    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [card.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:AxsWeChatGPTCardInset],
        [card.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-AxsWeChatGPTCardInset],
        [card.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],

        [blur.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [blur.topAnchor constraintEqualToAnchor:card.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:card.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20.0f],
        [titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:18.0f],
        [titleLabel.heightAnchor constraintEqualToConstant:22.0f],
    ]];

    if (rightView) {
        rightView.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:rightView];
        CGSize size = rightView.bounds.size;
        [constraints addObjectsFromArray:@[
            [rightView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20.0f],
            [rightView.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
            [rightView.widthAnchor constraintEqualToConstant:MAX(size.width, 30.0f)],
            [rightView.heightAnchor constraintEqualToConstant:MAX(size.height, 24.0f)],
        ]];
        titleTrailing = [titleLabel.trailingAnchor constraintEqualToAnchor:rightView.leadingAnchor constant:-12.0f];
    }
    [constraints addObject:titleTrailing];

    NSLayoutYAxisAnchor *previousBottom = titleLabel.bottomAnchor;
    CGFloat gap = 14.0f;
    for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
        AxsWeChatGPTSettingItem *item = items[i];
        AxsWeChatGPTSettingCell *row = [[AxsWeChatGPTSettingCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                                   reuseIdentifier:nil];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [row configureWithItem:item];
        if (item.actionBlock) {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                  action:@selector(axs_wechatgpt_rowTapped:)];
            tap.cancelsTouchesInView = NO;
            objc_setAssociatedObject(tap, &AxsWeChatGPTCardItemKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [row addGestureRecognizer:tap];
        }
        [content addSubview:row];
        [constraints addObjectsFromArray:@[
            [row.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:previousBottom constant:gap],
            [row.heightAnchor constraintEqualToConstant:AxsWeChatGPTCardItemHeight],
        ]];
        previousBottom = row.bottomAnchor;
        gap = 0.0f;
    }

    [NSLayoutConstraint activateConstraints:constraints];
    return cell;
}

+ (void)axs_wechatgpt_rowTapped:(UITapGestureRecognizer *)gesture {
    AxsWeChatGPTSettingItem *item = objc_getAssociatedObject(gesture, &AxsWeChatGPTCardItemKey);
    if (item.actionBlock) {
        item.actionBlock();
    }
}

@end
