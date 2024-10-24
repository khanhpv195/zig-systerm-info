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
        .windows => {
            var memStatus = std.mem.zeroes(MEMORYSTATUSEX);
            memStatus.dwLength = @sizeOf(MEMORYSTATUSEX);

            if (GlobalMemoryStatusEx(&memStatus) == 0) {
                try writer.print("Failed to get memory information\n", .{});
                return;
            }

            const gb = 1024 * 1024 * 1024;
            try writer.print("Total Memory: {d:.1} GB\n", .{@as(f64, @floatFromInt(memStatus.ullTotalPhys)) / @as(f64, @floatFromInt(gb))});
            try writer.print("Available Memory: {d:.1} GB\n", .{@as(f64, @floatFromInt(memStatus.ullAvailPhys)) / @as(f64, @floatFromInt(gb))});
        },
        else => try writer.print("Unsupported operating system\n", .{}),
    }
}

fn getDiskInfo(writer: anytype) !void {
    switch (builtin.os.tag) {
        .windows => {
            const GetDiskFreeSpaceExA = windows.kernel32.GetDiskFreeSpaceExA;
            const lpDirectoryName = "C:\\\x00"; // Ổ đĩa C
            var lpFreeBytesAvailableToCaller: windows.ULARGE_INTEGER = undefined;
            var lpTotalNumberOfBytes: windows.ULARGE_INTEGER = undefined;
            var lpTotalNumberOfFreeBytes: windows.ULARGE_INTEGER = undefined;

            if (GetDiskFreeSpaceExA(lpDirectoryName.ptr, &lpFreeBytesAvailableToCaller, &lpTotalNumberOfBytes, &lpTotalNumberOfFreeBytes) == 0) {
                try writer.print("Failed to get disk information\n", .{});
                return;
            }

            const gb = 1024 * 1024 * 1024;
            try writer.print("Total Disk Space: {d:.1} GB\n", .{@as(f64, @floatFromInt(lpTotalNumberOfBytes.QuadPart)) / @as(f64, @floatFromInt(gb))});
            try writer.print("Free Disk Space: {d:.1} GB\n", .{@as(f64, @floatFromInt(lpTotalNumberOfFreeBytes.QuadPart)) / @as(f64, @floatFromInt(gb))});
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
