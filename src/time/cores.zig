const std = @import("std");

const root = @import("../root.zig");
const Time = root.Time;

/// Iterator for cores that also parses the total
/// cpu times in the `.total` field.
/// Must run `.deinit()`!
pub const CoresIter = struct {
	reader: std.fs.File.Reader,
	total: Time,
	
	/// Creates a new instance, also reads and
	/// parses the line for the total cpu times.
	/// Run `.deinit()` to close the inner file!
	pub fn new() !@This() {
		const file = try std.fs.openFileAbsolute(
			"/proc/stat",
			.{}
		);
		
		var buffer: [128]u8 = undefined;
		var stream =
			std.io.fixedBufferStream(&buffer);
		
		var file_reader = file.reader();
		try file_reader.streamUntilDelimiter(
			stream.writer(),
			'\n',
			128
		);
		const line = stream.getWritten();
		const total = try Time.parse(line);
		
		return .{
			.reader = file_reader,
			.total = total,
		};
	}
	
	/// Closes the inner file
	pub inline fn deinit(this: *@This()) void {
		this.reader.context.close();
	}
	
	/// Read and parse next core line
	pub fn next(this: *@This()) !?Time {
		var buffer: [128]u8 = undefined;
		var stream =
			std.io.fixedBufferStream(&buffer);
		
		this.reader.streamUntilDelimiter(
			stream.writer(),
			'\n',
			buffer.len
		) catch |err| {
			if (err == error.StreamTooLong) {
				return null;
			}
			return err;
		};
		
		const line = stream.getWritten();
		return try Time.parse(line);
	}
};

test "cores" {
	var cores = try CoresIter.new();
	defer cores.deinit();
	
	var tolerance: u64 = 0;
	var total = Time{};
	while (try cores.next()) |core| {
		for (
			total.asArrayMut(),
			core.asArray(),
		) |*t, c| {
			t.* += c;
		}
		tolerance += 1;
	}
	
	for (
		cores.total.asArray(),
		total.asArray(),
	) |a, b| {
		try std.testing.expect(a + tolerance > b);
		try std.testing.expect(b + tolerance > a);
	}
}

