const std = @import("std");
const cpu = @import("services/cpu.zig");
const memory = @import("services/memory.zig");
const disk = @import("services/disk.zig");
const network = @import("services/network.zig");
const saveToFile = @import("services/saveToFile.zig").saveToFile;
const SystemInfo = @import("types/SystemInfo.zig").SystemInfo;
const api = @import("services/api.zig");

pub fn main() !void {
    // Initialize allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var counter: u32 = 0;

    // Infinite loop for continuous monitoring
    while (true) {
        const current_time = std.time.timestamp();

        // Collect all system information
        const cpu_info = try cpu.getWindowsCpuInfo(allocator);
        const device_name = try cpu.getDeviceName(allocator);
        const memory_info = try memory.getMemoryInfo();
        const network_stats = try network.getNetworkInfo();
        const disk_stats = try disk.getDiskInfo();

        const info = SystemInfo{
            .timestamp = @as(u64, @intCast(current_time)),
            .cpu = .{
                .name = cpu_info.name,
                .manufacturer = cpu_info.manufacturer,
                .model = cpu_info.model,
                .speed = cpu_info.speed,
                .device_name = device_name,
            },
            .ram = .{
                .total_ram = memory_info.total_ram,
                .used_ram = memory_info.used_ram,
                .free_ram = memory_info.free_ram,
            },
            .disk = .{
                .total_space = disk_stats.total_space,
                .used_space = disk_stats.used_space,
                .free_space = disk_stats.free_space,
                .disk_reads = disk_stats.disk_reads,
                .disk_writes = disk_stats.disk_writes,
            },
            .network = .{
                .bytes_sent = network_stats.bytes_sent,
                .bytes_received = network_stats.bytes_received,
                .packets_sent = network_stats.packets_sent,
                .packets_received = network_stats.packets_received,
            },
        };

        // Save to file - pass device_name as third argument
        try saveToFile(allocator, info, device_name);

        // Increment counter and check if we need to send to API
        counter += 1;
        if (counter >= 10) {
            // try api.sendData(allocator, info);
            counter = 0;
        }

        // Wait for 1 minute before next iteration
        std.time.sleep(60 * std.time.ns_per_s);
    }
}
