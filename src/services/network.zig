const std = @import("std");

pub const NetworkStats = struct {
    bytes_sent: u64,
    bytes_received: u64,
    packets_sent: u64,
    packets_received: u64,
};

pub fn getNetworkInfo() !NetworkStats {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = [_][]const u8{ "powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", "Get-NetAdapterStatistics | Select-Object BytesSent,BytesReceived,PacketsSent,PacketsReceived | Format-List" };
    var child = std.ChildProcess.init(&args, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    var buffer: [4096]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);
    _ = try child.wait();

    // Parse the output
    var lines = std.mem.split(u8, buffer[0..size], "\n");
    var bytes_sent: u64 = 0;
    var bytes_received: u64 = 0;
    var packets_sent: u64 = 0;
    var packets_received: u64 = 0;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (std.mem.startsWith(u8, trimmed, "BytesSent : ")) {
            bytes_sent = try std.fmt.parseInt(u64, trimmed[12..], 10);
        } else if (std.mem.startsWith(u8, trimmed, "BytesReceived : ")) {
            bytes_received = try std.fmt.parseInt(u64, trimmed[15..], 10);
        } else if (std.mem.startsWith(u8, trimmed, "PacketsSent : ")) {
            packets_sent = try std.fmt.parseInt(u64, trimmed[12..], 10);
        } else if (std.mem.startsWith(u8, trimmed, "PacketsReceived : ")) {
            packets_received = try std.fmt.parseInt(u64, trimmed[17..], 10);
        }
    }

    return NetworkStats{
        .bytes_sent = bytes_sent,
        .bytes_received = bytes_received,
        .packets_sent = packets_sent,
        .packets_received = packets_received,
    };
}
