const std = @import("std");

fn parseAny(
	comptime T: type,
	allocator: std.mem.Allocator,
	string: []const u8
) !T {
	const parseFloat = std.fmt.parseFloat;
	const parseInt = std.fmt.parseInt;
	const startsWith = std.mem.startsWith;
	const eql = std.mem.eql;
	
	return switch (T) {
		u8, u16 => try parseInt(T, string, 10),
		f32 => try parseFloat(f32, string),
		bool => if (eql(u8, string, "yes"))
			true
		else if (eql(u8, string, "no"))
			false
		else
			error.InvalidBool,
		*void => block: {
			if (!startsWith(u8, string, "0x")) {
				return error.PointerIsNotHex;
			}
			const value = try parseInt(
				usize,
				string[2 .. ],
				16
			);
			break :block @ptrFromInt(value);
		},
		[]u8 => try allocator.dupe(u8, string),
		std.ArrayList([]u8) => block: {
			var list = std.ArrayList([]u8)
				.init(allocator);
			errdefer list.deinit();
			errdefer for (list.items) |item| {
				allocator.free(item);
			};
			
			var iter = std.mem.splitScalar(
				u8,
				string,
				' '
			);
			while (iter.next()) |item| {
				try list.append(
					try allocator.dupe(u8, item)
				);
			}
			
			break :block list;
		},
		else => @compileError(
			"Invalid type " ++ @typeName(T)
		),
	};
}

fn deinitAny(
	item: anytype,
	allocator: std.mem.Allocator,
) void {
	const T = @TypeOf(item);
	switch (T) {
		u8, u16, f32, bool, *void => {},
		[]u8 => allocator.free(item),
		std.ArrayList([]u8) => block: {
			for (item.items) |i| {
				allocator.free(i);
			}
			item.deinit();
			break :block;
		},
		else => @compileError(
			"Invalid type " ++ @typeName(T)
		),
	}
}

pub const Core = struct {
	inner: Inner,
	allocator: std.mem.Allocator,
	
	pub const Inner = struct {
		@"processor": ?u8 = null,
		@"vendor_id": ?[]u8 = null,
		@"cpu family": ?u16 = null,
		@"model": ?u16 = null,
		@"model name": ?[]u8 = null,
		@"stepping": ?u8 = null,
		@"microcode": ?*void = null,
		@"cpu MHz": ?f32 = null,
		@"physical id": ?u8 = null,
		@"siblings": ?u8 = null,
		@"core id": ?u8 = null,
		@"cpu cores": ?u8 = null,
		@"apicid": ?u8 = null,
		@"initial apicid": ?u8 = null,
		@"fpu": ?bool = null,
		@"fpu_exception": ?bool = null,
		@"cpuid level": ?u8 = null,
		@"wp": ?bool = null,
		@"flags": ?std.ArrayList([]u8) = null,
		@"bugs": ?std.ArrayList([]u8) = null,
		@"bogomips": ?f32 = null,
		@"clflush size": ?u8 = null,
		@"cache_alignment": ?u8 = null,
		@"power management": ?std.ArrayList([]u8) = null,
	};
	
	pub const Iterator = struct {
		allocator: std.mem.Allocator,
		reader: std.io.BufferedReader(
			4096,
			std.fs.File.Reader
		),
		
		pub inline fn new(
			allocator: std.mem.Allocator
		) !@This() {
			var file = try std.fs.openFileAbsolute(
				"/proc/cpuinfo",
				.{}
			);
			const reader = std.io.bufferedReader(
				file.reader()
			);
			
			return .{
				.allocator = allocator,
				.reader = reader,
			};
		}
		
		pub inline fn close(this: *@This()) void {
			this.reader.unbuffered_reader.context.close();
		}
		
		pub fn next(this: *@This()) !?Core {
			var core = Core.Inner{};
			
			var reader = this.reader.reader();
			while (true) {
				var line = reader.readUntilDelimiterAlloc(
					this.allocator,
					'\n',
					4096
				) catch |err| {
					if (err == error.EndOfStream) {
						return null;
					}
					return err;
				};
				defer this.allocator.free(line);
				
				if (line.len == 0) {
					break;
				}
				const div = std.mem.indexOfScalar(
					u8,
					line,
					':'
				) orelse return error.NoColon;

				const key_end = std.mem.lastIndexOfNone(
					u8,
					line[0 .. div],
					" \t"
				) orelse return error.NoSpaces;
				
				const key = line[0 .. key_end + 1];
				const value = line[div + 2 .. ];
				
				inline for (
					std.meta.fields(Core.Inner)
				) |field| {
					if (std.mem.eql(
						u8,
						key,
						field.name
					)) {
						@field(
							core,
							field.name
						) = try parseAny(
							@TypeOf(@field(
								core,
								field.name
							).?),
							this.allocator,
							value
						);
						break;
					}
				}
			}
			
			return .{
				.inner = core,
				.allocator = this.allocator,
			};
		}
	};
	
	pub fn deinit(this: *@This()) void {
		inline for (
			std.meta.fields(Core.Inner)
		) |field| {
			if (@field(
				this.inner,
				field.name
			)) |item| {
				deinitAny(item, this.allocator);
			}
		}
	}
};

test "Core.Iterator" {
	const allocator = std.testing.allocator;
	
	var iter = try Core.Iterator.new(allocator);
	defer iter.close();
	
	while (try iter.next()) |_core| {
		var core = _core;
		defer core.deinit();
		
		std.debug.print(
			"core {?}: {?s} ({?d:.2} MHz)\n",
			.{
				core.inner.@"processor",
				core.inner.@"model name",
				core.inner.@"cpu MHz"
			}
		);
	}
}

