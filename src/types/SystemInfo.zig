const std = @import("std");

pub const CpuInfo = struct {
    name: []const u8,
    manufacturer: []const u8,
    model: []const u8,
    speed: []const u8,
    device_name: []const u8,
    usage: u32,
};

pub const RamInfo = struct {
    total_ram: f64,
    used_ram: f64,
    free_ram: f64,
};

pub const SystemInfo = struct {
    timestamp: u64,
    cpu: CpuInfo,
    ram: RamInfo,
    disk: DiskInfo,
    network: NetworkInfo,
    app: AppInfo,
};

pub const DiskInfo = struct {
    total_space: f64,
    used_space: f64,
    free_space: f64,
    disk_reads: u64,
    disk_writes: u64,
};

pub const NetworkInfo = struct {
    bytes_sent: f64,
    bytes_received: f64,
    packets_sent: u64,
    packets_received: u64,
    bandwidth_usage: f64,
    transfer_rate: f64,
    isInternet: u8,
};
pub const NetworkStats = struct {
    bytes_sent: f64,
    bytes_received: f64,
    packets_sent: u64,
    packets_received: u64,
    bandwidth_usage: f64,
    transfer_rate: f64,
    isInternet: u8,
};
pub const DiskStats = struct {
    total_space: f64,
    used_space: f64,
    free_space: f64,
    disk_reads: u64,
    disk_writes: u64,
};
pub const MemoryInfo = struct {
    total_ram: u64,
    used_ram: u64,
    free_ram: u64,
};
pub const AppInfo = struct {
    pid: u32,
    cpu_usage: f64,
    memory_usage: u64,
    disk_usage: u64,
};
