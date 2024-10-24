const std = @import("std");

pub fn getNetworkInfo(writer: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Simplified ipconfig output
    var child = std.ChildProcess.init(&[_][]const u8{ "ipconfig", "/all" }, allocator);
    child.stdout_behavior = .Pipe;
    try child.spawn();

    var buffer: [4096]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);
    _ = try child.wait();

    try writer.print("{s}\n", .{buffer[0..size]});
}
