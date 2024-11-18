const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const SystemInfo = @import("../types/SystemInfo.zig").SystemInfo;
const device_id = @import("device_id.zig");

fn bytesToGB(bytes: f64) f64 {
    return @round(bytes / (1024 * 1024 * 1024) * 100) / 100;
}

fn roundFloat(value: f64) f64 {
    return @round(value * 100) / 100;
}

fn bytesToMB(bytes: f64) f64 {
    return @round(bytes / (1024 * 1024) * 100) / 100;
}

var datetime_buffer: [20]u8 = undefined; // Buffer toàn cục

pub fn getCurrentDateTime() []const u8 {
    const timestamp = std.time.timestamp() + (9 * std.time.s_per_hour);
    const epoch = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(@max(0, timestamp))) };
    const day = epoch.getEpochDay();
    const year_day = day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();

    const hours = @divFloor(day_seconds.secs, 3600);
    const minutes = @divFloor(@mod(day_seconds.secs, 3600), 60);
    const seconds = @mod(day_seconds.secs, 60);

    // Format: YYYY-MM-DD HH:MM:SS
    _ = std.fmt.bufPrint(&datetime_buffer, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        hours,
        minutes,
        seconds,
    }) catch return "2024-03-19 15:30:00"; // Fallback nếu có lỗi

    return datetime_buffer[0..19]; // Trả về chính xác 19 ký tự
}

pub fn saveToDb(info: SystemInfo, device_name: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Lấy device ID
    const uuid = try device_id.getOrCreateDeviceId(allocator);
    defer allocator.free(uuid);

    var db: ?*c.sqlite3 = null;

    // Tạo thư mục data nếu chưa tồn tại
    try std.fs.cwd().makePath("data");

    // Tạo tên file database với đường dẫn đầy đủ
    var db_filename_buffer: [256]u8 = undefined;
    const db_filename = try std.fmt.bufPrint(&db_filename_buffer, "data/{s}_metrics.db", .{device_name});

    std.debug.print("Attempting to create or open database at: {s}\n", .{db_filename});

    // Thêm kiểm tra null termination cho C string
    var null_terminated_filename_buffer: [257]u8 = undefined;
    const null_terminated_filename = try std.fmt.bufPrint(&null_terminated_filename_buffer, "{s}\x00", .{db_filename});

    const rc = c.sqlite3_open(null_terminated_filename.ptr, &db);
    if (rc != c.SQLITE_OK) {
        const err = c.sqlite3_errmsg(db);
        std.debug.print("SQLite open error: {s}\n", .{err});
        if (db) |db_ptr| {
            _ = c.sqlite3_close(db_ptr);
        }
        return error.SQLiteOpenError;
    }

    if (db == null) {
        std.debug.print("Database pointer is null after open\n", .{});
        return error.SQLiteNullDatabase;
    }

    std.debug.print("Database opened successfully\n", .{});
    defer {
        const close_rc = c.sqlite3_close(db);
        if (close_rc != c.SQLITE_OK) {
            std.debug.print("Error closing database: {d}\n", .{close_rc});
        }
    }

    // Create table SQL
    const create_table_sql =
        \\CREATE TABLE IF NOT EXISTS system_metrics (
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    device_id TEXT NOT NULL,
        \\    device_name TEXT NOT NULL,
        \\    timestamp INTEGER NOT NULL,
        \\    created_at TEXT NOT NULL,
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
    const created_at = getCurrentDateTime();
    const time_str = created_at[0..created_at.len];

    const insert_sql =
        \\INSERT INTO system_metrics (
        \\    device_id, device_name, timestamp, created_at, cpu_usage, 
        \\    total_ram, used_ram, free_ram,
        \\    total_space, used_space, free_space, disk_reads, disk_writes,
        \\    bytes_sent, bytes_received, packets_sent, packets_received,
        \\    bandwidth_usage, transfer_rate
        \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ;

    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, insert_sql, -1, &stmt, null) != c.SQLITE_OK) {
        return error.SQLitePrepareError;
    }
    defer _ = c.sqlite3_finalize(stmt);

    // Bind values
    _ = c.sqlite3_bind_text(stmt, 1, uuid.ptr, @intCast(uuid.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_text(stmt, 2, device_name.ptr, @intCast(device_name.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_int64(stmt, 3, @intCast(info.timestamp));
    _ = c.sqlite3_bind_text(stmt, 4, time_str.ptr, @intCast(time_str.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_double(stmt, 5, @floatFromInt(info.cpu.usage));
    _ = c.sqlite3_bind_double(stmt, 6, ram_total);
    _ = c.sqlite3_bind_double(stmt, 7, ram_used);
    _ = c.sqlite3_bind_double(stmt, 8, ram_free);
    _ = c.sqlite3_bind_double(stmt, 9, info.disk.total_space);
    _ = c.sqlite3_bind_double(stmt, 10, info.disk.used_space);
    _ = c.sqlite3_bind_double(stmt, 11, info.disk.free_space);
    _ = c.sqlite3_bind_int64(stmt, 12, @intCast(info.disk.disk_reads));
    _ = c.sqlite3_bind_int64(stmt, 13, @intCast(info.disk.disk_writes));
    _ = c.sqlite3_bind_double(stmt, 14, net_sent);
    _ = c.sqlite3_bind_double(stmt, 15, net_received);
    _ = c.sqlite3_bind_int64(stmt, 16, @intCast(info.network.packets_sent));
    _ = c.sqlite3_bind_int64(stmt, 17, @intCast(info.network.packets_received));
    _ = c.sqlite3_bind_double(stmt, 18, roundFloat(info.network.bandwidth_usage));
    _ = c.sqlite3_bind_double(stmt, 19, transfer_rate);

    if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
        const err = c.sqlite3_errmsg(db);
        std.debug.print("SQLite error: {s}\n", .{err});
        return error.SQLiteStepError;
    }
}
