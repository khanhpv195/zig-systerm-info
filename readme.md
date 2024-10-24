# cpu-info-zig

Library for fetching CPU information such as
current load and logical processors' data.

## Usage

Check out the [examples/](./examples) directory

## Adding it to your project

1. Add the dependency in `build.zig.zon`

	```diff
	.{
		.name = "my-project",
		.version = "0.0.0",
		.paths = .{ "" },
		.dependencies = .{
	+		.@"cpu-info" = .{
	+			.url = "<URL>",
	+		},
		},
	}
	```
	
	You get the `<URL>` like this:
	
	1. Go to a commit in this repository
	2. Click on `Browser Source`
	3. Click on `...` (More operations)
	4. Right click `Download TAR.GZ` and `Copy link`

2. Add module to your `exe` in `build.zig`

	```diff
	const std = @import("std");
	
	pub fn build(b: *std.Build) void {
		const target = b.standardTargetOptions(.{});
		const optimize = b.standardOptimizeOption(.{});
		
		const exe = b.addExecutable(.{
			.name = "my-project",
			.root_source_file = b.path("src/main.zig"),
			.target = target,
			.optimize = optimize,
		});
		
	+	// exe dependencies
	+	for ([_][]const u8{
	+		"cpu-info",
	+	}) |name| {
	+		const module = b.dependency(name, .{
	+			.target = target,
	+			.optimize = optimize,
	+		}).module(name);
	+		
	+		exe.root_module.addImport(name, module);
	+	}
		
		b.installArtifact(exe);
	}
	```

3. Add Hash

	1. Run `zig build`
	
		```sh
		zig build
		```
	
		```make
		Fetch Packages ... /path/to/my-project/build.zig.zon:15:11: error: dependency is missing hash field
			.url = "https://codeberg.org/xvzls/cpu-info-zig/archive/<COMMIT>.tar.gz",
			       ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
		note: expected .hash = "<HASH>",
		```
	
	2. Copy the `<HASH>` into your `build.zig.zon`
	
		```diff
		.{
			.name = "my-project",
			.version = "0.0.0",
			.paths = .{ "" },
			.dependencies = .{
				.@"cpu-info" = .{
					.url = "<URL>",
		+			.hash = "<HASH>",
				},
			},
		}
		```
	
4. Finally

	Run `zig build` again and it should all work now

## Contributing

Bug reports, suggestions and pull requests are
welcome. Feel free to open an issue for any feature
you may want incorporated into this library.

