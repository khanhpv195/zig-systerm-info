const cpu_info = @import("cpu-info");
const std = @import("std");

pub fn main() !void {
	const stdout = std.io.getStdOut().writer();
	
	var reader = cpu_info.Time.reader();
	for (0 .. 5) |_| {
		const usage = try reader.usage();
		try stdout.print("load: {d:.2}%\n", .{
			usage * 100.0
		});
		std.time.sleep(std.time.ns_per_s * 1);
	}
}

