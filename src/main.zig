const std = @import("std");
const cpu = @import("services/cpu.zig");
const memory = @import("services/memory.zig");
const disk = @import("services/disk.zig");
const network = @import("services/network.zig");
const saveToDb = @import("services/saveToDb.zig").saveToDb;
const SystemInfo = @import("types/SystemInfo.zig").SystemInfo;
const CpuInfo = @import("types/SystemInfo.zig").CpuInfo;
const api = @import("services/api.zig");
const windows = std.os.windows;

extern "kernel32" fn GetConsoleWindow() ?windows.HWND;
extern "user32" fn ShowWindow(hWnd: ?windows.HWND, nCmdShow: c_int) callconv(windows.WINAPI) c_int;
extern "kernel32" fn FreeConsole() callconv(windows.WINAPI) c_int;
extern "kernel32" fn AllocConsole() callconv(windows.WINAPI) c_int;

const SW_HIDE = 0;
const SW_SHOW = 5;

pub fn main() !void {
    _ = FreeConsole();
    _ = AllocConsole();
    const console_window = GetConsoleWindow();
    if (console_window) |window| {
        _ = ShowWindow(window, SW_HIDE);
    }

    // Initialize allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Pre-allocate buffers
    var disk_buffer = try std.ArrayList(u8).initCapacity(allocator, 4096);
    var network_buffer = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer disk_buffer.deinit();
    defer network_buffer.deinit();

    // Buffer to store 10 minutes of data
    var info_buffer = try std.ArrayList(SystemInfo).initCapacity(allocator, 10);
    defer info_buffer.deinit();

    const device_name = try cpu.getDeviceName(allocator);
    var counter: usize = 0;
    var last_collect_time = std.time.timestamp();

    while (true) {
        const current_time = std.time.timestamp();

        // Chỉ thu thập và lưu dữ liệu khi đã đủ 1 phút
        if (current_time - last_collect_time >= 60) {
            disk_buffer.clearRetainingCapacity();
            network_buffer.clearRetainingCapacity();

            const cpu_info = try cpu.getWindowsCpuInfo(allocator);
            const memory_info = try memory.getMemoryInfo();
            const disk_info = try disk.getDiskInfo();
            const network_info = try network.getNetworkInfo(network_buffer.writer());

            const info = SystemInfo{
                .timestamp = @as(u64, @intCast(std.time.timestamp())),
                .cpu = CpuInfo{
                    .name = cpu_info.name,
                    .manufacturer = cpu_info.manufacturer,
                    .model = cpu_info.model,
                    .speed = cpu_info.speed,
                    .device_name = device_name,
                    .usage = cpu_info.usage,
                },
                .ram = .{
                    .total_ram = @as(f64, @floatFromInt(memory_info.total_ram)),
                    .used_ram = @as(f64, @floatFromInt(memory_info.used_ram)),
                    .free_ram = @as(f64, @floatFromInt(memory_info.free_ram)),
                },
                .disk = .{
                    .total_space = disk_info.total_space,
                    .used_space = disk_info.used_space,
                    .free_space = disk_info.free_space,
                    .disk_reads = disk_info.disk_reads,
                    .disk_writes = disk_info.disk_writes,
                },
                .network = .{
                    .bytes_sent = network_info.bytes_sent,
                    .bytes_received = network_info.bytes_received,
                    .packets_sent = network_info.packets_sent,
                    .packets_received = network_info.packets_received,
                    .bandwidth_usage = network_info.bandwidth_usage,
                    .transfer_rate = network_info.transfer_rate,
                },
            };

            // Luôn lưu vào database mỗi phút
            try saveToDb(info, device_name);
            try info_buffer.append(info);

            counter += 1;
            last_collect_time = current_time;

            // Cứ 10 bản ghi thì gửi lên server và reset buffer
            if (counter >= 10) {
                try api.sendSystemInfo();
                info_buffer.clearRetainingCapacity();
                counter = 0;
            }
        }
    }
}
