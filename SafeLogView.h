#import <UIKit/UIKit.h>

@interface SafeLogView : UIView

+ (instancetype)sharedInstance;
- (void)appendLog:(NSString *)text;

@end

FOUNDATION_EXPORT void SafeLog(NSString *format, ...);
