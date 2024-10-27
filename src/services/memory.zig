const std = @import("std");

pub const MemoryInfo = struct {
    total_ram: u64,
    used_ram: u64,
    free_ram: u64,
};

fn bytesToGB(bytes: u64) f64 {
    return @as(f64, @floatFromInt(bytes)) / (1024 * 1024 * 1024);
}

pub fn getMemoryInfo() !MemoryInfo {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get total RAM
    const total_args = [_][]const u8{ "powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", "Get-WmiObject Win32_ComputerSystem | Select-Object TotalPhysicalMemory | Format-List" };
    var total_ram_cmd = std.ChildProcess.init(&total_args, allocator);
    total_ram_cmd.stdout_behavior = .Pipe;
    total_ram_cmd.stderr_behavior = .Ignore;

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

    // Get free RAM using PowerShell instead of wmic
    const free_args = [_][]const u8{ "powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", "Get-WmiObject Win32_OperatingSystem | Select-Object FreePhysicalMemory | Format-List" };
    var free_ram_cmd = std.ChildProcess.init(&free_args, allocator);
    free_ram_cmd.stdout_behavior = .Pipe;
    free_ram_cmd.stderr_behavior = .Ignore;

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
