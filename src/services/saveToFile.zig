const std = @import("std");
const fs = std.fs;
const SystemInfo = @import("../types/SystemInfo.zig").SystemInfo;

pub fn saveToFile(allocator: std.mem.Allocator, info: SystemInfo, device_name: []const u8) !void {
    // Convert timestamp to GMT+9 (Tokyo, Japan timezone)
    const timestamp = info.timestamp + (9 * std.time.s_per_hour);

    // Calculate date components with floor division to handle negative timestamps correctly
    const days = @divFloor(timestamp, std.time.s_per_day);
    const epoch_day = std.time.epoch.EpochDay{ .day = @intCast(days) };
    const year_day = epoch_day.calculateYearDay();

    const year = year_day.year;
    const day_of_year = year_day.day;

    // Calculate month and day
    var month: u8 = 1;
    var day_in_month: u16 = day_of_year;
    const is_leap_year = std.time.epoch.isLeapYear(year);
    const days_per_month = if (is_leap_year)
        &[_]u8{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    else
        &[_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    for (days_per_month, 0..) |days_in_month, i| {
        if (day_in_month <= days_in_month) break;
        day_in_month -= days_in_month;
        month = @intCast(i + 2);
    }

    const seconds_of_day = @mod(timestamp, std.time.s_per_day);
    const hour = @divFloor(seconds_of_day, std.time.s_per_hour);
    const minute = @divFloor(@mod(seconds_of_day, std.time.s_per_hour), std.time.s_per_min);

    // Create directory path: data/YYYY/MM/DD/
    const dir_path = try std.fmt.allocPrint(allocator, "data/{d}/{:0>2}/{:0>2}", .{ year, month, day_in_month });
    defer allocator.free(dir_path);

    // Create all directories in path
    try fs.cwd().makePath(dir_path);

    // Create filename with device name, hour and minute
    const filename = try std.fmt.allocPrint(allocator, "{s}/{s}_{:0>2}_{:0>2}.json", .{ dir_path, device_name, hour, minute });
    defer allocator.free(filename);

    // Create new file
    const file = try fs.cwd().createFile(filename, .{ .read = true });
    defer file.close();

    // Write JSON data to file
    const writer = file.writer();
    try std.json.stringify(info, .{}, writer);
}
