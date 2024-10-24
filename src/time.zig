const std = @import("std");

pub const Reader =
	@import("time/reader.zig").Reader;
pub const CoresIter =
	@import("time/cores.zig").CoresIter;

/// Cpu time spent since boot
pub const Time = struct {
	user:    u64 = 0,
	nice:    u64 = 0,
	system:  u64 = 0,
	idle:    u64 = 0,
	iowait:  u64 = 0,
	irq:     u64 = 0,
	softirq: u64 = 0,
	
	/// Same as `time.Reader.new()`
	pub inline fn reader() Reader {
		return Reader.new();
	}
	
	/// Same as `time.CoresIter.new()`
	pub inline fn cores() !CoresIter {
		return CoresIter.new();
	}
	
	/// Pointer to data interpreted as an array
	pub inline fn asArray(
		this: *const @This()
	) *const[
		@sizeOf(@This()) / @sizeOf(u64)
	]u64 {
		return @ptrCast(this);
	}
	
	/// Pointer to data interpreted as a mut array
	pub inline fn asArrayMut(
		this: *@This()
	) *[
		@sizeOf(@This()) / @sizeOf(u64)
	]u64 {
		return @ptrCast(this);
	}
	
	/// Parse a line like this one:
	/// "cpu2 10981 0 3244 282002 215 0 31 0 0 0"
	pub fn parse(line: []u8) !@This() {
		const space = std.mem.indexOfScalarPos(
			u8,
			line,
			"cpu".len,
			' '
		) orelse return error.InvalidProcStat;
		var start = std.mem.indexOfNonePos(
			u8,
			line,
			space + 1,
			" "
		) orelse return error.InvalidProcStat;
		
		var cpu = @This(){};
		for (cpu.asArrayMut()) |*item| {
			const end = std.mem.indexOfScalarPos(
				u8,
				line,
				start,
				' '
			) orelse return error.InvalidProcStat;
			const slice = line[start .. end];
			start = end + 1;
			
			item.* = try std.fmt.parseInt(
				u64,
				slice,
				10
			);
		}
		
		return cpu;
	}
	
	/// Current cpu `Time` spend by the kernel
	/// performing different kinds of work.
	/// See https://www.idnt.net/en-US/kb/941772
	pub fn now() !@This() {
		var file = try std.fs.openFileAbsolute(
			"/proc/stat",
			.{}
		);
		defer file.close();
		
		var buffer: [64]u8 = undefined;
		const size = try file.read(&buffer);
		
		return @This().parse(buffer[0 .. size]);
	}
	
	/// Sum of all the time spent by the kernel for
	/// different kinds of work.
	pub inline fn sum(this: @This()) u64 {
		var total: u64 = 0;
		for (this.asArray()) |item| {
			total += item;
		}
		return total;
	}
};

test "now" {
	const now = try Time.now();
	_ = now.sum();
}

test {
	std.testing.refAllDecls(@This());
}

