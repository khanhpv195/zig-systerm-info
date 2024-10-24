const std = @import("std");
const fs = std.fs;
const SystemInfo = @import("../types/SystemInfo.zig").SystemInfo;
const getDiskInfo = @import("./disk.zig").getDiskInfo;
const getNetworkInfo = @import("./network.zig").getNetworkInfo;

fn getLogFilePath() ![]u8 {
    var buffer: [100]u8 = undefined;
    const now = std.time.timestamp();

    // Calculate date/time components
    const seconds_per_day = 24 * 60 * 60;
    const days_since_epoch = @divTrunc(now, seconds_per_day);
    const seconds_in_day = @mod(now, seconds_per_day);

    // Calculate hour
    const hour = @divTrunc(seconds_in_day, 3600);

    // Get current minutes from Timer
    var timer = try std.time.Timer.start();
    const current_time = timer.read();
    const minutes = @divTrunc(current_time, std.time.ns_per_min) % 60;

    // Calculate month and day (approximate)
    const days_per_month = [_]u16{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var days_remaining = @mod(days_since_epoch + 1, 365);
    var month: u8 = 1;

    for (days_per_month, 0..) |days, i| {
        if (days_remaining > days) {
            days_remaining -= days;
            continue;
        }
        month = @intCast(i + 1);
        break;
    }

    const day = @as(u8, @intCast(days_remaining));

    // Format: metrics_MM_DD_HH_mm.txt
    const path = try std.fmt.bufPrint(&buffer, "metrics_{:0>2}_{:0>2}_{:0>2}_{:0>2}.txt", .{
        month,
        day,
        hour,
        minutes,
    });

    return buffer[0..path.len];
}

pub fn saveToFile(info: SystemInfo) !void {
    // Get the file name based on the time
    const log_file_path = try getLogFilePath();

    // Create a new file (truncate = true to overwrite if the file already exists)
    const file = try fs.cwd().createFile(log_file_path, .{ .read = true, .truncate = true });
    defer file.close();

    const writer = file.writer();

    // Add a separator between each log entry
    try writer.writeAll("\n=== System Information === (");
    try writer.print("{}", .{std.time.epoch.EpochSeconds{ .secs = @intCast(info.timestamp) }});
    try writer.writeAll(")\n");

    // CPU Information
    try writer.writeAll("\n--- CPU Information ---\n");
    try writer.print("{s}\n", .{info.cpu});

    // Memory Information
    try writer.writeAll("\n--- Memory Information ---\n");
    try writer.print("Total RAM: {d:.2} GB\n", .{info.total_ram});
    try writer.print("Used RAM: {d:.2} GB\n", .{info.used_ram});
    try writer.print("Free RAM: {d:.2} GB\n", .{info.free_ram});

    // Disk Information
    try writer.writeAll("\n--- Disk Information ---\n");
    try writer.writeAll("\nDrive\tTotal\t\tFree\t\tUsed\n");
    try writer.writeAll("------------------------------------------------\n");

    // Collect and save disk information using the disk service
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var disk_buffer = std.ArrayList(u8).init(allocator);
    defer disk_buffer.deinit();
    try getDiskInfo(disk_buffer.writer());
    try writer.writeAll(disk_buffer.items);

    // Network Information
    try writer.writeAll("\n--- Network Information ---\n");
    var net_buffer = std.ArrayList(u8).init(allocator);
    defer net_buffer.deinit();
    try getNetworkInfo(net_buffer.writer());
    try writer.writeAll(net_buffer.items);

    // Add a final separator
    try writer.writeAll("\n========================================\n");
}
