const std = @import("std");

pub fn bytesToGB(bytes: u64) f64 {
    return @as(f64, @floatFromInt(bytes)) / (1024 * 1024 * 1024);
}

pub const DiskStats = struct {
    total_space: u64,
    used_space: u64,
    free_space: u64,
    disk_reads: u64,
    disk_writes: u64,
};

pub fn getDiskInfo() !DiskStats {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var total_space: u64 = 0;
    var free_space: u64 = 0;
    var used_space: u64 = 0;

    // Get list of drives and their sizes using PowerShell
    const args = [_][]const u8{ "powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", "Get-WmiObject Win32_LogicalDisk | Where-Object DriveType -eq 3 | Select-Object DeviceID,Size,FreeSpace | Format-List" };
    var child = std.ChildProcess.init(&args, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    var buffer: [4096]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);
    _ = try child.wait();

    // Process each drive's information
    var lines = std.mem.split(u8, buffer[0..size], "\n");
    var current_drive: ?[]const u8 = null;
    var current_size: u64 = 0;
    var current_free: u64 = 0;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        if (std.mem.startsWith(u8, trimmed, "DeviceID : ")) {
            current_drive = trimmed[11..];
        } else if (std.mem.startsWith(u8, trimmed, "Size : ")) {
            current_size = try std.fmt.parseInt(u64, trimmed[7..], 10);
        } else if (std.mem.startsWith(u8, trimmed, "FreeSpace : ")) {
            current_free = try std.fmt.parseInt(u64, trimmed[12..], 10);

            // Add to totals
            total_space += current_size;
            free_space += current_free;
            used_space += current_size - current_free;
        }
    }

    return DiskStats{
        .total_space = total_space,
        .used_space = used_space,
        .free_space = free_space,
        .disk_reads = 0,
        .disk_writes = 0,
    };
}
