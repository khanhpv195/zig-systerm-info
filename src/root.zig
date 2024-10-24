const std = @import("std");

pub const time = @import("time.zig");
pub const Time = time.Time;

pub const core = @import("core.zig");
pub const Core = core.Core;

test {
	std.testing.refAllDecls(@This());
}

