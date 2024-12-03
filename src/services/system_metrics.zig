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

const INTERNET_CONNECTION_ONLINE = 0x40;
const INTERNET_CONNECTION_MODEM = 0x1;
const INTERNET_CONNECTION_LAN = 0x2;
const INTERNET_CONNECTION_PROXY = 0x4;
const INTERNET_CONNECTION_MODEM_BUSY = 0x8;
extern "wininet" fn InternetGetConnectedState(
    lpdwFlags: *windows.DWORD,
    dwReserved: windows.DWORD,
) windows.BOOL;

const IP_HEADER_LENGTH = 20;
const ICMP_HEADER_LENGTH = 8;
const ICMP_ECHO_REQUEST = 8;
const ICMP_ECHO_REPLY = 0;

extern "iphlpapi" fn IcmpCreateFile() windows.HANDLE;
extern "iphlpapi" fn IcmpCloseHandle(IcmpHandle: windows.HANDLE) windows.BOOL;
extern "iphlpapi" fn IcmpSendEcho(
    IcmpHandle: windows.HANDLE,
    DestinationAddress: windows.ULONG,
    RequestData: [*]const u8,
    RequestSize: windows.WORD,
    RequestOptions: ?*anyopaque,
    ReplyBuffer: [*]u8,
    ReplySize: windows.DWORD,
    Timeout: windows.DWORD,
) windows.DWORD;






pub const SystemMetrics = struct {
    query: PDH_HQUERY,
    cpu_counter: PDH_HCOUNTER,
    memory_counter: PDH_HCOUNTER,
    disk_read_counter: PDH_HCOUNTER,
    disk_write_counter: PDH_HCOUNTER,
    network_send_counter: PDH_HCOUNTER,
    network_recv_counter: PDH_HCOUNTER,
    
    // Thêm các biến để tích lũy giá trị
    samples_count: usize,
    cpu_total: f64,
    memory_total: f64,
    disk_read_total: f64,
    disk_write_total: f64,
    network_send_total: f64,
    network_recv_total: f64,

    // Thêm counter cho RAM
    total_ram_counter: PDH_HCOUNTER,
    free_ram_counter: PDH_HCOUNTER,
    
    // Thêm counter cho Disk Space
    total_space_counter: PDH_HCOUNTER,
    free_space_counter: PDH_HCOUNTER,
    used_space_counter: PDH_HCOUNTER,

    // Thêm biến tích lũy
    total_ram_total: f64,
    free_ram_total: f64,
    total_space_total: f64,
    free_space_total: f64,
    used_space_total: f64,

    // Thêm counters cho Network
    packets_sent_counter: PDH_HCOUNTER,
    packets_recv_counter: PDH_HCOUNTER,
    bandwidth_counter: PDH_HCOUNTER,
    
    // Thêm biến tích lũy cho Network
    packets_sent_total: f64,
    packets_recv_total: f64,
    bandwidth_total: f64,

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
            .samples_count = 0,
            .cpu_total = 0,
            .memory_total = 0,
            .disk_read_total = 0,
            .disk_write_total = 0,
            .network_send_total = 0,
            .network_recv_total = 0,
            .total_ram_counter = undefined,
            .free_ram_counter = undefined,
            .total_space_counter = undefined,
            .free_space_counter = undefined,
            .used_space_counter = undefined,
            .total_ram_total = 0,
            .free_ram_total = 0,
            .total_space_total = 0,
            .free_space_total = 0,
            .used_space_total = 0,
            .packets_sent_counter = undefined,
            .packets_recv_counter = undefined,
            .bandwidth_counter = undefined,
            .packets_sent_total = 0,
            .packets_recv_total = 0,
            .bandwidth_total = 0,
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

        try self.addCounter("\\Memory\\Committed Bytes", &self.total_ram_counter);
        try self.addCounter("\\Memory\\Available Bytes", &self.free_ram_counter);
        
        try self.addCounter("\\LogicalDisk(_Total)\\Free Megabytes", &self.free_space_counter);
        try self.addCounter("\\LogicalDisk(_Total)\\% Free Space", &self.used_space_counter);

        try self.addCounter("\\Network Interface(*)\\Packets Sent/sec", &self.packets_sent_counter);
        try self.addCounter("\\Network Interface(*)\\Packets Received/sec", &self.packets_recv_counter);
        try self.addCounter("\\Network Interface(*)\\Current Bandwidth", &self.bandwidth_counter);

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
        fn checkInternetConnection() bool {
            var flags: windows.DWORD = 0;
            const result = InternetGetConnectedState(&flags, 0);
            std.debug.print("Debug - InternetCheck: raw result={}, flags={}\n", .{result, flags});
            return result != 0;
        }
    pub fn collectSample(self: *SystemMetrics) !void {
        if (PdhCollectQueryData(self.query) != 0) {
            return error.PdhCollectQueryDataFailed;
        }

        var value: PDH_FMT_COUNTERVALUE = undefined;
        
        // Thu thập CPU
        if (PdhGetFormattedCounterValue(self.cpu_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.cpu_total += value.doubleValue;
        }

        // Thu thập Memory
        if (PdhGetFormattedCounterValue(self.memory_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.memory_total += value.doubleValue;
        }

        // Thu thập Disk I/O
        if (PdhGetFormattedCounterValue(self.disk_read_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.disk_read_total += value.doubleValue;
        }
        if (PdhGetFormattedCounterValue(self.disk_write_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.disk_write_total += value.doubleValue;
        }

        // Thu thập Network I/O
        if (PdhGetFormattedCounterValue(self.network_send_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.network_send_total += value.doubleValue;
        }
        if (PdhGetFormattedCounterValue(self.network_recv_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.network_recv_total += value.doubleValue;
        }

        // Thu thập RAM details
        if (PdhGetFormattedCounterValue(self.total_ram_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.total_ram_total += value.doubleValue;
        }
        if (PdhGetFormattedCounterValue(self.free_ram_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.free_ram_total += value.doubleValue;
        }

        // Thu thập Disk Space details
        if (PdhGetFormattedCounterValue(self.free_space_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.free_space_total += value.doubleValue;
        }
        if (PdhGetFormattedCounterValue(self.used_space_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.used_space_total += value.doubleValue;
        }

        // Thu thập Network details
        if (PdhGetFormattedCounterValue(self.packets_sent_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.packets_sent_total += value.doubleValue;
        }
        if (PdhGetFormattedCounterValue(self.packets_recv_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.packets_recv_total += value.doubleValue;
        }
        if (PdhGetFormattedCounterValue(self.bandwidth_counter, PDH_FMT_DOUBLE, null, &value) == 0) {
            self.bandwidth_total += value.doubleValue;
        }

        self.samples_count += 1;
    }

    pub fn getAverages(self: *SystemMetrics) !SystemInfo {
        if (self.samples_count == 0) return error.NoSamples;

        var info = SystemInfo{
            .timestamp = @intCast(std.time.timestamp()),
            .cpu = undefined,
            .ram = undefined,
            .disk = undefined,
            .network = undefined,
            .app = undefined,
        };

        // Tính trung bình cho mỗi metric
        info.cpu.usage = @intFromFloat(self.cpu_total / @as(f64, @floatFromInt(self.samples_count)));
        info.ram.used_ram = self.memory_total / @as(f64, @floatFromInt(self.samples_count));
        info.disk.disk_reads = @intFromFloat(self.disk_read_total / @as(f64, @floatFromInt(self.samples_count)));
        info.disk.disk_writes = @intFromFloat(self.disk_write_total / @as(f64, @floatFromInt(self.samples_count)));
        info.network.bytes_sent = self.network_send_total / @as(f64, @floatFromInt(self.samples_count));
        info.network.bytes_received = self.network_recv_total / @as(f64, @floatFromInt(self.samples_count));

        // Tính trung bình cho RAM
        const avg_total_ram = self.total_ram_total / @as(f64, @floatFromInt(self.samples_count));
        const avg_free_ram = self.free_ram_total / @as(f64, @floatFromInt(self.samples_count));
        info.ram = .{
            .total_ram = avg_total_ram,
            .free_ram = avg_free_ram,
            .used_ram = avg_total_ram - avg_free_ram,
        };

        info.disk = .{
            .total_space = self.total_space_total / @as(f64, @floatFromInt(self.samples_count)),
            .free_space = self.free_space_total / @as(f64, @floatFromInt(self.samples_count)),
            .used_space = self.used_space_total / @as(f64, @floatFromInt(self.samples_count)),
            .disk_reads = @intFromFloat(self.disk_read_total / @as(f64, @floatFromInt(self.samples_count))),
            .disk_writes = @intFromFloat(self.disk_write_total / @as(f64, @floatFromInt(self.samples_count))),
        };

        const avg_bytes_sent = self.network_send_total / @as(f64, @floatFromInt(self.samples_count));
        const avg_bytes_received = self.network_recv_total / @as(f64, @floatFromInt(self.samples_count));
        
        const has_internet = checkInternetConnection();
        const has_network_activity = (self.network_send_total > 0 or 
                                    self.network_recv_total > 0 or 
                                    self.packets_sent_total > 0 or 
                                    self.packets_recv_total > 0 or
                                    self.bandwidth_total > 0);

        std.debug.print("Debug - Internet Check: has_internet={}, has_network_activity={}\n", .{has_internet, has_network_activity});
        std.debug.print("Debug - Network Details:\n", .{});
        std.debug.print("  bytes_sent={d}, bytes_received={d}\n", .{self.network_send_total, self.network_recv_total});
        std.debug.print("  packets_sent={d}, packets_received={d}\n", .{self.packets_sent_total, self.packets_recv_total});
        std.debug.print("  bandwidth={d}\n", .{self.bandwidth_total});

        var internet_value: u8 = 0;
        if (has_internet) {
            internet_value = 1;
        }
        std.debug.print("Debug - Final isInternet value: {}\n", .{internet_value});

        info.network = .{
            .bytes_sent = avg_bytes_sent,
            .bytes_received = avg_bytes_received,
            .packets_sent = @intFromFloat(self.packets_sent_total / @as(f64, @floatFromInt(self.samples_count))),
            .packets_received = @intFromFloat(self.packets_recv_total / @as(f64, @floatFromInt(self.samples_count))),
            .bandwidth_usage = self.bandwidth_total / @as(f64, @floatFromInt(self.samples_count)),
            .transfer_rate = (self.network_send_total + self.network_recv_total) / @as(f64, @floatFromInt(self.samples_count)),
            .isInternet = internet_value,
        };

        self.samples_count = 0;
        self.cpu_total = 0;
        self.memory_total = 0;
        self.disk_read_total = 0;
        self.disk_write_total = 0;
        self.network_send_total = 0;
        self.network_recv_total = 0;
        self.total_ram_total = 0;
        self.free_ram_total = 0;
        self.total_space_total = 0;
        self.free_space_total = 0;
        self.used_space_total = 0;
        self.packets_sent_total = 0;
        self.packets_recv_total = 0;
        self.bandwidth_total = 0;

        return info;
    }
};