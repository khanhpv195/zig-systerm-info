const cpu_info = @import("cpu-info");
const zbench = @import("zbench");
const std = @import("std");

fn wrap(comptime function: anytype) fn (std.mem.Allocator) void {
    return struct {
        fn call(allocator: std.mem.Allocator) void {
            function(allocator) catch {};
        }
    }.call;
}

fn parseCpu(_: std.mem.Allocator) !void {
    const time = try cpu_info.Time.now();
    _ = time.sum();
}

fn parseCores(_: std.mem.Allocator) !void {
    var cores = try cpu_info.Time.cores();
    defer cores.deinit();

    while (try cores.next()) |core| {
        _ = core.sum();
    }
}

pub fn main() !void {
    var bench = zbench.Benchmark.init(std.heap.page_allocator, .{});
    defer bench.deinit();
    try bench.add("Parse cpu", wrap(parseCpu), .{ .iterations = std.math.maxInt(u16) });
    try bench.add("Parse cores", wrap(parseCores), .{ .iterations = std.math.maxInt(u16) });
    try bench.run(std.io.getStdOut().writer());
}
