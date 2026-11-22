#import "AxsWeChatGPTSettingItem.h"

@interface AxsWeChatGPTSettingItem ()
@property (nonatomic, assign, readwrite) AxsWeChatGPTSettingItemType itemType;
@end

@implementation AxsWeChatGPTSettingItem

- (instancetype)initWithTitle:(NSString *)title
                     iconName:(NSString *)iconName
                    iconColor:(UIColor *)iconColor
                       detail:(NSString *)detail
                         type:(AxsWeChatGPTSettingItemType)type {
    self = [super init];
    if (self) {
        _title = [title copy] ?: @"";
        _iconName = [iconName copy];
        _iconColor = iconColor;
        _detail = [detail copy];
        _itemType = type;
    }
    return self;
}

+ (instancetype)itemWithTitle:(NSString *)title
                     iconName:(NSString *)iconName
                    iconColor:(UIColor *)iconColor
                       detail:(NSString *)detail {
    return [[self alloc] initWithTitle:title iconName:iconName iconColor:iconColor
                                detail:detail type:AxsWeChatGPTSettingItemTypeNormal];
}

+ (instancetype)actionItemWithTitle:(NSString *)title
                           iconName:(NSString *)iconName
                          iconColor:(UIColor *)iconColor {
    return [[self alloc] initWithTitle:title iconName:iconName iconColor:iconColor
                                detail:nil type:AxsWeChatGPTSettingItemTypeAction];
}

+ (instancetype)switchItemWithTitle:(NSString *)title
                           iconName:(NSString *)iconName
                          iconColor:(UIColor *)iconColor
                        switchValue:(BOOL)switchValue
                  valueChangedBlock:(void (^)(BOOL))valueChanged {
    AxsWeChatGPTSettingItem *item = [[self alloc] initWithTitle:title iconName:iconName iconColor:iconColor
                                                       detail:nil type:AxsWeChatGPTSettingItemTypeSwitch];
    item.switchValue = switchValue;
    item.switchValueChanged = valueChanged;
    return item;
}

@end

@implementation AxsWeChatGPTSettingSection

+ (instancetype)sectionWithHeader:(NSString *)header items:(NSArray<AxsWeChatGPTSettingItem *> *)items {
    AxsWeChatGPTSettingSection *section = [[self alloc] init];
    section.header = header;
    section.items = items ?: @[];
    return section;
}

@end
