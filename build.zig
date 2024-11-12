const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite_source = .{
        "deps/sqlite/sqlite3.c",
    };

    const exe = b.addExecutable(.{
        .name = "system-info",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addCSourceFiles(.{
        .files = &sqlite_source,
        .flags = &.{"-std=c99"},
    });

    exe.addIncludePath(.{ .path = "deps/sqlite" });

    exe.linkSystemLibrary("kernel32");
    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("advapi32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("winhttp");
    exe.linkLibC();

    exe.subsystem = .Windows;
    exe.want_lto = false;
    exe.rdynamic = true;
    exe.linker_allow_shlib_undefined = true;
    exe.link_function_sections = true;

    b.installArtifact(exe);
}
