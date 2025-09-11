#import <UIKit/UIKit.h>
#import <CoreML/CoreML.h>
#import <objc/runtime.h>
#import "SafeLogView.h"

static NSMapTable<id, NSNumber *> *checkedImages;

@implementation UIImageView (SafeView)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        checkedImages = [NSMapTable weakToStrongObjectsMapTable];

        Class targetClass = [UIImageView class];
        SEL originalSelector = @selector(setImage:);
        SEL swizzledSelector = @selector(swizzled_setImage:);
        Method originalMethod = class_getInstanceMethod(targetClass, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(targetClass, swizzledSelector);

        BOOL didAddMethod = class_addMethod(targetClass,
                                            originalSelector,
                                            method_getImplementation(swizzledMethod),
                                            method_getTypeEncoding(swizzledMethod));
        if (didAddMethod) {
            class_replaceMethod(targetClass,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
            SafeLog(@"Swizzled using class_addMethod");
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
            SafeLog(@"Swizzled using method_exchangeImplementations");
        }
    });
}

- (void)swizzled_setImage:(UIImage *)image {
    if (!image) {
        [self swizzled_setImage:image];
        return;
    }

    __weak typeof(self) wself = self;

    NSNumber *cachedResult = [checkedImages objectForKey:image];
    if (cachedResult != nil) {
        BOOL unsafe = [cachedResult boolValue];
        if (unsafe) {
            UIImage *blackImg = [wself blackImageWithSize:image.size];
            SafeLog(@"Cached unsafe image, replacing with black image.");
            [wself swizzled_setImage:blackImg];
        } else {
            SafeLog(@"Cached safe image, setting directly.");
            [wself swizzled_setImage:image];
        }
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL unsafe = [wself isInappropriateSync:image];
        [checkedImages setObject:@(unsafe) forKey:image];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (unsafe) {
                UIImage *blackImg = [wself blackImageWithSize:image.size];
                SafeLog(@"Unsafe image detected, replacing with black image.");
                [wself swizzled_setImage:blackImg];
            } else {
                SafeLog(@"Safe image detected, setting image.");
                [wself swizzled_setImage:image];
            }
        });
    });
}

- (BOOL)isInappropriateSync:(UIImage *)image {
    static MLModel *model = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *modelPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/SafeModel.mlmodelc"];
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:modelPath];
        BOOL isDir = NO;
        BOOL pathExists = [[NSFileManager defaultManager] fileExistsAtPath:modelPath isDirectory:&isDir];

        SafeLog(@"Model path: %@", modelPath);
        SafeLog(@"Does model file exist? %d", exists);
        SafeLog(@"Does path exist? %d, is directory? %d", pathExists, isDir);

        NSError *dirErr = nil;
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:modelPath error:&dirErr];
        if (dirErr) {
            SafeLog(@"Directory could not be read: %@", dirErr);
        } else {
            SafeLog(@"Directory contents: %@", contents);
        }

        NSURL *modelURL = [NSURL fileURLWithPath:modelPath isDirectory:YES];
        NSError *err = nil;
        model = [MLModel modelWithContentsOfURL:modelURL error:&err];
        if (!model) {
            SafeLog(@"Model could not be loaded: %@", err);
        } else {
            SafeLog(@"Model loaded successfully.");
        }
    });

    if (!model) return NO;

    NSString *inputName = @"input";
    NSString *outputName = @"classLabel";

    CGSize size = CGSizeMake(224,224);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    [image drawInRect:CGRectMake(0,0,size.width,size.height)];
    UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!resized.CGImage) return NO;

    CVPixelBufferRef buffer = [self pixelBufferFromCGImage:resized.CGImage width:224 height:224];
    if (!buffer) return NO;

    MLMultiArray *array = [self multiArrayFromPixelBuffer:buffer];
    CFRelease(buffer);
    if (!array) return NO;

    NSError *error = nil;
    NSDictionary *inputDict = @{ inputName: [MLFeatureValue featureValueWithMultiArray:array] };
    MLDictionaryFeatureProvider *input = [[MLDictionaryFeatureProvider alloc] initWithDictionary:inputDict error:&error];
    if (error) {
        SafeLog(@"Error preparing input: %@", error);
        return NO;
    }

    id<MLFeatureProvider> result = [model predictionFromFeatures:input error:&error];
    if (error || !result) {
        SafeLog(@"Prediction error: %@", error);
        return NO;
    }

    MLFeatureValue *outVal = [result featureValueForName:outputName];
    if (!outVal) return NO;

    NSString *predictedClass = [outVal stringValue];
    SafeLog(@"Model prediction: %@", predictedClass);

    if ([predictedClass isEqualToString:@"hentai"] ||
        [predictedClass isEqualToString:@"porn"] ||
        [predictedClass isEqualToString:@"drawing"] ||
        [predictedClass isEqualToString:@"sexy"]) {
        return YES;
    }
    return NO;
}

- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)cgImage width:(size_t)width height:(size_t)height {
    NSDictionary *attrs = @{(NSString*)kCVPixelBufferCGImageCompatibilityKey:@YES,
                            (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES};
    CVPixelBufferRef pxbuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                          kCVPixelFormatType_32BGRA,
                                          (__bridge CFDictionaryRef)attrs,
                                          &pxbuffer);
    if (status != kCVReturnSuccess || !pxbuffer) {
        SafeLog(@"CVPixelBufferCreate failed: %d", status);
        return NULL;
    }
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pxbuffer);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, width, height, 8, bytesPerRow, rgb,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    if (!context) {
        SafeLog(@"CGContextCreate failed.");
        CGColorSpaceRelease(rgb);
        CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
        CFRelease(pxbuffer);
        return NULL;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);
    CGColorSpaceRelease(rgb);
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    return pxbuffer;
}

- (MLMultiArray *)multiArrayFromPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
    NSError *error = nil;
    MLMultiArray *array = [[MLMultiArray alloc] initWithShape:@[@1,@224,@224,@3]
                                                     dataType:MLMultiArrayDataTypeFloat32
                                                        error:&error];
    if (error) {
        SafeLog(@"MultiArray allocation failed: %@", error);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return nil;
    }
    int ptr = 0;
    for (int y = 0; y < height; y++) {
        uint8_t *row = baseAddress + y * bytesPerRow;
        for (int x = 0; x < width; x++) {
            uint8_t b = row[x * 4 + 0];
            uint8_t g = row[x * 4 + 1];
            uint8_t r = row[x * 4 + 2];
            array[ptr++] = @(r / 255.0f);
            array[ptr++] = @(g / 255.0f);
            array[ptr++] = @(b / 255.0f);
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    return array;
}

- (UIImage *)blackImageWithSize:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    [[UIColor blackColor] setFill];
    UIRectFill(CGRectMake(0,0,size.width,size.height));
    UIImage *blackImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return blackImg;
}

@end
