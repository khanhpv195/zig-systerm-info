const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const SystemInfo = @import("../types/SystemInfo.zig").SystemInfo;

fn bytesToGB(bytes: f64) f64 {
    return @round(bytes / (1024 * 1024 * 1024) * 100) / 100;
}

fn roundFloat(value: f64) f64 {
    return @round(value * 100) / 100;
}

fn bytesToMB(bytes: f64) f64 {
    return @round(bytes / (1024 * 1024) * 100) / 100;
}

pub fn saveToDb(info: SystemInfo, device_name: []const u8) !void {
    var db: ?*c.sqlite3 = null;
    const rc = c.sqlite3_open("system_metrics.db", &db);
    if (rc != c.SQLITE_OK) {
        return error.SQLiteOpenError;
    }
    defer _ = c.sqlite3_close(db);

    // Create table SQL
    const create_table_sql =
        \\CREATE TABLE IF NOT EXISTS system_metrics (
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    device_name TEXT NOT NULL,
        \\    timestamp INTEGER NOT NULL,
        \\    cpu_usage REAL NOT NULL,
        \\    total_ram REAL NOT NULL,
        \\    used_ram REAL NOT NULL,
        \\    free_ram REAL NOT NULL,
        \\    total_space REAL NOT NULL,
        \\    used_space REAL NOT NULL,
        \\    free_space REAL NOT NULL,
        \\    disk_reads INTEGER NOT NULL,
        \\    disk_writes INTEGER NOT NULL,
        \\    bytes_sent REAL NOT NULL,
        \\    bytes_received REAL NOT NULL,
        \\    packets_sent INTEGER NOT NULL,
        \\    packets_received INTEGER NOT NULL,
        \\    bandwidth_usage REAL NOT NULL,
        \\    transfer_rate REAL NOT NULL
        \\);
    ;

    var err_msg: [*c]u8 = null;
    if (c.sqlite3_exec(db, create_table_sql, null, null, &err_msg) != c.SQLITE_OK) {
        if (err_msg) |msg| {
            c.sqlite3_free(msg);
        }
        return error.SQLiteExecError;
    }

    // Convert values
    const ram_total = bytesToGB(info.ram.total_ram);
    const ram_used = bytesToGB(info.ram.used_ram);
    const ram_free = bytesToGB(info.ram.free_ram);
    const net_sent = bytesToGB(info.network.bytes_sent);
    const net_received = bytesToGB(info.network.bytes_received);
    const transfer_rate = roundFloat(bytesToMB(info.network.bytes_sent + info.network.bytes_received));

    // Prepare insert statement
    const insert_sql =
        \\INSERT INTO system_metrics (
        \\    device_name, timestamp, cpu_usage, 
        \\    total_ram, used_ram, free_ram,
        \\    total_space, used_space, free_space, disk_reads, disk_writes,
        \\    bytes_sent, bytes_received, packets_sent, packets_received,
        \\    bandwidth_usage, transfer_rate
        \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ;

    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, insert_sql, -1, &stmt, null) != c.SQLITE_OK) {
        return error.SQLitePrepareError;
    }
    defer _ = c.sqlite3_finalize(stmt);

    // Bind values
    _ = c.sqlite3_bind_text(stmt, 1, device_name.ptr, @intCast(device_name.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_int64(stmt, 2, @intCast(info.timestamp));
    _ = c.sqlite3_bind_double(stmt, 3, @floatFromInt(info.cpu.usage));
    _ = c.sqlite3_bind_double(stmt, 4, ram_total);
    _ = c.sqlite3_bind_double(stmt, 5, ram_used);
    _ = c.sqlite3_bind_double(stmt, 6, ram_free);
    _ = c.sqlite3_bind_double(stmt, 7, info.disk.total_space);
    _ = c.sqlite3_bind_double(stmt, 8, info.disk.used_space);
    _ = c.sqlite3_bind_double(stmt, 9, info.disk.free_space);
    _ = c.sqlite3_bind_int64(stmt, 10, @intCast(info.disk.disk_reads));
    _ = c.sqlite3_bind_int64(stmt, 11, @intCast(info.disk.disk_writes));
    _ = c.sqlite3_bind_double(stmt, 12, net_sent);
    _ = c.sqlite3_bind_double(stmt, 13, net_received);
    _ = c.sqlite3_bind_int64(stmt, 14, @intCast(info.network.packets_sent));
    _ = c.sqlite3_bind_int64(stmt, 15, @intCast(info.network.packets_received));
    _ = c.sqlite3_bind_double(stmt, 16, roundFloat(info.network.bandwidth_usage));
    _ = c.sqlite3_bind_double(stmt, 17, transfer_rate);

    if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
        return error.SQLiteStepError;
    }
}
