const std = @import("std");
const SystemInfo = @import("../types/SystemInfo.zig");
const DiskStats = SystemInfo.DiskStats;
pub fn bytesToGB(bytes: u64) f64 {
    return @as(f64, @floatFromInt(bytes)) / (1024 * 1024 * 1024);
}

// Thêm hàm helper để làm sạch chuỗi số
fn cleanNumberString(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &[_]u8{ ' ', '"', '\r', '\n' });
}

pub fn getDiskInfo() !DiskStats {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var child = std.process.Child.init(&[_][]const u8{
        "wmic",
        "logicaldisk",
        "where",
        "DriveType=3",
        "get",
        "Size,FreeSpace",
        "/format:csv",
    }, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const buffer: [8192]u8 = undefined; // Changed from 'var' to 'const'
    const output = try child.stdout.?.reader().readAllAlloc(allocator, buffer.len);
    defer allocator.free(output);

    _ = try child.wait();

    if (output.len == 0) {
        return DiskStats{
            .total_space = 0,
            .used_space = 0,
            .free_space = 0,
            .disk_reads = 0,
            .disk_writes = 0,
        };
    }

    var total_space: u64 = 0;
    var free_space: u64 = 0;
    const used_space = if (total_space >= free_space)
        total_space - free_space
    else
        0;

    if (output.len > 0) {
        var lines = std.mem.split(u8, output, "\n");
        _ = lines.next(); // Skip header

        while (lines.next()) |line| {
            var fields = std.mem.split(u8, line, ",");
            _ = fields.next(); // Skip Node

            if (fields.next()) |size_str| {
                const clean_size = cleanNumberString(size_str);
                if (clean_size.len > 0) {
                    total_space = std.fmt.parseInt(u64, clean_size, 10) catch {
                        std.debug.print("Invalid size string: '{s}'\n", .{clean_size});
                        continue;
                    };
                }
            }

            if (fields.next()) |free_str| {
                const clean_free = cleanNumberString(free_str);
                if (clean_free.len > 0) {
                    free_space = std.fmt.parseInt(u64, clean_free, 10) catch {
                        std.debug.print("Invalid free space string: '{s}'\n", .{clean_free});
                        continue;
                    };
                }
            }
        }
    }

    var perf_child = std.process.Child.init(&[_][]const u8{
        "wmic",
        "diskdrive",
        "get",
        "BytesPerSecond,ReadBytesPerSecond,WriteBytesPerSecond",
        "/format:csv",
    }, allocator);

    perf_child.stdout_behavior = .Pipe;
    perf_child.stderr_behavior = .Pipe;

    try perf_child.spawn();

    const perf_output = try perf_child.stdout.?.reader().readAllAlloc(allocator, buffer.len);
    defer allocator.free(perf_output);

    _ = try perf_child.wait();

    var disk_reads: u64 = 0;
    var disk_writes: u64 = 0;

    if (perf_output.len > 0) {
        var perf_lines = std.mem.split(u8, perf_output, "\n");
        _ = perf_lines.next(); // Skip header

        while (perf_lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;

            var perf_fields = std.mem.split(u8, trimmed, ",");
            _ = perf_fields.next(); // Skip Node

            if (perf_fields.next()) |read_str| {
                if (std.fmt.parseInt(u64, std.mem.trim(u8, read_str, " "), 10)) |reads| {
                    disk_reads = reads;
                } else |_| {}
            }

            if (perf_fields.next()) |write_str| {
                if (std.fmt.parseInt(u64, std.mem.trim(u8, write_str, " "), 10)) |writes| {
                    disk_writes = writes;
                } else |_| {}
            }
        }
    }

    std.debug.print("Final values - Total: {}, Used: {}, Free: {}, Reads: {}, Writes: {}\n", .{ total_space, used_space, free_space, disk_reads, disk_writes });

    // Convert to GB before returning
    return DiskStats{
        .total_space = bytesToGB(total_space),
        .used_space = bytesToGB(used_space),
        .free_space = bytesToGB(free_space),
        .disk_reads = disk_reads,
        .disk_writes = disk_writes,
    };
}
