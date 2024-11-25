const std = @import("std");
const crypto = std.crypto;

// Đường dẫn file lưu UUID
const UUID_FILE_PATH = "device/device_uuid";

// Thêm vào đầu file
const exe_path = @import("std").fs.selfExePathAlloc;

pub fn getOrCreateDeviceId(allocator: std.mem.Allocator) ![]const u8 {
    // Thử đọc UUID từ file trước
    if (readUuidFromFile(allocator)) |uuid| {
        return uuid;
    } else |_| {
        // Nếu không có file hoặc lỗi, tạo UUID mới
        const new_uuid = try generateUuid();
        try saveUuidToFile(new_uuid);
        return try allocator.dupe(u8, &new_uuid);
    }
}

fn generateUuid() ![36]u8 {
    var uuid: [16]u8 = undefined;
    crypto.random.bytes(&uuid);

    const uuid_str: [36]u8 = blk: {
        var buffer: [36]u8 = undefined;
        _ = try std.fmt.bufPrint(&buffer, "{}-{}-{}-{}-{}", .{
            std.fmt.fmtSliceHexLower(uuid[0..4]),
            std.fmt.fmtSliceHexLower(uuid[4..6]),
            std.fmt.fmtSliceHexLower(uuid[6..8]),
            std.fmt.fmtSliceHexLower(uuid[8..10]),
            std.fmt.fmtSliceHexLower(uuid[10..16]),
        });
        break :blk buffer;
    };

    return uuid_str;
}

fn readUuidFromFile(allocator: std.mem.Allocator) ![]const u8 {
    const exe_dir_path = try exe_path(allocator);
    defer allocator.free(exe_dir_path);
    const exe_dir = std.fs.path.dirname(exe_dir_path) orelse return error.NoPath;
    const data_dir = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "device" });
    defer allocator.free(data_dir);

    // Tạo thư mục data nếu chưa tồn tại
    std.fs.makeDirAbsolute(data_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    const uuid_path = try std.fs.path.join(allocator, &[_][]const u8{ data_dir, "device_uuid" });
    defer allocator.free(uuid_path);

    const file = try std.fs.openFileAbsolute(uuid_path, .{});
    defer file.close();

    const uuid = try file.readToEndAlloc(allocator, 36);
    if (uuid.len != 36) return error.InvalidUuidLength;

    return uuid;
}

fn saveUuidToFile(uuid: [36]u8) !void {
    const allocator = std.heap.page_allocator;
    const exe_dir_path = try exe_path(allocator);
    defer allocator.free(exe_dir_path);
    const exe_dir = std.fs.path.dirname(exe_dir_path) orelse return error.NoPath;
    const data_dir = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "device" });
    defer allocator.free(data_dir);

    // Tạo thư mục data nếu chưa tồn tại
    std.fs.makeDirAbsolute(data_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    const uuid_path = try std.fs.path.join(allocator, &[_][]const u8{ data_dir, "device_uuid" });
    defer allocator.free(uuid_path);

    const file = try std.fs.createFileAbsolute(uuid_path, .{});
    defer file.close();

    _ = try file.writeAll(&uuid);
}
