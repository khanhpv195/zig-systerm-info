const std = @import("std");

pub fn bytesToGB(bytes: u64) f64 {
    return @as(f64, @floatFromInt(bytes)) / (1024 * 1024 * 1024);
}

pub fn getDiskInfo(writer: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get list of drives
    var drives_child = std.ChildProcess.init(&[_][]const u8{
        "wmic",
        "logicaldisk",
        "where",
        "DriveType=3",
        "get",
        "DeviceID",
        "/value",
    }, allocator);
    drives_child.stdout_behavior = .Pipe;
    try drives_child.spawn();
    defer _ = drives_child.wait() catch {};

    var buffer: [4096]u8 = undefined;
    const drives_stdout = drives_child.stdout.?.reader();
    const drives_size = try drives_stdout.readAll(&buffer);

    try writer.print("\nDrive\tTotal\t\tFree\t\tUsed\n", .{});
    try writer.print("------------------------------------------------\n", .{});

    // Process each drive
    const drives_output = buffer[0..drives_size];
    var lines = std.mem.split(u8, drives_output, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len != 0 and std.mem.startsWith(u8, trimmed, "DeviceID")) {
            const drive = trimmed[9..];

            // Get size of the drive
            var size_child = std.ChildProcess.init(&[_][]const u8{
                "wmic",
                "logicaldisk",
                "where",
                try std.fmt.allocPrint(allocator, "DeviceID='{s}'", .{drive}),
                "get",
                "Size",
                "/value",
            }, allocator);
            size_child.stdout_behavior = .Pipe;
            try size_child.spawn();
            defer _ = size_child.wait() catch {};

            var size_buffer: [1024]u8 = undefined;
            const size_stdout = size_child.stdout.?.reader();
            const size_read = try size_stdout.readAll(&size_buffer);

            // Get free space of the drive
            var free_child = std.ChildProcess.init(&[_][]const u8{
                "wmic",
                "logicaldisk",
                "where",
                try std.fmt.allocPrint(allocator, "DeviceID='{s}'", .{drive}),
                "get",
                "FreeSpace",
                "/value",
            }, allocator);
            free_child.stdout_behavior = .Pipe;
            try free_child.spawn();
            defer _ = free_child.wait() catch {};

            var free_buffer: [1024]u8 = undefined;
            const free_stdout = free_child.stdout.?.reader();
            const free_read = try free_stdout.readAll(&free_buffer);

            // Parse sizes and display information
            var size_str = std.mem.trim(u8, size_buffer[0..size_read], &std.ascii.whitespace);
            var free_str = std.mem.trim(u8, free_buffer[0..free_read], &std.ascii.whitespace);

            if (std.mem.indexOf(u8, size_str, "=")) |index| {
                size_str = size_str[index + 1 ..];
            }
            if (std.mem.indexOf(u8, free_str, "=")) |index| {
                free_str = free_str[index + 1 ..];
            }

            const size_bytes = try std.fmt.parseInt(u64, size_str, 10);
            const free_bytes = try std.fmt.parseInt(u64, free_str, 10);
            const used_bytes = size_bytes - free_bytes;

            const size_gb = bytesToGB(size_bytes);
            const free_gb = bytesToGB(free_bytes);
            const used_gb = bytesToGB(used_bytes);

            try writer.print("{s}\t{d:.1} GB\t{d:.1} GB\t{d:.1} GB\n", .{
                drive,
                size_gb,
                free_gb,
                used_gb,
            });
        }
    }
}
