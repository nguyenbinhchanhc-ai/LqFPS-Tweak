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
            // Giả lập thành iPhone 15 Pro Max để tránh lỗi cấu trúc Dynamic Island
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
    // Gọi phương thức gốc thông qua phương thức đã tráo đổi
    NSString *orig = [self my_bundleIdentifier]; 
    
    // CHỈ định danh Liên Quân cho Game. KHÔNG đổi Bundle ID cho chính LiveContainer
    // Nếu đổi của LiveContainer, LiveContainer sẽ không load được giao diện của chính nó (gây đen màn hình)
    if (orig && ([orig containsString:@"LiveContainer"] || [orig isEqualToString:@"ch.playcover.LiveContainer"])) {
        return orig; 
    }
    
    return @"com.garena.game.kgvn"; // Trả về Garena cho game Liên Quân
}
@end

@interface UIDevice (LqFPSSwizzle)
@end

@implementation UIDevice (LqFPSSwizzle)
- (NSString *)my_model { return @"iPhone"; }
- (NSString *)my_localizedModel { return @"iPhone"; }
- (NSString *)my_name { return @"iPhone 15 Pro Max"; }
- (NSString *)my_systemVersion { return @"17.0"; }
@end

// ============================================================================
// CHỐNG CRASH TẬP TIN HỆ THỐNG (NSASSERTIONHANDLER BYPASS)
// ============================================================================
@interface NSAssertionHandler (LqFPSSwizzle)
@end

@implementation NSAssertionHandler (LqFPSSwizzle)

- (void)my_handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(NSInteger)line description:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[LqFPSOptimizer] Bypassed NSAssertionHandler method failure: %@", description);
}

- (void)my_handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(NSInteger)line description:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[LqFPSOptimizer] Bypassed NSAssertionHandler function failure: %@", description);
}

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
        
        // Swizzle NSAssertionHandler để tắt hoàn toàn các crash do Assertion (như BoundingPathBitmap)
        swizzleMethod([NSAssertionHandler class], 
                      @selector(handleFailureInMethod:object:file:lineNumber:description:), 
                      @selector(my_handleFailureInMethod:object:file:lineNumber:description:));
                      
        swizzleMethod([NSAssertionHandler class], 
                      @selector(handleFailureInFunction:file:lineNumber:description:), 
                      @selector(my_handleFailureInFunction:file:lineNumber:description:));
                      
        NSLog(@"[LqFPSOptimizer] Standalone FPS & Anti-Crash Tweak initialized successfully!");
    }
}
