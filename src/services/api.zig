const std = @import("std");
const SystemInfo = @import("../types/SystemInfo.zig").SystemInfo;

pub fn sendData() !void {
    std.debug.print("Sending data to API\n", .{});
}
