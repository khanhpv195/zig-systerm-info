const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const time = std.time;
const fs = std.fs;
const c = @cImport({
    @cInclude("windows.h");
    @cInclude("winreg.h");
});

const LOG_FILE_PATH = "system_metrics.txt";

const SystemInfo = struct {
    timestamp: i64,
    cpu: []const u8,
    total_ram: f64,
    used_ram: f64,
    free_ram: f64,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout = std.io.getStdOut().writer();
    var collect_count: u32 = 0;

    // Khởi tạo timer
    const minute_interval = 60 * time.ns_per_s;
    var next_collection = time.nanoTimestamp();

    while (true) {
        const current_time = time.nanoTimestamp();

        if (current_time >= next_collection) {
            collect_count += 1;

            // Thu thập thông tin
            const info = try collectSystemInfo(allocator);

            // Lưu vào file
            try saveToFile(info);

            // Hiển thị thông tin
            try displaySystemInfo(stdout, info);

            // Kiểm tra xem có nên gửi API không (10 phút một lần)
            if (collect_count >= 10) {
                try sendDataFromFile();
                collect_count = 0;
            }

            next_collection = current_time + minute_interval;
            try stdout.print("\nNext collection at: {}\n", .{std.time.epoch.EpochSeconds{ .secs = @intCast(@divFloor(next_collection, time.ns_per_s)) }});
        }

        time.sleep(1 * time.ns_per_s);
    }
}

fn saveToFile(info: SystemInfo) !void {
    const file = try fs.cwd().createFile(LOG_FILE_PATH, .{ .read = true, .truncate = false });
    defer file.close();

    try file.seekFromEnd(0);
    const writer = file.writer();

    // Thêm dòng phân cách giữa các lần ghi
    try writer.writeAll("\n=== System Information === (");
    try writer.print("{}", .{std.time.epoch.EpochSeconds{ .secs = @intCast(info.timestamp) }});
    try writer.writeAll(")\n");

    // CPU Information
    try writer.writeAll("\n--- CPU Information ---\n");
    try writer.print("{s}\n", .{info.cpu});

    // Memory Information
    try writer.writeAll("\n--- Memory Information ---\n");
    try writer.print("Total RAM: {d:.2} GB\n", .{info.total_ram});
    try writer.print("Used RAM: {d:.2} GB\n", .{info.used_ram});
    try writer.print("Free RAM: {d:.2} GB\n", .{info.free_ram});

    // Disk Information
    try writer.writeAll("\n--- Disk Information ---\n");
    try writer.writeAll("\nDrive\tTotal\t\tFree\t\tUsed\n");
    try writer.writeAll("------------------------------------------------\n");

    // Thu thập thông tin ổ đĩa
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var disk_buffer = std.ArrayList(u8).init(allocator);
    defer disk_buffer.deinit();
    try getDiskInfo(disk_buffer.writer());
    try writer.writeAll(disk_buffer.items);

    // Network Information
    try writer.writeAll("\n--- Network Information ---\n");
    var net_buffer = std.ArrayList(u8).init(allocator);
    defer net_buffer.deinit();
    try getNetworkInfo(net_buffer.writer());
    try writer.writeAll(net_buffer.items);

    // Thêm dòng phân cách cuối
    try writer.writeAll("\n========================================\n");
}

fn sendDataFromFile() !void {
    const file = try fs.cwd().openFile(LOG_FILE_PATH, .{ .mode = .read_only });
    defer file.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    // Tách các bản ghi theo dòng phân cách
    var records = std.mem.split(u8, content, "=== System Information === (");
    var data = std.ArrayList(SystemInfo).init(allocator);
    defer data.deinit();

    while (records.next()) |record| {
        if (record.len == 0) continue;

        // Parse timestamp từ header
        var lines = std.mem.split(u8, record, "\n");
        const timestamp_line = lines.next() orelse continue;
        if (timestamp_line.len == 0) continue;

        // Tìm và parse các thông tin cần thiết
        var cpu: []const u8 = "";
        var total_ram: f64 = 0;
        var used_ram: f64 = 0;
        var free_ram: f64 = 0;

        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "Processor:")) |_| {
                cpu = line[10..];
            } else if (std.mem.indexOf(u8, line, "Total RAM:")) |_| {
                total_ram = try parseRAMValue(line[10..]);
            } else if (std.mem.indexOf(u8, line, "Used RAM:")) |_| {
                used_ram = try parseRAMValue(line[9..]);
            } else if (std.mem.indexOf(u8, line, "Free RAM:")) |_| {
                free_ram = try parseRAMValue(line[9..]);
            }
        }

        // Tạo SystemInfo và thêm vào danh sách
        const info = SystemInfo{
            .timestamp = try parseTimestamp(timestamp_line),
            .cpu = try allocator.dupe(u8, cpu),
            .total_ram = total_ram,
            .used_ram = used_ram,
            .free_ram = free_ram,
        };

        try data.append(info);
    }

    if (data.items.len > 0) {
        try sendDataToApi(data.items);
        try fs.cwd().deleteFile(LOG_FILE_PATH);
        const new_file = try fs.cwd().createFile(LOG_FILE_PATH, .{});
        new_file.close();
    }
}

fn parseRAMValue(text: []const u8) !f64 {
    // Tìm và parse giá trị RAM từ chuỗi "XX.XX GB"
    var value_str = std.mem.trim(u8, text, &std.ascii.whitespace);
    if (std.mem.indexOf(u8, value_str, " GB")) |index| {
        value_str = value_str[0..index];
    }
    return try std.fmt.parseFloat(f64, value_str);
}

fn parseTimestamp(text: []const u8) !i64 {
    // Parse timestamp từ chuỗi thời gian
    var timestamp_str = std.mem.trim(u8, text, &std.ascii.whitespace);
    if (std.mem.indexOf(u8, timestamp_str, ")")) |index| {
        timestamp_str = timestamp_str[0..index];
    }
    return try std.fmt.parseInt(i64, timestamp_str, 10);
}

fn sendDataToApi(data: []const SystemInfo) !void {
    std.debug.print("Sending {d} records to API...\n", .{data.len});
    // TODO: Implement your API call here

    for (data) |info| {
        std.debug.print("Record: timestamp={d}, cpu={s}, ram={d:.2}/{d:.2}/{d:.2}\n", .{
            info.timestamp,
            info.cpu,
            info.total_ram,
            info.used_ram,
            info.free_ram,
        });
    }
}

fn getWindowsCpuInfo(writer: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Sử dụng wmic để lấy thông tin CPU
    var child = std.ChildProcess.init(&[_][]const u8{ "wmic", "cpu", "get", "name" }, allocator);
    child.stdout_behavior = .Pipe;
    try child.spawn();

    var buffer: [1024]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);
    _ = try child.wait();

    try writer.print("Processor: {s}\n", .{buffer[0..size]});
}

fn bytesToGB(bytes: u64) f64 {
    return @as(f64, @floatFromInt(bytes)) / (1024 * 1024 * 1024);
}

fn getMemoryInfo(writer: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Đổi tên biến từ total_ram thành total_ram_cmd
    var total_ram_cmd = std.ChildProcess.init(&[_][]const u8{ "wmic", "computersystem", "get", "totalphysicalmemory" }, allocator);
    total_ram_cmd.stdout_behavior = .Pipe;
    try total_ram_cmd.spawn();

    var buffer1: [1024]u8 = undefined;
    const total_stdout = total_ram_cmd.stdout.?.reader();
    const total_size = try total_stdout.readAll(&buffer1);
    _ = try total_ram_cmd.wait();

    // Xử lý output để lấy số bytes
    const output = buffer1[0..total_size];
    var lines = mem.split(u8, output, "\n");
    _ = lines.next(); // Bỏ qua dòng header

    // Tìm dòng chứa số
    var total_bytes: u64 = 0;
    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        var valid = true;
        for (trimmed) |ch| {
            if (ch < '0' or ch > '9') {
                valid = false;
                break;
            }
        }

        if (valid) {
            total_bytes = try std.fmt.parseInt(u64, trimmed, 10);
            break;
        }
    }

    // Đổi tên biến từ used_ram thành used_ram_cmd
    var used_ram_cmd = std.ChildProcess.init(&[_][]const u8{ "wmic", "OS", "get", "FreePhysicalMemory" }, allocator);
    used_ram_cmd.stdout_behavior = .Pipe;
    try used_ram_cmd.spawn();

    var buffer2: [1024]u8 = undefined;
    const used_stdout = used_ram_cmd.stdout.?.reader();
    const used_size = try used_stdout.readAll(&buffer2);
    _ = try used_ram_cmd.wait();

    // Xử lý output để lấy RAM còn trống (KB)
    const used_output = buffer2[0..used_size];
    var used_lines = mem.split(u8, used_output, "\n");
    _ = used_lines.next(); // Bỏ qua header

    var free_kb: u64 = 0;
    while (used_lines.next()) |line| {
        const trimmed = mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        var valid = true;
        for (trimmed) |ch| {
            if (ch < '0' or ch > '9') {
                valid = false;
                break;
            }
        }

        if (valid) {
            free_kb = try std.fmt.parseInt(u64, trimmed, 10);
            break;
        }
    }

    // Chuyển đổi KB thành bytes
    const free_bytes = free_kb * 1024;
    const used_bytes = total_bytes - free_bytes;

    // Đổi tên các biến RAM để tránh trùng
    const ram_total = bytesToGB(total_bytes);
    const ram_used = bytesToGB(used_bytes);
    const ram_free = bytesToGB(free_bytes);

    try writer.print("Total RAM: {d:.2} GB\n", .{ram_total});
    try writer.print("Used RAM: {d:.2} GB\n", .{ram_used});
    try writer.print("Free RAM: {d:.2} GB\n", .{ram_free});
}

fn getDiskInfo(writer: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Lấy danh sách ổ đĩa
    var drives_child = std.ChildProcess.init(&[_][]const u8{
        "wmic",
        "logicaldisk",
        "where",
        "DriveType=3",
        "get",
        "DeviceID",
        "/value",
    }, allocator);
    drives_child.stdout_behavior = .Pipe;
    try drives_child.spawn();

    var buffer: [4096]u8 = undefined;
    const drives_stdout = drives_child.stdout.?.reader();
    const drives_size = try drives_stdout.readAll(&buffer);
    _ = try drives_child.wait();

    try writer.print("\nDrive\tTotal\t\tFree\t\tUsed\n", .{});
    try writer.print("------------------------------------------------\n", .{});

    // Xử lý từng ổ đĩa
    const drives_output = buffer[0..drives_size];
    var lines = mem.split(u8, drives_output, "\n");
    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        if (!mem.startsWith(u8, trimmed, "DeviceID")) continue;

        const drive = trimmed[9..]; // Bỏ qua "DeviceID="

        // Lấy thông tin dung lượng tổng
        var size_child = std.ChildProcess.init(&[_][]const u8{
            "wmic",
            "logicaldisk",
            "where",
            try std.fmt.allocPrint(allocator, "DeviceID='{s}'", .{drive}),
            "get",
            "Size",
            "/value",
        }, allocator);
        size_child.stdout_behavior = .Pipe;
        try size_child.spawn();

        var size_buffer: [1024]u8 = undefined;
        const size_stdout = size_child.stdout.?.reader();
        const size_read = try size_stdout.readAll(&size_buffer);
        _ = try size_child.wait();

        // Lấy thông tin dung lưng trống
        var free_child = std.ChildProcess.init(&[_][]const u8{
            "wmic",
            "logicaldisk",
            "where",
            try std.fmt.allocPrint(allocator, "DeviceID='{s}'", .{drive}),
            "get",
            "FreeSpace",
            "/value",
        }, allocator);
        free_child.stdout_behavior = .Pipe;
        try free_child.spawn();

        var free_buffer: [1024]u8 = undefined;
        const free_stdout = free_child.stdout.?.reader();
        const free_read = try free_stdout.readAll(&free_buffer);
        _ = try free_child.wait();

        // Parse size
        var size_str = mem.trim(u8, size_buffer[0..size_read], &std.ascii.whitespace);
        if (mem.indexOf(u8, size_str, "=")) |index| {
            size_str = size_str[index + 1 ..];
        }
        const size_bytes = try std.fmt.parseInt(u64, size_str, 10);

        // Parse free space
        var free_str = mem.trim(u8, free_buffer[0..free_read], &std.ascii.whitespace);
        if (mem.indexOf(u8, free_str, "=")) |index| {
            free_str = free_str[index + 1 ..];
        }
        const free_bytes = try std.fmt.parseInt(u64, free_str, 10);

        const used_bytes = size_bytes - free_bytes;
        const size_gb = bytesToGB(size_bytes);
        const free_gb = bytesToGB(free_bytes);
        const used_gb = bytesToGB(used_bytes);

        try writer.print("{s}\t{d:.1} GB\t{d:.1} GB\t{d:.1} GB\n", .{
            drive,
            size_gb,
            free_gb,
            used_gb,
        });
    }
}

fn getNetworkInfo(writer: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Simplified ipconfig output
    var child = std.ChildProcess.init(&[_][]const u8{ "ipconfig", "/all" }, allocator);
    child.stdout_behavior = .Pipe;
    try child.spawn();

    var buffer: [4096]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);
    _ = try child.wait();

    try writer.print("{s}\n", .{buffer[0..size]});
}

fn collectSystemInfo(allocator: std.mem.Allocator) !SystemInfo {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    const writer = buffer.writer();

    // Thu thập thông tin CPU
    try getWindowsCpuInfo(writer);
    const cpu_info = try buffer.toOwnedSlice();

    // Thu thập thông tin RAM
    var total_bytes: u64 = 0;
    var free_kb: u64 = 0;

    // Lấy total RAM
    var total_ram_cmd = std.ChildProcess.init(&[_][]const u8{ "wmic", "computersystem", "get", "totalphysicalmemory" }, allocator);
    total_ram_cmd.stdout_behavior = .Pipe;
    try total_ram_cmd.spawn();
    var total_buffer: [1024]u8 = undefined;
    const total_size = try total_ram_cmd.stdout.?.reader().readAll(&total_buffer);
    _ = try total_ram_cmd.wait();

    // Parse total RAM
    var lines = mem.split(u8, total_buffer[0..total_size], "\n");
    _ = lines.next(); // Skip header
    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        if (std.fmt.parseInt(u64, trimmed, 10)) |value| {
            total_bytes = value;
            break;
        } else |_| {}
    }

    // Lấy free RAM
    var free_ram_cmd = std.ChildProcess.init(&[_][]const u8{ "wmic", "OS", "get", "FreePhysicalMemory" }, allocator);
    free_ram_cmd.stdout_behavior = .Pipe;
    try free_ram_cmd.spawn();
    var free_buffer: [1024]u8 = undefined;
    const free_size = try free_ram_cmd.stdout.?.reader().readAll(&free_buffer);
    _ = try free_ram_cmd.wait();

    // Parse free RAM
    lines = mem.split(u8, free_buffer[0..free_size], "\n");
    _ = lines.next(); // Skip header
    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        if (std.fmt.parseInt(u64, trimmed, 10)) |value| {
            free_kb = value;
            break;
        } else |_| {}
    }

    // Chuyển đổi đơn vị
    const free_bytes = free_kb * 1024;
    const used_bytes = total_bytes - free_bytes;

    const total_ram = bytesToGB(total_bytes);
    const used_ram = bytesToGB(used_bytes);
    const free_ram = bytesToGB(free_bytes);

    return SystemInfo{
        .timestamp = std.time.timestamp(),
        .cpu = cpu_info,
        .total_ram = total_ram,
        .used_ram = used_ram,
        .free_ram = free_ram,
    };
}

fn displaySystemInfo(writer: anytype, info: SystemInfo) !void {
    // Xóa màn hình console
    if (builtin.os.tag == .windows) {
        _ = c.system("cls");
    } else {
        _ = c.system("clear");
    }

    // Hiển thị thời gian
    try writer.print("\n=== System Information === ({})\n", .{std.time.epoch.EpochSeconds{ .secs = @intCast(info.timestamp) }});

    // Hiển thị thông tin CPU
    try writer.print("\n--- CPU Information ---\n", .{});
    try writer.print("{s}", .{info.cpu});

    // Hiển thị thông tin RAM
    try writer.print("\n--- Memory Information ---\n", .{});
    try writer.print("Total RAM: {d:.2} GB\n", .{info.total_ram});
    try writer.print("Used RAM: {d:.2} GB\n", .{info.used_ram});
    try writer.print("Free RAM: {d:.2} GB\n", .{info.free_ram});

    // Hiển thị thông tin Disk
    try writer.print("\n--- Disk Information ---\n", .{});
    try getDiskInfo(writer);

    // Hiển thị thông tin Network
    try writer.print("\n--- Network Information ---\n", .{});
    try getNetworkInfo(writer);
}
