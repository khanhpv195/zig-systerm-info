const std = @import("std");

pub fn getWindowsCpuInfo(allocator: std.mem.Allocator) ![]const u8 {
    // Use wmic to get CPU information
    var child = std.ChildProcess.init(&[_][]const u8{ "wmic", "cpu", "get", "name" }, allocator);
    child.stdout_behavior = .Pipe;
    try child.spawn();

    var buffer: [1024]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);
    _ = try child.wait();

    return try allocator.dupe(u8, buffer[0..size]);
}
