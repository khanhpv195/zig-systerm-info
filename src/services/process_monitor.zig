const std = @import("std");
const windows = std.os.windows;
const api = @import("api.zig");

pub const ProcessStats = struct {
    pid: u32,
    cpu_usage: f64,
    memory_usage: u64,
    disk_usage: u64,
};

const interval = 5 * std.time.ns_per_s; // 5 seconds

const HQUERY = windows.HANDLE;
const HCOUNTER = windows.HANDLE;
const PDH_FMT_DOUBLE = 0x00000200;
const PDH_FMT_COUNTERVALUE = extern struct {
    CStatus: windows.LONG,
    doubleValue: f64,
};

// PDH function declarations
extern "pdh" fn PdhOpenQuery(DataSource: ?windows.LPCWSTR, UserData: windows.DWORD, Query: *HQUERY) windows.LONG;
extern "pdh" fn PdhAddCounterW(Query: HQUERY, CounterPath: windows.LPCWSTR, UserData: windows.DWORD, Counter: *HCOUNTER) windows.LONG;
extern "pdh" fn PdhCollectQueryData(Query: HQUERY) windows.LONG;
extern "pdh" fn PdhCloseQuery(Query: HQUERY) windows.LONG;
extern "pdh" fn PdhGetFormattedCounterValue(Counter: HCOUNTER, Format: windows.DWORD, Reserved: ?*windows.DWORD, Value: *PDH_FMT_COUNTERVALUE) windows.LONG;

pub fn getProcessStats(process_name: []const u8) !ProcessStats {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stats = ProcessStats{
        .pid = 0,
        .cpu_usage = 0,
        .memory_usage = 0,
        .disk_usage = 0,
    };

    var buffer: [4096]u8 = undefined;

    // Get PID and memory usage
    var process_cmd = std.ChildProcess.init(&[_][]const u8{
        "wmic",
        "process",
        "where",
        try std.fmt.allocPrint(allocator, "name='{s}'", .{std.fs.path.basename(process_name)}),
        "get",
        "ProcessId,WorkingSetSize",
        "/format:csv",
    }, allocator);

    process_cmd.stdout_behavior = .Pipe;
    try process_cmd.spawn();

    const size = try process_cmd.stdout.?.reader().readAll(&buffer);
    _ = try process_cmd.wait();

    var lines = std.mem.split(u8, buffer[0..size], "\n");
    _ = lines.next(); // Skip header
    _ = lines.next(); // Skip empty line

    while (lines.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \r\n");
        if (trimmed_line.len == 0) continue;

        var fields = std.mem.split(u8, trimmed_line, ",");
        _ = fields.next(); // Skip Node

        if (fields.next()) |pid_str| {
            const trimmed_pid = std.mem.trim(u8, pid_str, " \"\r\n");
            if (trimmed_pid.len > 0) {
                stats.pid = try std.fmt.parseInt(u32, trimmed_pid, 10);
            }
        }

        if (fields.next()) |mem_str| {
            const trimmed_mem = std.mem.trim(u8, mem_str, " \"\r\n");
            if (trimmed_mem.len > 0) {
                stats.memory_usage = try std.fmt.parseInt(u64, trimmed_mem, 10);
            }
        }

        if (stats.pid != 0) {
            var query: HQUERY = undefined;
            var counter: HCOUNTER = undefined;
            var counter_value: PDH_FMT_COUNTERVALUE = undefined;

            // Open a query
            if (PdhOpenQuery(null, 0, &query) != 0) {
                return error.PdhOpenQueryFailed;
            }
            defer _ = PdhCloseQuery(query);

            // Get process name without extension
            const process_base_name = std.fs.path.stem(process_name);

            // Build counter path with correct format
            const counter_path = try std.fmt.allocPrint(allocator, "\\Process({s})\\% Processor Time", .{process_base_name});
            defer allocator.free(counter_path);

            std.debug.print("Counter path: {s}\n", .{counter_path});

            const counter_path_wide = try api.stringToUtf16(allocator, counter_path);
            defer allocator.free(counter_path_wide);

            const add_result = PdhAddCounterW(query, counter_path_wide, 0, &counter);
            if (add_result != 0) {
                std.debug.print("PdhAddCounterW failed with error code: {d}\n", .{add_result});
                return error.PdhAddCounterFailed;
            }

            // Wait between measurements
            std.time.sleep(1000 * std.time.ns_per_ms); // Wait 1 second

            // First collection
            if (PdhCollectQueryData(query) != 0) {
                return error.PdhCollectQueryDataFailed;
            }

            // Increase time between measurements
            std.time.sleep(1000 * std.time.ns_per_ms); // Wait 1 second

            // Second collection
            if (PdhCollectQueryData(query) != 0) {
                return error.PdhCollectQueryDataFailed;
            }

            // Get the formatted value
            const format_result = PdhGetFormattedCounterValue(counter, PDH_FMT_DOUBLE, null, &counter_value);
            if (format_result != 0) {
                std.debug.print("PdhGetFormattedCounterValue failed with error code: {d}\n", .{format_result});
                return error.PdhGetFormattedCounterValueFailed;
            }

            stats.cpu_usage = counter_value.doubleValue;

            // Update counter path for disk I/O
            const io_counter_path = try std.fmt.allocPrint(allocator, "\\Process({s})\\IO Read Bytes/sec", .{process_base_name});
            defer allocator.free(io_counter_path);

            const io_counter_path_wide = try api.stringToUtf16(allocator, io_counter_path);
            defer allocator.free(io_counter_path_wide);

            var io_counter: HCOUNTER = undefined;
            if (PdhAddCounterW(query, io_counter_path_wide, 0, &io_counter) == 0) {
                var io_value: PDH_FMT_COUNTERVALUE = undefined;
                if (PdhGetFormattedCounterValue(io_counter, PDH_FMT_DOUBLE, null, &io_value) == 0) {
                    stats.disk_usage = @intFromFloat(io_value.doubleValue);
                }
            }
        }

        break;
    }

    return stats;
}

pub fn monitorProcess(process_path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    while (true) {
        const stats = try getProcessStats(process_path);

        // Print information to screen
        std.debug.print("PID: {d}\n", .{stats.pid});
        std.debug.print("CPU Usage: {d:.2}%\n", .{stats.cpu_usage});
        std.debug.print("Memory Usage: {d:.2} MB\n", .{@as(f64, @floatFromInt(stats.memory_usage)) / (1024 * 1024)});
        std.debug.print("Disk I/O: {d} bytes\n", .{stats.disk_usage});

        std.time.sleep(interval);
    }
}
