const std = @import("std");
const fs = std.fs;
const SystemInfo = @import("../types/SystemInfo.zig").SystemInfo;
const CpuInfo = @import("../types/SystemInfo.zig").CpuInfo;
const NetworkInfo = @import("../types/SystemInfo.zig").NetworkInfo;
const RamInfo = @import("../types/SystemInfo.zig").RamInfo;
const DiskInfo = @import("../types/SystemInfo.zig").DiskInfo;

// Add at the top with other constants
const TIMEZONE_OFFSET = 9 * std.time.s_per_hour; // UTC+9 (Tokyo)

fn bytesToGB(bytes: f64) f64 {
    return @round(bytes / (1024 * 1024 * 1024) * 100) / 100;
}

fn roundFloat(value: f64) f64 {
    return @round(value * 100) / 100;
}

fn bytesToMB(bytes: f64) f64 {
    return @round(bytes / (1024 * 1024) * 100) / 100;
}

pub fn saveToFile(allocator: std.mem.Allocator, info: SystemInfo, device_name: []const u8) !void {
    const current_time = std.time.timestamp();
    const local_timestamp = current_time + TIMEZONE_OFFSET;
    const days = @divFloor(local_timestamp, std.time.s_per_day) + 1;
    const seconds_of_day = @mod(local_timestamp, std.time.s_per_day);

    // Calculate date components
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

    const enhanced_info = SystemInfo{
        .timestamp = info.timestamp,
        .cpu = info.cpu,
        .ram = RamInfo{
            .total_ram = bytesToGB(info.ram.total_ram),
            .used_ram = bytesToGB(info.ram.used_ram),
            .free_ram = bytesToGB(info.ram.free_ram),
        },
        .disk = DiskInfo{
            .total_space = info.disk.total_space,
            .used_space = info.disk.used_space,
            .free_space = info.disk.free_space,
            .disk_reads = info.disk.disk_reads,
            .disk_writes = info.disk.disk_writes,
        },
        .network = NetworkInfo{
            .bytes_sent = bytesToGB(info.network.bytes_sent),
            .bytes_received = bytesToGB(info.network.bytes_received),
            .packets_sent = info.network.packets_sent,
            .packets_received = info.network.packets_received,
            .bandwidth_usage = roundFloat(info.network.bandwidth_usage),
            .transfer_rate = roundFloat(bytesToMB(info.network.bytes_sent + info.network.bytes_received)),
        },
    };

    // Thêm debug để kiểm tra giá trị trước khi ghi file
    std.debug.print("Disk values before writing - Total: {d}, Used: {d}, Free: {d}\n", .{ enhanced_info.disk.total_space, enhanced_info.disk.used_space, enhanced_info.disk.free_space });

    // Write JSON data to file
    const writer = file.writer();
    try std.json.stringify(enhanced_info, .{}, writer);
}
