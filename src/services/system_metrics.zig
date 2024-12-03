const std = @import("std");
const windows = std.os.windows;
const SystemInfo = @import("../types/SystemInfo.zig").SystemInfo;

const PDH_HQUERY = windows.HANDLE;
const PDH_HCOUNTER = windows.HANDLE;

extern "pdh" fn PdhOpenQueryW(
    DataSource: ?windows.LPCWSTR,
    UserData: windows.DWORD,
    Query: *PDH_HQUERY,
) windows.LONG;

extern "pdh" fn PdhAddCounterW(
    Query: PDH_HQUERY,
    CounterPath: windows.LPCWSTR,
    UserData: windows.DWORD,
    Counter: *PDH_HCOUNTER,
) windows.LONG;

extern "pdh" fn PdhCollectQueryData(Query: PDH_HQUERY) windows.LONG;
extern "pdh" fn PdhGetFormattedCounterValue(
    Counter: PDH_HCOUNTER,
    Format: windows.DWORD,
    Type: ?*windows.DWORD,
    Value: *PDH_FMT_COUNTERVALUE,
) windows.LONG;

const PDH_FMT_DOUBLE = 0x00000200;
const PDH_FMT_COUNTERVALUE = extern struct {
    CStatus: windows.LONG,
    doubleValue: f64,
};

pub const SystemMetrics = struct {
    query: PDH_HQUERY,
    cpu_counter: PDH_HCOUNTER,
    memory_counter: PDH_HCOUNTER,
    disk_read_counter: PDH_HCOUNTER,
    disk_write_counter: PDH_HCOUNTER,
    network_send_counter: PDH_HCOUNTER,
    network_recv_counter: PDH_HCOUNTER,

    pub fn init() !SystemMetrics {
        var query: PDH_HQUERY = undefined;
        if (PdhOpenQueryW(null, 0, &query) != 0) {
            return error.PdhOpenQueryFailed;
        }

        var self = SystemMetrics{
            .query = query,
            .cpu_counter = undefined,
            .memory_counter = undefined,
            .disk_read_counter = undefined,
            .disk_write_counter = undefined,
            .network_send_counter = undefined,
            .network_recv_counter = undefined,
        };

        // CPU Usage
        try self.addCounter("\\Processor(_Total)\\% Processor Time", &self.cpu_counter);
        
        // Memory Usage
        try self.addCounter("\\Memory\\% Committed Bytes In Use", &self.memory_counter);
        
        // Disk I/O
        try self.addCounter("\\PhysicalDisk(_Total)\\Disk Reads/sec", &self.disk_read_counter);
        try self.addCounter("\\PhysicalDisk(_Total)\\Disk Writes/sec", &self.disk_write_counter);
        
        // Network I/O
        try self.addCounter("\\Network Interface(*)\\Bytes Sent/sec", &self.network_send_counter);
        try self.addCounter("\\Network Interface(*)\\Bytes Received/sec", &self.network_recv_counter);

        // First collection to establish baseline
        _ = PdhCollectQueryData(self.query);

        return self;
    }

    fn addCounter(self: *SystemMetrics, path: []const u8, counter: *PDH_HCOUNTER) !void {
        const wide_path = try std.unicode.utf8ToUtf16LeWithNull(std.heap.page_allocator, path);
        defer std.heap.page_allocator.free(wide_path);

        if (PdhAddCounterW(self.query, wide_path.ptr, 0, counter) != 0) {
            return error.PdhAddCounterFailed;
        }
    }

    pub fn collect(self: *SystemMetrics) !SystemInfo {
        if (PdhCollectQueryData(self.query) != 0) {
            return error.PdhCollectQueryDataFailed;
        }

        var info = SystemInfo{
            .timestamp = @intCast(std.time.timestamp()),
            .cpu = undefined,
            .ram = undefined,
            .disk = undefined,
            .network = undefined,
            .app = undefined,
        };

        // Get CPU usage
        var cpu_value: PDH_FMT_COUNTERVALUE = undefined;
        if (PdhGetFormattedCounterValue(self.cpu_counter, PDH_FMT_DOUBLE, null, &cpu_value) == 0) {
            info.cpu.usage = @intFromFloat(cpu_value.doubleValue);
        }

        // Get Memory usage
        var mem_value: PDH_FMT_COUNTERVALUE = undefined;
        if (PdhGetFormattedCounterValue(self.memory_counter, PDH_FMT_DOUBLE, null, &mem_value) == 0) {
            info.ram.used_ram = mem_value.doubleValue;
        }

        // Get Disk I/O
        var disk_read_value: PDH_FMT_COUNTERVALUE = undefined;
        var disk_write_value: PDH_FMT_COUNTERVALUE = undefined;
        if (PdhGetFormattedCounterValue(self.disk_read_counter, PDH_FMT_DOUBLE, null, &disk_read_value) == 0) {
            info.disk.disk_reads = @intFromFloat(disk_read_value.doubleValue);
        }
        if (PdhGetFormattedCounterValue(self.disk_write_counter, PDH_FMT_DOUBLE, null, &disk_write_value) == 0) {
            info.disk.disk_writes = @intFromFloat(disk_write_value.doubleValue);
        }

        // Get Network I/O
        var net_send_value: PDH_FMT_COUNTERVALUE = undefined;
        var net_recv_value: PDH_FMT_COUNTERVALUE = undefined;
        if (PdhGetFormattedCounterValue(self.network_send_counter, PDH_FMT_DOUBLE, null, &net_send_value) == 0) {
            info.network.bytes_sent = net_send_value.doubleValue;
        }
        if (PdhGetFormattedCounterValue(self.network_recv_counter, PDH_FMT_DOUBLE, null, &net_recv_value) == 0) {
            info.network.bytes_received = net_recv_value.doubleValue;
        }

        return info;
    }
};