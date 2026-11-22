#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
// Native CMessageMgr GetLastMsgByCreateTime only. No UI scans or own database.
@interface DGPTWeChatBridge : NSObject
// Fail closed: hide all custom long-press actions for groups or unknown chats.
+ (BOOL)isSingleChatCell:(UIView *)cell;
+ (NSString *)messagePlaceholderForWrap:(nullable id)wrap;
+ (NSDictionary<NSString *,id> *)sessionContextForCell:(UIView *)cell selectedWrap:(nullable id)selectedWrap;
+ (NSDictionary<NSString *,id> *)historyPageForSession:(NSString *)session limit:(NSUInteger)limit fromID:(long long)fromID
                                            fromTime:(long long)fromTime;
+ (NSDictionary<NSString *,id> *)recentOpenChatHistoryForCell:(UIView *)cell
                                                selectedWrap:(nullable id)selectedWrap
                                                       limit:(NSUInteger)limit;
@end
NS_ASSUME_NONNULL_END
