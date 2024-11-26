const std = @import("std");
const windows = std.os.windows;
const HKEY = windows.HKEY;

// Windows API function declarations
extern "advapi32" fn RegOpenKeyExW(
    hKey: HKEY,
    lpSubKey: [*:0]const u16,
    ulOptions: u32,
    samDesired: u32,
    phkResult: *HKEY,
) callconv(windows.WINAPI) windows.LONG;

extern "advapi32" fn RegSetValueExW(
    hKey: HKEY,
    lpValueName: [*:0]const u16,
    Reserved: u32,
    dwType: u32,
    lpData: [*]const u8,
    cbData: u32,
) callconv(windows.WINAPI) windows.LONG;

extern "advapi32" fn RegDeleteValueW(
    hKey: HKEY,
    lpValueName: [*:0]const u16,
) callconv(windows.WINAPI) windows.LONG;

extern "advapi32" fn RegCloseKey(
    hKey: HKEY,
) callconv(windows.WINAPI) windows.LONG;

const REGISTRY_PATH = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run";
const MAX_PATH = 260;
const ERROR_SUCCESS: windows.DWORD = 0;
const KEY_SET_VALUE = 0x0002;
const REG_SZ: windows.DWORD = 1;
const KEY_ALL_ACCESS = 0xF003F;
const REG_ENABLED = 0x00000000;
const REG_BINARY = 3;

pub fn enableAutoStart() !void {
    var buffer: [MAX_PATH]u16 = undefined;
    const len = windows.kernel32.GetModuleFileNameW(null, &buffer, MAX_PATH);
    if (len == 0) return error.GetModuleFileNameFailed;

    // Get directory path
    var path_buffer: [MAX_PATH]u8 = undefined;
    const utf8_result = std.unicode.utf16leToUtf8(&path_buffer, buffer[0..len]) catch return error.PathConversionFailed;
    const exe_path = path_buffer[0..utf8_result];
    const dir_path = std.fs.path.dirname(exe_path) orelse return error.NoPath;

    // Create full VBS path
    var vbs_path_buffer: [MAX_PATH]u8 = undefined;
    const vbs_path = try std.fmt.bufPrint(&vbs_path_buffer, "\"{s}\\run_as_admin.vbs\"", .{dir_path});

    // Convert to UTF16
    var vbs_path_utf16: [MAX_PATH]u16 = undefined;
    const utf16_len = try std.unicode.utf8ToUtf16Le(&vbs_path_utf16, vbs_path);
    const final_path = vbs_path_utf16[0..utf16_len];

    var key_handle: HKEY = undefined;
    const result = RegOpenKeyExW(
        windows.HKEY_CURRENT_USER,
        std.unicode.utf8ToUtf16LeStringLiteral(REGISTRY_PATH),
        0,
        KEY_ALL_ACCESS,
        &key_handle,
    );
    if (result != ERROR_SUCCESS) return error.RegOpenKeyFailed;
    defer _ = RegCloseKey(key_handle);

    const value_name = std.unicode.utf8ToUtf16LeStringLiteral("SystemInfoMonitor");
    const result2 = RegSetValueExW(
        key_handle,
        value_name,
        0,
        REG_SZ,
        @ptrCast(final_path.ptr),
        @intCast(final_path.len * 2 + 2),
    );
    if (result2 != ERROR_SUCCESS) return error.RegSetValueFailed;

    const startup_key = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run";
    var startup_handle: HKEY = undefined;
    const result3 = RegOpenKeyExW(
        windows.HKEY_CURRENT_USER,
        std.unicode.utf8ToUtf16LeStringLiteral(startup_key),
        0,
        KEY_ALL_ACCESS,
        &startup_handle,
    );
    if (result3 == ERROR_SUCCESS) {
        defer _ = RegCloseKey(startup_handle);

        var enabled_data = [_]u8{0} ** 12;
        enabled_data[0] = REG_ENABLED;

        _ = RegSetValueExW(
            startup_handle,
            value_name,
            0,
            REG_BINARY,
            &enabled_data,
            12,
        );
    }
}

pub fn disableAutoStart() !void {
    var key_handle: HKEY = undefined;
    const result = RegOpenKeyExW(
        windows.HKEY_CURRENT_USER,
        std.unicode.utf8ToUtf16LeStringLiteral(REGISTRY_PATH),
        0,
        KEY_SET_VALUE,
        &key_handle,
    );
    if (result != ERROR_SUCCESS) return error.RegOpenKeyFailed;
    defer _ = RegCloseKey(key_handle);

    const value_name = std.unicode.utf8ToUtf16LeStringLiteral("SystemInfoMonitor");
    const result2 = RegDeleteValueW(key_handle, value_name);
    if (result2 != ERROR_SUCCESS) return error.RegDeleteValueFailed;
}
