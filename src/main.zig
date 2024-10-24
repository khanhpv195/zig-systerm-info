const std = @import("std");
const cpu = @import("services/cpu.zig");
const memory = @import("services/memory.zig");
const disk = @import("services/disk.zig");
const network = @import("services/network.zig");
const saveToFile = @import("services/saveToFile.zig").saveToFile;
const SystemInfo = @import("types/SystemInfo.zig").SystemInfo;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Create allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Collect system information from services
    const cpu_info = try cpu.getWindowsCpuInfo(allocator);
    const memory_info = try memory.getMemoryInfo();

    // Construct the SystemInfo struct with actual data
    const info = SystemInfo{
        .timestamp = @as(u64, @intCast(std.time.timestamp())),
        .cpu = cpu_info,
        .total_ram = memory_info.total_ram,
        .used_ram = memory_info.used_ram,
        .free_ram = memory_info.free_ram,
    };

    // Save system information to the log file
    try saveToFile(info);

    // Print system information to console
    try stdout.print("System information saved to file.\n", .{});
}
