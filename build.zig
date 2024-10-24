const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "system-info",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link with libc to use functions from the operating system API
    exe.linkLibC();

    // exe dependencies
    for ([_][]const u8{
        "cpu-info",
    }) |name| {
        const module = b.dependency(name, .{
            .target = target,
            .optimize = optimize,
        }).module(name);

        exe.root_module.addImport(name, module);
    }

    b.installArtifact(exe);

    // Library
    const lib = b.addStaticLibrary(.{
        .name = "cpu-info",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const mod = b.addModule("cpu-info", .{
        .root_source_file = b.path("src/root.zig"),
    });

    // Examples
    const examples_step = b.step("examples", "Run examples");

    for ([_][]const u8{
        "cores",
        "load",
    }) |name| {
        const example = b.addExecutable(.{
            .name = name,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
        });

        example.root_module.addImport(lib.name, mod);

        const run = b.addRunArtifact(example);
        examples_step.dependOn(&run.step);
    }

    // Benchmarks
    const bench = b.addExecutable(.{
        .name = "benchmark",
        .root_source_file = b.path("bench/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = true,
        .single_threaded = true,
    });

    bench.root_module.addImport(lib.name, &lib.root_module);

    for ([_][]const u8{"zbench"}) |name| {
        const module = b.dependency(name, .{
            .target = target,
            .optimize = optimize,
        }).module(name);

        bench.root_module.addImport(name, module);
    }

    const bench_cmd = b.addRunArtifact(bench);
    bench_cmd.step.dependOn(b.getInstallStep());
    b.step("bench", "Run benchmarks").dependOn(&bench_cmd.step);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run unit tests").dependOn(&run_tests.step);
}
