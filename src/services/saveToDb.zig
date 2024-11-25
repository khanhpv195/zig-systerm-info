const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const SystemInfo = @import("../types/SystemInfo.zig").SystemInfo;
const device_id = @import("device_id.zig");
const process_monitor = @import("process_monitor.zig");

const exe_path = @import("std").fs.selfExePathAlloc;

fn bytesToGB(bytes: u64) f64 {
    return @round(@as(f64, @floatFromInt(bytes)) / (1024 * 1024 * 1024) * 100) / 100;
}

fn bytesToGBFromF64(bytes: f64) f64 {
    return @round(bytes / (1024 * 1024 * 1024) * 100) / 100;
}

fn roundFloat(value: f64) f64 {
    return @round(value * 100) / 100;
}

fn bytesToMB(bytes: f64) f64 {
    return @round(bytes / (1024 * 1024) * 100) / 100;
}

var datetime_buffer: [20]u8 = undefined;

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

    _ = std.fmt.bufPrint(&datetime_buffer, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        hours,
        minutes,
        seconds,
    }) catch return "2024-03-19 15:30:00";

    return datetime_buffer[0..19];
}

pub fn saveToDb(info: SystemInfo, device_name: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const exe_dir_path = try exe_path(allocator);
    defer allocator.free(exe_dir_path);
    const exe_dir = std.fs.path.dirname(exe_dir_path) orelse return error.NoPath;
    const data_dir = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "data" });
    defer allocator.free(data_dir);

    std.fs.makeDirAbsolute(data_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    const uuid = try device_id.getOrCreateDeviceId(allocator);
    defer allocator.free(uuid);

    var safe_device_name = try std.ArrayList(u8).initCapacity(allocator, device_name.len);
    defer safe_device_name.deinit();

    for (device_name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '_' or char == '-') {
            try safe_device_name.append(char);
        } else {
            try safe_device_name.append('_');
        }
    }

    const db_path = try std.fmt.allocPrint(allocator, "{s}/{s}_metrics.db\x00", .{ data_dir, safe_device_name.items });
    defer allocator.free(db_path);

    var db: ?*c.sqlite3 = null;
    const rc = c.sqlite3_open_v2(
        db_path.ptr,
        &db,
        c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_READWRITE,
        null,
    );

    if (rc != c.SQLITE_OK) {
        std.debug.print("Cannot open database: {s}\n", .{c.sqlite3_errmsg(db)});
        return error.DatabaseOpenFailed;
    }
    defer _ = c.sqlite3_close(db);

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
        \\    transfer_rate REAL NOT NULL,
        \\    app_cpu REAL,
        \\    app_ram REAL,
        \\    app_disk INTEGER,
        \\    isInternet BOOLEAN NOT NULL
        \\);
    ;

    var err_msg: [*c]u8 = null;
    if (c.sqlite3_exec(db, create_table_sql, null, null, &err_msg) != c.SQLITE_OK) {
        if (err_msg) |msg| {
            c.sqlite3_free(msg);
        }
        return error.SQLiteExecError;
    }

    const ram_total = bytesToGBFromF64(info.ram.total_ram);
    const ram_used = bytesToGBFromF64(info.ram.used_ram);
    const ram_free = bytesToGBFromF64(info.ram.free_ram);
    const net_sent = bytesToGBFloat(info.network.bytes_sent);
    const net_received = bytesToGBFloat(info.network.bytes_received);
    const transfer_rate = roundFloat(bytesToMB(info.network.bytes_sent + info.network.bytes_received));

    const time_str = getCurrentDateTime();

    const insert_sql =
        \\INSERT INTO system_metrics (
        \\    device_id, device_name, timestamp, created_at, cpu_usage,
        \\    total_ram, used_ram, free_ram,
        \\    total_space, used_space, free_space, disk_reads, disk_writes,
        \\    bytes_sent, bytes_received, packets_sent, packets_received,
        \\    bandwidth_usage, transfer_rate, app_cpu, app_ram, app_disk, isInternet
        \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ;

    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, insert_sql, -1, &stmt, null) != c.SQLITE_OK) {
        const err = c.sqlite3_errmsg(db);
        std.debug.print("SQLite prepare error: {s}\n", .{err});
        return error.SQLitePrepareError;
    }
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_text(stmt, 1, uuid.ptr, @intCast(uuid.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_text(stmt, 2, safe_device_name.items.ptr, @intCast(safe_device_name.items.len), c.SQLITE_STATIC);
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
    _ = c.sqlite3_bind_double(stmt, 20, info.app.cpu_usage);
    _ = c.sqlite3_bind_double(stmt, 21, bytesToGBFromF64(@floatFromInt(info.app.memory_usage)));
    _ = c.sqlite3_bind_int64(stmt, 22, @intCast(info.app.disk_usage));
    _ = c.sqlite3_bind_int(stmt, 23, if (info.network.bytes_received > 0 or info.network.bytes_sent > 0) 1 else 0);

    if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
        const err = c.sqlite3_errmsg(db);
        std.debug.print("SQLite error: {s}\n", .{err});
        if (err != null) {
            std.debug.print("Error details: {s}\n", .{err});
        }
        return error.SQLiteStepError;
    }
}

fn bytesToGBFloat(bytes: f64) f64 {
    return @round(bytes / (1024 * 1024 * 1024) * 100) / 100;
}
