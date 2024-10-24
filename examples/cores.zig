const cpu_info = @import("cpu-info");
const std = @import("std");

const Core = cpu_info.Core;

pub fn main() !void {
	const allocator = std.heap.page_allocator;
	const stdout = std.io.getStdOut().writer();
	
	var iter = try Core.Iterator.new(allocator);
	defer iter.close();
	
	while (try iter.next()) |_core| {
		var core = _core;
		defer core.deinit();
		
		try stdout.print(
			"core {?}: {?s} ({?d:.2} MHz)\n",
			.{
				core.inner.@"processor",
				core.inner.@"model name",
				core.inner.@"cpu MHz"
			}
		);
	}
}

