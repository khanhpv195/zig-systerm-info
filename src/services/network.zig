const std = @import("std");
const SystemInfo = @import("../types/SystemInfo.zig");
const NetworkStats = SystemInfo.NetworkStats;

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

    // Skip header lines
    _ = lines.next(); // Skip "Interface Statistics"
    _ = lines.next(); // Skip empty line
    _ = lines.next(); // Skip "Received Sent" header
    _ = lines.next(); // Skip empty line

    // Parse bytes line
    const bytes_line = lines.next() orelse return NetworkStats{
        .bytes_sent = 0,
        .bytes_received = 0,
        .packets_sent = 0,
        .packets_received = 0,
        .bandwidth_usage = 0.0,
        .transfer_rate = 0.0,
    };

    var bytes_values = std.mem.tokenize(u8, bytes_line, " \t");
    _ = bytes_values.next();
    const bytes_received_str = bytes_values.next() orelse "0";
    const bytes_sent_str = bytes_values.next() orelse "0";

    const bytes_received = try std.fmt.parseInt(u64, std.mem.trim(u8, bytes_received_str, " \t\r\n"), 10);
    const bytes_sent = try std.fmt.parseInt(u64, std.mem.trim(u8, bytes_sent_str, " \t\r\n"), 10);

    // Parse packets line
    const packets_line = lines.next() orelse return NetworkStats{
        .bytes_sent = 0,
        .bytes_received = 0,
        .packets_sent = 0,
        .packets_received = 0,
        .bandwidth_usage = 0.0,
        .transfer_rate = 0.0,
    };

    var packet_values = std.mem.tokenize(u8, packets_line, " \t");
    _ = packet_values.next();
    _ = packet_values.next();

    // Now we should be at the actual numbers
    const packets_received_str = packet_values.next() orelse "0";
    const packets_sent_str = packet_values.next() orelse "0";

    const packets_received = try std.fmt.parseInt(u64, std.mem.trim(u8, packets_received_str, " \t\r\n"), 10);
    const packets_sent = try std.fmt.parseInt(u64, std.mem.trim(u8, packets_sent_str, " \t\r\n"), 10);

    const bandwidth_capacity = 1000000000;
    const transfer_rate = @as(f64, @floatFromInt(bytes_sent + bytes_received)) / 1.0;
    const bandwidth_usage = transfer_rate / @as(f64, @floatFromInt(bandwidth_capacity));

    return NetworkStats{
        .bytes_sent = @floatFromInt(bytes_sent),
        .bytes_received = @floatFromInt(bytes_received),
        .packets_sent = packets_sent,
        .packets_received = packets_received,
        .bandwidth_usage = bandwidth_usage,
        .transfer_rate = transfer_rate,
    };
}
