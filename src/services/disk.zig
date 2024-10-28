const std = @import("std");
const SystemInfo = @import("../types/SystemInfo.zig");
const DiskStats = SystemInfo.DiskStats;
pub fn bytesToGB(bytes: u64) f64 {
    return @as(f64, @floatFromInt(bytes)) / (1024 * 1024 * 1024);
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
        std.debug.print("No output received from wmic\n", .{});
        return DiskStats{
            .total_space = 0,
            .used_space = 0,
            .free_space = 0,
            .disk_reads = 0,
            .disk_writes = 0,
        };
    }

    std.debug.print("WMIC Output: {s}\n", .{output});

    var total_space: u64 = 0;
    var free_space: u64 = 0;
    var used_space: u64 = 0;

    var lines = std.mem.split(u8, output, "\n");
    _ = lines.next(); // Skip header

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        std.debug.print("Processing line: {s}\n", .{trimmed});

        var fields = std.mem.split(u8, trimmed, ",");
        _ = fields.next(); // Skip Node
        if (fields.next()) |free_str| { // FreeSpace comes first
            const clean_free = std.mem.trim(u8, free_str, " ");
            if (fields.next()) |size_str| { // Size comes second
                const clean_size = std.mem.trim(u8, size_str, " ");
                std.debug.print("Size: {s}, Free: {s}\n", .{ clean_size, clean_free });

                if (std.fmt.parseInt(u64, clean_size, 10)) |size_bytes| {
                    if (std.fmt.parseInt(u64, clean_free, 10)) |free_bytes| {
                        total_space = size_bytes;
                        free_space = free_bytes;
                        if (size_bytes >= free_bytes) {
                            used_space = size_bytes - free_bytes;
                        } else {
                            std.debug.print("Warning: Free space larger than total size\n", .{});
                            used_space = 0;
                        }
                    } else |err| {
                        std.debug.print("Error parsing free space: {}\n", .{err});
                    }
                } else |err| {
                    std.debug.print("Error parsing total size: {}\n", .{err});
                }
            }
        }
    }

    // Thêm lệnh để lấy thông tin disk I/O
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
