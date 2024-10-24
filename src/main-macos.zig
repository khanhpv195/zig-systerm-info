const std = @import("std");
const builtin = @import("builtin");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Get basic CPU info
    const cpu_count = try std.Thread.getCpuCount();
    try stdout.print("Number of CPU cores: {}\n", .{cpu_count});

    // Platform-specific info
    switch (builtin.os.tag) {
        .linux => try getProcCpuInfo(stdout),
        .macos => try getMacOsCpuInfo(stdout),
        .windows => try getWindowsCpuInfo(stdout),
        else => try stdout.print("Unsupported operating system\n", .{}),
    }
}

fn getProcCpuInfo(writer: anytype) !void {
    const file = try std.fs.openFileAbsolute("/proc/cpuinfo", .{ .mode = .read_only });
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();
    var buf: [1024]u8 = undefined;

    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        try writer.print("{s}\n", .{line});
    }
}

fn getMacOsCpuInfo(writer: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var child = std.ChildProcess.init(&[_][]const u8{ "sysctl", "-n", "machdep.cpu.brand_string" }, allocator);
    child.stdout_behavior = .Pipe;
    try child.spawn();

    var buffer: [1024]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code == 0) {
                try writer.print("CPU: {s}\n", .{buffer[0..size]});
            } else {
                try writer.print("sysctl failed with exit code: {}\n", .{code});
            }
        },
        else => try writer.print("sysctl failed to execute\n", .{}),
    }
}

fn getWindowsCpuInfo(writer: anytype) !void {
    try writer.print("Windows CPU info retrieval not implemented\n", .{});
}
