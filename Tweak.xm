#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <Security/Security.h>
#import <substrate.h>

// ==========================================
// 1. PHẦN CHỐNG VĂNG GAME (KEYCHAIN BYPASS)
// ==========================================

// Hook hàm SecItemCopyMatching để tránh lỗi văng do Keychain
OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result);
OSStatus hook_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus status = orig_SecItemCopyMatching(query, result);
    // Nếu iOS báo lỗi thiếu quyền hạn do sideload, ép nó trả về thành công
    if (status == errSecMissingEntitlement) {
        return errSecSuccess;
    }
    return status;
}

// Hook hàm SecItemAdd để cho phép game ghi dữ liệu giả lập vào Keychain
OSStatus (*orig_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result);
OSStatus hook_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    OSStatus status = orig_SecItemAdd(attributes, result);
    if (status == errSecMissingEntitlement) {
        return errSecSuccess;
    }
    return status;
}

// ==========================================
// 2. PHẦN GIẢ LẬP BUNDLE ID GỐC (SPOOF ID)
// ==========================================
%hook NSBundle
- (NSString *)bundleIdentifier {
    // Luôn trả về Bundle ID gốc của Liên Quân Việt Nam để qua mặt kiểm tra
    return @"com.garena.game.kgvn"; 
}
%end

// ==========================================
// 3. PHẦN TỐI ƯU/MỞ KHÓA FPS (DEVICE SPOOF)
// ==========================================
int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && strcmp(name, "hw.machine") == 0) {
        if (oldp) {
            // Giả lập thành iPad Pro M1 để game mở khóa 120 FPS và Đồ họa tối đa
            strcpy((char *)oldp, "iPad13,8");
        }
        return 0;
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

%hook UIDevice
- (NSString *)model { return @"iPad"; }
- (NSString *)localizedModel { return @"iPad"; }
- (NSString *)name { return @"iPad Pro"; }
- (NSString *)systemVersion { return @"17.0"; }
%end

// ==========================================
// KHỞI CHẠY TẤT CẢ HOOK KHI GAME LOAD
// ==========================================
%ctor {
    @autoreleasepool {
        // Kích hoạt các bản vá chống văng game (C Level)
        MSHookFunction((void *)SecItemCopyMatching, (void *)hook_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching);
        MSHookFunction((void *)SecItemAdd, (void *)hook_SecItemAdd, (void **)&orig_SecItemAdd);
        MSHookFunction((void *)sysctlbyname, (void *)hook_sysctlbyname, (void **)&orig_sysctlbyname);
        
        // Kích hoạt các bản vá Objective-C (NSBundle, UIDevice)
        %init;
    }
}
