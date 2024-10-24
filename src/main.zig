const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;

// Windows-specific imports
const windows = std.os.windows;
const SYSTEM_INFO = windows.SYSTEM_INFO;
const GetSystemInfo = windows.kernel32.GetSystemInfo;
const HKEY = windows.HKEY;
const HKEY_LOCAL_MACHINE = windows.HKEY_LOCAL_MACHINE;
const RegOpenKeyExA = windows.advapi32.RegOpenKeyExA;
const RegQueryValueExA = windows.advapi32.RegQueryValueExA;
const RegCloseKey = windows.advapi32.RegCloseKey;
const KEY_READ = windows.KEY_READ;
const ERROR_SUCCESS = windows.ERROR_SUCCESS;
const MEMORYSTATUSEX = windows.MEMORYSTATUSEX;
const GlobalMemoryStatusEx = windows.kernel32.GlobalMemoryStatusEx;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Print System Info Header
    try stdout.print("\n=== System Information ===\n\n", .{});

    // CPU Info
    try stdout.print("--- CPU Information ---\n", .{});
    switch (builtin.os.tag) {
        .linux => try getProcCpuInfo(stdout),
        .macos => try getMacOsCpuInfo(stdout),
        .windows => try getWindowsCpuInfo(stdout),
        else => try stdout.print("Unsupported operating system\n", .{}),
    }

    // Memory Info
    try stdout.print("\n--- Memory Information ---\n", .{});
    try getMemoryInfo(stdout);

    // Disk Info
    try stdout.print("\n--- Disk Information ---\n", .{});
    try getDiskInfo(stdout);

    // Network Info
    try stdout.print("\n--- Network Information ---\n", .{});
    try getNetworkInfo(stdout);
}

fn getProcCpuInfo(writer: anytype) !void {
    const file = try std.fs.openFileAbsolute("/proc/cpuinfo", .{ .mode = .read_only });
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();
    var buf: [1024]u8 = undefined;

    var printed_model = false;
    var printed_cores = false;
    var printed_freq = false;

    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (!printed_model and mem.indexOf(u8, line, "model name") != null) {
            try writer.print("{s}\n", .{line});
            printed_model = true;
        } else if (!printed_cores and mem.indexOf(u8, line, "cpu cores") != null) {
            try writer.print("{s}\n", .{line});
            printed_cores = true;
        } else if (!printed_freq and mem.indexOf(u8, line, "cpu MHz") != null) {
            try writer.print("{s}\n", .{line});
            printed_freq = true;
        }

        if (printed_model and printed_cores and printed_freq) break;
    }
}

fn getMacOsCpuInfo(writer: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get CPU Brand
    {
        var child = std.ChildProcess.init(&[_][]const u8{ "sysctl", "-n", "machdep.cpu.brand_string" }, allocator);
        child.stdout_behavior = .Pipe;
        try child.spawn();

        var buffer: [1024]u8 = undefined;
        const stdout = child.stdout.?.reader();
        const size = try stdout.readAll(&buffer);
        _ = try child.wait();

        try writer.print("CPU Brand: {s}", .{buffer[0..size]});
    }

    // Get CPU Core Count
    {
        var child = std.ChildProcess.init(&[_][]const u8{ "sysctl", "-n", "hw.ncpu" }, allocator);
        child.stdout_behavior = .Pipe;
        try child.spawn();

        var buffer: [1024]u8 = undefined;
        const stdout = child.stdout.?.reader();
        const size = try stdout.readAll(&buffer);
        _ = try child.wait();

        try writer.print("CPU Cores: {s}", .{buffer[0..size]});
    }
}

fn getWindowsCpuInfo(writer: anytype) !void {
    var sys_info: SYSTEM_INFO = undefined;
    GetSystemInfo(&sys_info);

    try writer.print("Number of Processors: {}\n", .{sys_info.dwNumberOfProcessors});

    var hKey: HKEY = undefined;
    const subKey = "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0\x00";
    const valueName = "ProcessorNameString\x00";

    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, subKey.ptr, 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
        defer _ = RegCloseKey(hKey);

        var buffer: [1024]u8 = undefined;
        var bufferSize: windows.DWORD = buffer.len;
        var valueType: windows.DWORD = undefined;

        if (RegQueryValueExA(hKey, valueName.ptr, null, &valueType, &buffer, &bufferSize) == ERROR_SUCCESS) {
            var len: usize = 0;
            while (len < bufferSize and buffer[len] != 0) : (len += 1) {}
            try writer.print("Processor: {s}\n", .{buffer[0..len]});
        }
    }
}

fn getMemoryInfo(writer: anytype) !void {
    switch (builtin.os.tag) {
        .macos => {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            // Get total memory
            var child = std.ChildProcess.init(&[_][]const u8{ "sysctl", "-n", "hw.memsize" }, allocator);
            child.stdout_behavior = .Pipe;
            try child.spawn();

            var buffer: [1024]u8 = undefined;
            const stdout = child.stdout.?.reader();
            const size = try stdout.readAll(&buffer);
            _ = try child.wait();

            const total_memory = if (size > 0) blk: {
                break :blk std.fmt.parseInt(u64, mem.trim(u8, buffer[0..size], &std.ascii.whitespace), 10) catch 0;
            } else 0;

            // Get VM stats for available memory
            var vm_child = std.ChildProcess.init(&[_][]const u8{"vm_stat"}, allocator);
            vm_child.stdout_behavior = .Pipe;
            try vm_child.spawn();

            var vm_buffer: [4096]u8 = undefined;
            const vm_stdout = vm_child.stdout.?.reader();
            const vm_size = try vm_stdout.readAll(&vm_buffer);
            _ = try vm_child.wait();

            const page_size: u64 = 4096; // Default page size for macOS
            var free_pages: u64 = 0;
            var inactive_pages: u64 = 0;

            var lines = std.mem.split(u8, vm_buffer[0..vm_size], "\n");
            while (lines.next()) |line| {
                if (mem.indexOf(u8, line, "Pages free:")) |_| {
                    var parts = mem.split(u8, line, ":");
                    _ = parts.next();
                    if (parts.next()) |value| {
                        free_pages = std.fmt.parseInt(u64, mem.trim(u8, value, &std.ascii.whitespace), 10) catch 0;
                    }
                } else if (mem.indexOf(u8, line, "Pages inactive:")) |_| {
                    var parts = mem.split(u8, line, ":");
                    _ = parts.next();
                    if (parts.next()) |value| {
                        inactive_pages = std.fmt.parseInt(u64, mem.trim(u8, value, &std.ascii.whitespace), 10) catch 0;
                    }
                }
            }

            const available_memory = (free_pages + inactive_pages) * page_size;
            const gb = 1024 * 1024 * 1024;

            try writer.print("Total Memory: {d:.1} GB\n", .{@as(f64, @floatFromInt(total_memory)) / @as(f64, @floatFromInt(gb))});
            try writer.print("Available Memory: {d:.1} GB\n", .{@as(f64, @floatFromInt(available_memory)) / @as(f64, @floatFromInt(gb))});

            if (total_memory > 0) {
                const used_memory = total_memory - available_memory;
                const usage_percent = @as(f64, @floatFromInt(used_memory)) / @as(f64, @floatFromInt(total_memory)) * 100;
                try writer.print("Memory Usage: {d:.1}%\n", .{usage_percent});
            }
        },
        else => try writer.print("Unsupported operating system\n", .{}),
    }
}

fn getDiskInfo(writer: anytype) !void {
    switch (builtin.os.tag) {
        .macos => {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            // Get disk information using df command
            var child = std.ChildProcess.init(&[_][]const u8{ "df", "-h", "/" }, allocator);
            child.stdout_behavior = .Pipe;
            try child.spawn();

            var buffer: [4096]u8 = undefined;
            const stdout = child.stdout.?.reader();
            const size = try stdout.readAll(&buffer);
            _ = try child.wait();

            var lines = std.mem.split(u8, buffer[0..size], "\n");
            _ = lines.next(); // Skip header

            if (lines.next()) |line| {
                var tokens = std.mem.tokenizeAny(u8, line, " ");

                // Skip filesystem name
                _ = tokens.next();

                // Get size, used, and available space
                if (tokens.next()) |total| {
                    try writer.print("Total Disk Space: {s}\n", .{total});
                }
                if (tokens.next()) |used| {
                    try writer.print("Used Disk Space: {s}\n", .{used});
                }
                if (tokens.next()) |avail| {
                    try writer.print("Available Disk Space: {s}\n", .{avail});
                }
                if (tokens.next()) |capacity| {
                    try writer.print("Disk Usage: {s}\n", .{capacity});
                }
            }
        },
        .windows => {
            // ... [existing Windows code remains the same] ...
        },
        else => try writer.print("Unsupported operating system\n", .{}),
    }
}

fn getNetworkInfo(writer: anytype) !void {
    switch (builtin.os.tag) {
        .linux => {
            const file = try std.fs.openFileAbsolute("/proc/net/dev", .{ .mode = .read_only });
            defer file.close();

            var buf_reader = std.io.bufferedReader(file.reader());
            var in_stream = buf_reader.reader();
            var buf: [1024]u8 = undefined;

            try writer.print("Network Interfaces:\n", .{});

            // Skip header lines
            _ = try in_stream.readUntilDelimiterOrEof(&buf, '\n');
            _ = try in_stream.readUntilDelimiterOrEof(&buf, '\n');

            // Read interfaces
            while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
                if (mem.indexOf(u8, line, ":")) |colon_pos| {
                    const interface = mem.trim(u8, line[0..colon_pos], " ");
                    if (!mem.eql(u8, interface, "lo")) { // Skip loopback
                        try writer.print("- {s}\n", .{interface});
                    }
                }
            }
        },
        .macos => {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            var child = std.ChildProcess.init(&[_][]const u8{ "networksetup", "-listallhardwareports" }, allocator);
            child.stdout_behavior = .Pipe;
            try child.spawn();

            var buffer: [4096]u8 = undefined;
            const stdout = child.stdout.?.reader();
            const size = try stdout.readAll(&buffer);
            _ = try child.wait();

            try writer.print("{s}\n", .{buffer[0..size]});
        },
        .windows => {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            // Simplified ipconfig output
            var child = std.ChildProcess.init(&[_][]const u8{ "ipconfig", "/brief" }, allocator);
            child.stdout_behavior = .Pipe;
            try child.spawn();

            var buffer: [4096]u8 = undefined;
            const stdout = child.stdout.?.reader();
            const size = try stdout.readAll(&buffer);
            _ = try child.wait();

            try writer.print("{s}\n", .{buffer[0..size]});
        },
        else => try writer.print("Unsupported operating system\n", .{}),
    }
}
