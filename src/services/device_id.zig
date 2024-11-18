const std = @import("std");
const crypto = std.crypto;

// Đường dẫn file lưu UUID
const UUID_FILE_PATH = "data/device_uuid";

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
    const file = try std.fs.cwd().openFile(UUID_FILE_PATH, .{});
    defer file.close();

    const uuid = try file.readToEndAlloc(allocator, 36);
    if (uuid.len != 36) return error.InvalidUuidLength;

    return uuid;
}

fn saveUuidToFile(uuid: [36]u8) !void {
    // Tạo thư mục data nếu chưa tồn tại
    try std.fs.cwd().makePath("data");

    const file = try std.fs.cwd().createFile(UUID_FILE_PATH, .{});
    defer file.close();

    _ = try file.writeAll(&uuid);
}
