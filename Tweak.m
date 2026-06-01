#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <Security/Security.h>
#import <objc/runtime.h>

// ============================================================================
// 1. MACRO DYLD_INTERPOSE (CHỐNG VĂNG CHO APP KHÔNG JAILBREAK)
// ============================================================================
#define DYLD_INTERPOSE(_replacement,_replacee) \
__attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

// ============================================================================
// 2. CÁC HÀM C-LEVEL HOOK (BẰNG DYLD_INTERPOSE - ZERO DEPENDENCY)
// ============================================================================

// Hook sysctlbyname để giả lập phần cứng (Mở khóa 120 FPS)
int my_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && strcmp(name, "hw.machine") == 0) {
        if (oldp) {
            // Giả lập thành iPhone 15 Pro Max thay vì iPad để tránh lỗi lệch cấu trúc notch/Dynamic Island
            strcpy((char *)oldp, "iPhone16,2"); 
        }
        return 0;
    }
    return sysctlbyname(name, oldp, oldlenp, newp, newlen);
}
DYLD_INTERPOSE(my_sysctlbyname, sysctlbyname);

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
// 3. HÀM SWIZZLING ĐỂ HOOK OBJECTIVE-C (NSBUNDLE & UIDEVICE)
// ============================================================================
void swizzleMethod(Class class, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
    
    BOOL didAddMethod = class_addMethod(class,
                                        originalSelector,
                                        method_getImplementation(swizzledMethod),
                                        method_getTypeEncoding(swizzledMethod));
    
    if (didAddMethod) {
        class_replaceMethod(class,
                            swizzledSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

// ============================================================================
// 4. THAY THẾ PHƯƠNG THỨC HOOK (METHOD SWIZZLING IMPLEMENTATIONS)
// ============================================================================

@interface NSBundle (LqFPSSwizzle)
@end

@implementation NSBundle (LqFPSSwizzle)
- (NSString *)my_bundleIdentifier {
    return @"com.garena.game.kgvn"; // Giả lập Bundle ID gốc
}
@end

@interface UIDevice (LqFPSSwizzle)
@end

@implementation UIDevice (LqFPSSwizzle)
// Sửa thành "iPhone" thay vì "iPad" để tránh xung đột với độ phân giải màn hình của iPhone vật lý
- (NSString *)my_model { return @"iPhone"; }
- (NSString *)my_localizedModel { return @"iPhone"; }
- (NSString *)my_name { return @"iPhone 15 Pro Max"; }
- (NSString *)my_systemVersion { return @"17.0"; }
@end

// ============================================================================
// 5. KHỞI CHẠY KHI GAME LOAD (CONSTRUCTOR)
// ============================================================================
__attribute__((constructor)) static void init() {
    @autoreleasepool {
        // Swizzle NSBundle để đánh lừa Bundle ID
        swizzleMethod([NSBundle class], @selector(bundleIdentifier), @selector(my_bundleIdentifier));
        
        // Swizzle UIDevice để đồng bộ cấu hình iPhone giả lập
        swizzleMethod([UIDevice class], @selector(model), @selector(my_model));
        swizzleMethod([UIDevice class], @selector(localizedModel), @selector(my_localizedModel));
        swizzleMethod([UIDevice class], @selector(name), @selector(my_name));
        swizzleMethod([UIDevice class], @selector(systemVersion), @selector(my_systemVersion));
    }
}
