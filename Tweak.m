#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>

// ============================================================================
// 1. MACRO DYLD_INTERPOSE (CHỐNG VĂNG KEYCHAIN KHI SIDELOAD)
// ============================================================================
#define DYLD_INTERPOSE(_replacement,_replacee) \
__attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

// Hook SecItemCopyMatching chống văng do Keychain
OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus status = SecItemCopyMatching(query, result);
    if (status == errSecMissingEntitlement) {
        return errSecSuccess;
    }
    return status;
}
DYLD_INTERPOSE(my_SecItemCopyMatching, SecItemCopyMatching);

// Hook SecItemAdd cho phép ghi dữ liệu Keychain
OSStatus my_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    OSStatus status = SecItemAdd(attributes, result);
    if (status == errSecMissingEntitlement) {
        return errSecSuccess;
    }
    return status;
}
DYLD_INTERPOSE(my_SecItemAdd, SecItemAdd);


// ============================================================================
// 2. HÀM SWIZZLING ĐỂ HOOK OBJECTIVE-C (ZERO DEPENDENCY)
// ============================================================================
void swizzleClassMethod(Class class, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getClassMethod(class, originalSelector);
    Method swizzledMethod = class_getClassMethod(class, swizzledSelector);
    
    Class metaClass = object_getClass(class);
    
    BOOL didAddMethod = class_addMethod(metaClass,
                                        originalSelector,
                                        method_getImplementation(swizzledMethod),
                                        method_getTypeEncoding(swizzledMethod));
    
    if (didAddMethod) {
        class_replaceMethod(metaClass,
                            swizzledSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}


// ============================================================================
// 3. VÁ LỖI CẤU TRÚC NOTCH MÀN HÌNH (IMAGE_NAMED HOOK - SIÊU SẠCH & AN TOÀN)
// ============================================================================
@interface UIImage (LqFPSSwizzle)
@end

@implementation UIImage (LqFPSSwizzle)

+ (UIImage *)my_imageNamed:(NSString *)name inBundle:(NSBundle *)bundle compatibleWithTraitCollection:(UITraitCollection *)traitCollection {
    if (name && [name containsString:@"BoundingPathBitmap"]) {
        NSLog(@"[LqFPSOptimizer] Intercepted BoundingPathBitmap request: %@", name);
        
        // Tạo một ảnh trống 1x1 trong suốt để UIKit không bị lỗi Asset và không kích hoạt Assertion Crash!
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0.0);
        UIImage *blankImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return blankImage;
    }
    return [self my_imageNamed:name inBundle:bundle compatibleWithTraitCollection:traitCollection];
}

@end


// ============================================================================
// 4. KHỞI CHẠY KHI GAME LOAD (CONSTRUCTOR)
// ============================================================================
__attribute__((constructor)) static void init() {
    @autoreleasepool {
        // Swizzle UIImage để tự động vá lỗi màn hình đen / crash notch BoundingPathBitmap cực kỳ sạch
        swizzleClassMethod([UIImage class], 
                           @selector(imageNamed:inBundle:compatibleWithTraitCollection:), 
                           @selector(my_imageNamed:inBundle:compatibleWithTraitCollection:));
                           
        NSLog(@"[LqFPSOptimizer] Standalone Anti-Crash Tweak initialized successfully!");
    }
}
