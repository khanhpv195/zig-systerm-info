const std = @import("std");
const SystemInfo = @import("../types/SystemInfo.zig").SystemInfo;

pub fn sendData() !void {
    // TODO: Implement your API call logic here
}

pub fn sendSystemInfo(allocator: std.mem.Allocator, info: []const SystemInfo) !void {
    // TODO: Implement your API call logic here
    _ = allocator;
    _ = info;
}
