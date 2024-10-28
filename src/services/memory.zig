const std = @import("std");

const SystemInfo = @import("../types/SystemInfo.zig");
const MemoryInfo = SystemInfo.MemoryInfo;

fn bytesToGB(bytes: u64) f64 {
    return @as(f64, @floatFromInt(bytes)) / (1024 * 1024 * 1024);
}

pub fn getMemoryInfo() !MemoryInfo {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get total RAM
    var total_ram_cmd = std.ChildProcess.init(&[_][]const u8{ "wmic", "computersystem", "get", "totalphysicalmemory" }, allocator);
    total_ram_cmd.stdout_behavior = .Pipe;
    try total_ram_cmd.spawn();

    var buffer1: [1024]u8 = undefined;
    const total_stdout = total_ram_cmd.stdout.?.reader();
    const total_size = try total_stdout.readAll(&buffer1);
    _ = try total_ram_cmd.wait();

    // Parse total RAM
    var lines = std.mem.split(u8, buffer1[0..total_size], "\n");
    _ = lines.next(); // Skip header
    var total_bytes: u64 = 0;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len != 0) {
            total_bytes = try std.fmt.parseInt(u64, trimmed, 10);
            break;
        }
    }

    // Get free RAM
    var free_ram_cmd = std.ChildProcess.init(&[_][]const u8{ "wmic", "OS", "get", "FreePhysicalMemory" }, allocator);
    free_ram_cmd.stdout_behavior = .Pipe;
    try free_ram_cmd.spawn();

    var buffer2: [1024]u8 = undefined;
    const free_stdout = free_ram_cmd.stdout.?.reader();
    const free_size = try free_stdout.readAll(&buffer2);
    _ = try free_ram_cmd.wait();

    // Parse free RAM
    lines = std.mem.split(u8, buffer2[0..free_size], "\n");
    _ = lines.next(); // Skip header
    var free_kb: u64 = 0;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len != 0) {
            free_kb = try std.fmt.parseInt(u64, trimmed, 10);
            break;
        }
    }

    const free_bytes = free_kb * 1024;
    const used_bytes = total_bytes - free_bytes;

    return MemoryInfo{
        .total_ram = total_bytes,
        .used_ram = used_bytes,
        .free_ram = free_bytes,
    };
}
