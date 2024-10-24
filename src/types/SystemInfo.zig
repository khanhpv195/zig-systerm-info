const std = @import("std");

pub const SystemInfo = struct {
    timestamp: u64,
    cpu: []const u8,
    total_ram: u64,
    used_ram: u64,
    free_ram: u64,
};
