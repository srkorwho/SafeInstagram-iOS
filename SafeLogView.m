#import "SafeLogView.h"

@interface SafeLogView ()
@property (nonatomic, strong) UITextView *textView;
@end

@implementation SafeLogView

+ (instancetype)sharedInstance {
    static SafeLogView *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        instance = [[self alloc] initWithFrame:CGRectMake(10, 50, screenBounds.size.width - 20, 200)];
        instance.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        instance.layer.cornerRadius = 12;
        instance.layer.masksToBounds = YES;
        instance.layer.borderColor = [UIColor whiteColor].CGColor;
        instance.layer.borderWidth = 1;

        UITextView *tv = [[UITextView alloc] initWithFrame:instance.bounds];
        tv.backgroundColor = [UIColor clearColor];
        tv.textColor = [UIColor greenColor];
        tv.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        tv.editable = NO;
        tv.selectable = NO;
        tv.userInteractionEnabled = NO;
        instance.textView = tv;
        [instance addSubview:tv];


        UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:instance action:@selector(toggleVisibility)];
        tripleTap.numberOfTapsRequired = 3;
        tripleTap.numberOfTouchesRequired = 3;
        [instance addGestureRecognizer:tripleTap];

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            UIWindow *keyWindow = nil;
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    keyWindow = scene.windows.firstObject;
                    if (keyWindow) break;
                }
            }
            if (keyWindow) {
                [keyWindow addSubview:instance];
                [keyWindow bringSubviewToFront:instance];
                NSLog(@"[SafeLogView] Log view added successfully.");
            } else {
                NSLog(@"[SafeLogView] No active window found.");
            }
        }];
    });
    return instance;
}

- (void)toggleVisibility {
    self.hidden = !self.hidden;
}

- (void)appendLog:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *old = self.textView.text ?: @"";
        NSString *newText = [old stringByAppendingFormat:@"\nSAisig %@", text];
        self.textView.text = newText;
        NSRange range = NSMakeRange(newText.length - 1, 1);
        [self.textView scrollRangeToVisible:range];
    });
}

@end

void SafeLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"SAisig %@", msg);
    [[SafeLogView sharedInstance] appendLog:msg];
}
