const std = @import("std");
const cpu = @import("services/cpu.zig");
const memory = @import("services/memory.zig");
const disk = @import("services/disk.zig");
const network = @import("services/network.zig");
const saveToDb = @import("services/saveToDb.zig").saveToDb;
const SystemInfo = @import("types/SystemInfo.zig").SystemInfo;
const CpuInfo = @import("types/SystemInfo.zig").CpuInfo;
const api = @import("services/api.zig");
const process_monitor = @import("services/process_monitor.zig");
const autostart = @import("services/autostart.zig");
const system_metrics = @import("services/system_metrics.zig");

const windows = std.os.windows;

extern "kernel32" fn GetConsoleWindow() ?windows.HWND;
extern "user32" fn ShowWindow(hWnd: ?windows.HWND, nCmdShow: c_int) callconv(windows.WINAPI) c_int;
extern "kernel32" fn FreeConsole() callconv(windows.WINAPI) c_int;
extern "kernel32" fn AllocConsole() callconv(windows.WINAPI) c_int;

const SW_HIDE = 0;
const SW_SHOW = 5;

fn writeToLog(comptime format: []const u8, args: anytype) !void {
    const log_path = "debug.log";
    const file = try std.fs.cwd().openFile(log_path, .{ .mode = .write_only });
    defer file.close();

    try file.seekFromEnd(0);
    var timestamp_buf: [64]u8 = undefined;
    const timestamp = std.time.timestamp();
    const formatted_time = try std.fmt.bufPrint(&timestamp_buf, "[{d}] ", .{timestamp});

    try file.writer().writeAll(formatted_time);
    try file.writer().print(format, args);
    try file.writer().writeAll("\n");
}

pub fn main() !void {
    // Cài đặt console
    _ = FreeConsole();
    _ = AllocConsole();
    const console_window = GetConsoleWindow();
    if (console_window) |window| {
        _ = ShowWindow(window, SW_HIDE);
    }

    // Khởi tạo allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Khởi tạo buffers
    var disk_buffer = try std.ArrayList(u8).initCapacity(allocator, 4096);
    var network_buffer = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer disk_buffer.deinit();
    defer network_buffer.deinit();

    var info_buffer = try std.ArrayList(SystemInfo).initCapacity(allocator, 10);
    defer info_buffer.deinit();

    // Lấy thông tin hệ thống
    const device_name = try cpu.getDeviceName(allocator);
    
    // Khởi tạo các biến theo dõi
    var last_collect_time = std.time.timestamp();
    var record_count: usize = 0;
    var current_db_created_time = std.time.timestamp();

    // Cài đặt autostart
    autostart.enableAutoStart() catch |err| {
        try writeToLog("Unable to set up auto-start: {}", .{err});
    };

    // Khởi tạo system metrics
    var metrics = try system_metrics.SystemMetrics.init();

    while (true) {
        const current_time = std.time.timestamp();

        if (current_time - last_collect_time >= 60) {
            // Thu thập metrics
            const system_info = metrics.collect() catch |err| {
                try writeToLog("Failed to collect metrics: {}", .{err});
                continue;
            };
            
            // Create a mutable copy of system_info
            var mutable_info = system_info;
            mutable_info.cpu.device_name = device_name;

            // Thu thập thông tin process
            const process_stats = process_monitor.getProcessStats("chrome.exe") catch |err| {
                try writeToLog("Failed to get process stats: {}", .{err});
                continue;
            };

            mutable_info.app = .{
                .pid = process_stats.pid,
                .cpu_usage = process_stats.cpu_usage,
                .memory_usage = process_stats.memory_usage,
                .disk_usage = process_stats.disk_usage,
            };

            // Lưu vào database
            saveToDb(mutable_info, device_name) catch |err| {
                try writeToLog("Failed to save to database: {}", .{err});
                continue;
            };

            record_count += 1;

            // Gửi dữ liệu lên server sau mỗi 10 bản ghi
            if (record_count >= 10) {
                api.sendSystemInfo() catch |err| {
                    try writeToLog("Failed to send data to server: {}", .{err});
                };

                record_count = 0;
                current_db_created_time = current_time;
            }

            last_collect_time = current_time;
        }

        std.time.sleep(1 * std.time.ns_per_s);
    }
}

