const std = @import("std");

pub const CpuDetails = struct {
    name: []const u8,
    manufacturer: []const u8,
    model: []const u8,
    speed: []const u8,
};

pub fn getWindowsCpuInfo(allocator: std.mem.Allocator) !CpuDetails {
    const args = [_][]const u8{ "powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", "Get-WmiObject Win32_Processor | Select-Object Name,Manufacturer,MaxClockSpeed | Format-List" };
    var child = std.ChildProcess.init(&args, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    var buffer: [1024]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);
    _ = try child.wait();

    const output = buffer[0..size];

    // Parse the output
    var manufacturer: []const u8 = "Unknown";
    var model: []const u8 = "Unknown";
    var speed: []const u8 = "Unknown";
    var name: []const u8 = "Unknown";

    if (std.mem.indexOf(u8, output, "Intel")) |_| {
        manufacturer = try allocator.dupe(u8, "Intel");

        // Parse the model and speed from the full name
        const clean_output = std.mem.trim(u8, output, &[_]u8{ '\r', '\n', ' ' });
        const start_model = std.mem.indexOf(u8, clean_output, "Core") orelse 0;
        const end_model = std.mem.indexOf(u8, clean_output, "@") orelse clean_output.len;

        if (start_model > 0 and end_model > start_model) {
            model = try allocator.dupe(u8, std.mem.trim(u8, clean_output[start_model..end_model], &[_]u8{' '}));

            if (end_model < clean_output.len) {
                speed = try allocator.dupe(u8, std.mem.trim(u8, clean_output[end_model + 1 ..], &[_]u8{' '}));
            }
        }

        name = try allocator.dupe(u8, clean_output);
    }

    return CpuDetails{
        .name = name,
        .manufacturer = manufacturer,
        .model = model,
        .speed = speed,
    };
}

pub fn getDeviceName(allocator: std.mem.Allocator) ![]const u8 {
    const args = [_][]const u8{ "powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", "Get-WmiObject Win32_ComputerSystem | Select-Object Name | Format-List" };
    var child = std.ChildProcess.init(&args, allocator);

    child.stdout_behavior = .Pipe;

    try child.spawn();

    var buffer: [1024]u8 = undefined;
    const stdout = child.stdout.?.reader();
    const size = try stdout.readAll(&buffer);
    _ = try child.wait();

    const output = buffer[0..size];

    // Skip the header line and trim whitespace
    if (std.mem.indexOf(u8, output, "\n")) |newline_pos| {
        const device_name = std.mem.trim(u8, output[newline_pos..], &[_]u8{ '\r', '\n', ' ' });
        return try allocator.dupe(u8, device_name);
    }

    return try allocator.dupe(u8, "Unknown");
}
