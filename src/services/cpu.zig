const std = @import("std");
const windows = std.os.windows;
const HQUERY = windows.HANDLE;
const HCOUNTER = windows.HANDLE;
const SystemInfo = @import("../types/SystemInfo.zig");
const CpuInfo = SystemInfo.CpuInfo;

// PDH function declarations
extern "pdh" fn PdhOpenQuery(
    DataSource: ?windows.LPCWSTR,
    UserData: windows.DWORD,
    Query: *HQUERY,
) windows.LONG;

extern "pdh" fn PdhAddCounterW(
    Query: HQUERY,
    CounterPath: windows.LPCWSTR,
    UserData: windows.DWORD,
    Counter: *HCOUNTER,
) windows.LONG;

extern "pdh" fn PdhCollectQueryData(
    Query: HQUERY,
) windows.LONG;

extern "pdh" fn PdhCloseQuery(
    Query: HQUERY,
) windows.LONG;

// Add these type declarations at the top with other constants
const PDH_FMT_DOUBLE = 0x00000200;

const PDH_FMT_COUNTERVALUE = extern struct {
    CStatus: windows.LONG,
    doubleValue: f64,
};

extern "pdh" fn PdhGetFormattedCounterValue(
    Counter: HCOUNTER,
    Format: windows.DWORD,
    Reserved: ?*windows.DWORD,
    Value: *PDH_FMT_COUNTERVALUE,
) windows.LONG;

pub fn getWindowsCpuInfo(allocator: std.mem.Allocator) !CpuInfo {
    // Use wmic to get CPU information
    var child = std.ChildProcess.init(&[_][]const u8{ "wmic", "cpu", "get", "name,manufacturer,maxclockspeed" }, allocator);
    child.stdout_behavior = .Pipe;
    try child.spawn();

    var buffer: [1024]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);
    _ = try child.wait();

    const output = buffer[0..size];

    // Parse the output
    var manufacturer: []const u8 = "Unknown";
    var model: []const u8 = "Unknown";
    var speed: []const u8 = "Unknown";
    var name: []const u8 = "Unknown";

    if (std.mem.indexOf(u8, output, "Intel")) |_| {
        manufacturer = try allocator.dupe(u8, "Intel");

        // Parse the model and speed from the full name
        const clean_output = std.mem.trim(u8, output, &[_]u8{ '\r', '\n', ' ' });
        const start_model = std.mem.indexOf(u8, clean_output, "Core") orelse 0;
        const end_model = std.mem.indexOf(u8, clean_output, "@") orelse clean_output.len;

        if (start_model > 0 and end_model > start_model) {
            model = try allocator.dupe(u8, std.mem.trim(u8, clean_output[start_model..end_model], &[_]u8{' '}));

            if (end_model < clean_output.len) {
                speed = try allocator.dupe(u8, std.mem.trim(u8, clean_output[end_model + 1 ..], &[_]u8{' '}));
            }
        }

        name = try allocator.dupe(u8, clean_output);
    }

    //  CPU usage
    const cpu_usage = try getCpuUsage();

    return CpuInfo{
        .name = name,
        .manufacturer = manufacturer,
        .model = model,
        .speed = speed,
        .device_name = try getDeviceName(allocator),
        .usage = cpu_usage,
    };
}

pub fn getDeviceName(allocator: std.mem.Allocator) ![]const u8 {
    // Use wmic to get device name
    var child = std.ChildProcess.init(&[_][]const u8{ "wmic", "computersystem", "get", "name" }, allocator);
    child.stdout_behavior = .Pipe;
    try child.spawn();

    var buffer: [1024]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);
    _ = try child.wait();

    const output = buffer[0..size];

    // Skip the header line and trim whitespace
    if (std.mem.indexOf(u8, output, "\n")) |newline_pos| {
        const device_name = std.mem.trim(u8, output[newline_pos..], &[_]u8{ '\r', '\n', ' ' });
        return try allocator.dupe(u8, device_name);
    }

    return try allocator.dupe(u8, "Unknown");
}

const FILETIME = windows.FILETIME;

extern "kernel32" fn GetSystemTimes(
    lpIdleTime: *FILETIME,
    lpKernelTime: *FILETIME,
    lpUserTime: *FILETIME,
) windows.BOOL;

pub fn getCpuUsage() !u32 {
    var query: HQUERY = undefined;
    var counter: HCOUNTER = undefined;
    var counter_value: PDH_FMT_COUNTERVALUE = undefined;

    // Open a query
    if (PdhOpenQuery(null, 0, &query) != 0) {
        return error.PdhOpenQueryFailed;
    }
    defer _ = PdhCloseQuery(query);

    // Add CPU counter
    const counter_path = L("\\Processor Information(_Total)\\% Processor Time");
    if (PdhAddCounterW(query, counter_path, 0, &counter) != 0) {
        return error.PdhAddCounterFailed;
    }

    // First collection
    if (PdhCollectQueryData(query) != 0) {
        return error.PdhCollectQueryDataFailed;
    }

    // Wait for a second collection
    std.time.sleep(1 * std.time.ns_per_s);

    // Second collection
    if (PdhCollectQueryData(query) != 0) {
        return error.PdhCollectQueryDataFailed;
    }

    // Get the formatted value
    if (PdhGetFormattedCounterValue(counter, PDH_FMT_DOUBLE, null, &counter_value) != 0) {
        return error.PdhGetFormattedCounterValueFailed;
    }

    const usage = @as(u32, @intFromFloat(@floor(counter_value.doubleValue)));
    return if (usage > 100) 100 else usage;
}

fn L(comptime str: []const u8) [:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(str);
}
