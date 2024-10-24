const std = @import("std");

const root = @import("../root.zig");
const Time = root.Time;

/// Cpu times reader
pub const Reader = struct {
	previous: Time,
	current: Time,
	
	/// Creates new reader with two empty `Time`.
	pub inline fn new() @This() {
		return .{
			.previous = .{},
			.current = .{},
		};
	}
	
	/// Gets usage from the delta and idle
	/// differences since the last `Time`.
	/// Returns a float from 0.0 to 1.0.
	/// See https://www.idnt.net/en-US/kb/941772.
	pub fn usage(this: *@This()) !f32 {
		this.previous = this.current;
		this.current = try Time.now();
		
		const delta = @as(f32, @floatFromInt(
			this.current.sum() -
			this.previous.sum()
		));
		const idle = @as(f32, @floatFromInt(
			this.current.idle -
			this.previous.idle
		));
		
		return (delta - idle) / delta;
	}
};

test "reader" {
	var reader = Reader.new();
	_ = try reader.usage();
}

