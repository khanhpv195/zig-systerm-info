const std = @import("std");
const json = std.json;

pub fn getOrCreateDeviceId(allocator: std.mem.Allocator) ![]const u8 {
    // Đọc file
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ "C:/extech/config/local.json" });
    defer allocator.free(config_path);
    
    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();
    
    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    // Parse JSON với cú pháp mới
    var tree = try json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer tree.deinit();

    // Lấy machine_id dưới dạng chuỗi
    const machine_id = tree.value.object.get("machine").?.object.get("machine_id").?.string;
    return try allocator.dupe(u8, machine_id);
}



