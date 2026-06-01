#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Lưu giữ địa chỉ hàm gốc của hệ thống để khôi phục sau đó
static IMP orig_handleFailureInMethod = NULL;
static IMP orig_handleFailureInFunction = NULL;

static Method method_method = NULL;
static Method function_method = NULL;

// ============================================================================
// 1. CÁC HÀM HOOK TẠM THỜI (CHỈ CHẠY TRONG 8 GIÂY ĐẦU KHỞI ĐỘNG)
// ============================================================================
void my_handleFailureInMethod(id self, SEL _cmd, SEL selector, id object, NSString *fileName, NSInteger line, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[LqFPSOptimizer] Bypassed NSAssertionHandler method failure during startup: %@", description);
}

void my_handleFailureInFunction(id self, SEL _cmd, NSString *functionName, NSString *fileName, NSInteger line, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[LqFPSOptimizer] Bypassed NSAssertionHandler function failure during startup: %@", description);
}

// ============================================================================
// 2. HÀM THỰC HIỆN HOOK
// ============================================================================
void swizzleAssertionHandler() {
    Class class = [NSAssertionHandler class];
    
    SEL sel_method = @selector(handleFailureInMethod:object:file:lineNumber:description:);
    SEL sel_function = @selector(handleFailureInFunction:file:lineNumber:description:);
    
    method_method = class_getInstanceMethod(class, sel_method);
    function_method = class_getInstanceMethod(class, sel_function);
    
    if (method_method && function_method) {
        // Thực hiện hook và lưu lại IMP gốc
        orig_handleFailureInMethod = method_setImplementation(method_method, (IMP)my_handleFailureInMethod);
        orig_handleFailureInFunction = method_setImplementation(function_method, (IMP)my_handleFailureInFunction);
        NSLog(@"[LqFPSOptimizer] Successfully swizzled NSAssertionHandler for startup bypass.");
    }
}

// ============================================================================
// 3. HÀM KHÔI PHỤC NGUYÊN BẢN (REVERT HOOK - TRÁNH TENCENT ANTI-CHEAT)
// ============================================================================
void restoreAssertionHandler() {
    if (method_method && orig_handleFailureInMethod) {
        method_setImplementation(method_method, orig_handleFailureInMethod);
    }
    if (function_method && orig_handleFailureInFunction) {
        method_setImplementation(function_method, orig_handleFailureInFunction);
    }
    NSLog(@"[LqFPSOptimizer] Successfully RESTORED NSAssertionHandler to 100%% original system state!");
}

// ============================================================================
// 4. KHỞI CHẠY KHI GAME LOAD (CONSTRUCTOR STEALTH MODE)
// ============================================================================
__attribute__((constructor)) static void init() {
    @autoreleasepool {
        // Bước 1: Hook tạm thời bộ báo lỗi lúc mở game để tránh lỗi văng notch màn hình BoundingPathBitmap
        swizzleAssertionHandler();
        
        // Bước 2: Tự động KHÔI PHỤC lại nguyên bản 100% mã nguồn hệ thống sau 8 giây
        // (Lúc này game đã qua logo và vào sảnh chính. Khi vào trận đấu, MTP quét bộ nhớ sẽ thấy hệ thống sạch 100%)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            restoreAssertionHandler();
        });
    }
}
