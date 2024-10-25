const std = @import("std");

pub const CpuInfo = struct {
    name: []const u8,
    manufacturer: []const u8,
    model: []const u8,
    speed: []const u8,
    device_name: []const u8,
};

pub const RamInfo = struct {
    total_ram: u64,
    used_ram: u64,
    free_ram: u64,
};

pub const SystemInfo = struct {
    timestamp: u64,
    cpu: CpuInfo,
    ram: RamInfo,
    disk: DiskInfo,
    network: NetworkInfo,
};

pub const DiskInfo = struct {
    total_space: u64,
    used_space: u64,
    free_space: u64,
    disk_reads: u64,
    disk_writes: u64,
};

pub const NetworkInfo = struct {
    bytes_sent: u64,
    bytes_received: u64,
    packets_sent: u64,
    packets_received: u64,
};
