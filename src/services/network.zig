const std = @import("std");

pub const NetworkStats = struct {
    bytes_sent: u64,
    bytes_received: u64,
    packets_sent: u64,
    packets_received: u64,
};

pub fn getNetworkInfo(writer: anytype) !NetworkStats {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var child = std.ChildProcess.init(&[_][]const u8{ "netstat", "-e" }, allocator);
    child.stdout_behavior = .Pipe;
    try child.spawn();

    var buffer: [4096]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);
    _ = try child.wait();

    // Print raw network information
    try writer.print("{s}\n", .{buffer[0..size]});

    // Parse netstat output
    var lines = std.mem.split(u8, buffer[0..size], "\n");

    // Skip header line
    _ = lines.next();

    // Get data line
    if (lines.next()) |line| {
        var values = std.mem.tokenize(u8, line, " \t");

        // Skip interface name
        _ = values.next();

        // Parse values
        const bytes_received = try std.fmt.parseInt(u64, values.next() orelse "0", 10);
        const packets_received = try std.fmt.parseInt(u64, values.next() orelse "0", 10);
        const bytes_sent = try std.fmt.parseInt(u64, values.next() orelse "0", 10);
        const packets_sent = try std.fmt.parseInt(u64, values.next() orelse "0", 10);

        return NetworkStats{
            .bytes_sent = bytes_sent,
            .bytes_received = bytes_received,
            .packets_sent = packets_sent,
            .packets_received = packets_received,
        };
    }

    // Fallback if parsing fails
    return NetworkStats{
        .bytes_sent = 0,
        .bytes_received = 0,
        .packets_sent = 0,
        .packets_received = 0,
    };
}
