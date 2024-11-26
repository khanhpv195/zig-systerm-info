const std = @import("std");
const windows = std.os.windows;

const WINHTTP = struct {
    pub const HINTERNET = *opaque {};
    pub const LPCWSTR = [*:0]const u16;
    pub const DWORD = windows.DWORD;
    pub const LPVOID = windows.LPVOID;
    pub const BOOL = windows.BOOL;

    pub const WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0;
    pub const WINHTTP_QUERY_STATUS_CODE = 19;
    pub const WINHTTP_QUERY_FLAG_NUMBER = 0x20000000;

    extern "winhttp" fn WinHttpOpen(
        pszAgentW: LPCWSTR,
        dwAccessType: DWORD,
        pszProxyW: ?LPCWSTR,
        pszProxyBypassW: ?LPCWSTR,
        dwFlags: DWORD,
    ) callconv(windows.WINAPI) ?HINTERNET;

    extern "winhttp" fn WinHttpConnect(
        hSession: HINTERNET,
        pswzServerName: LPCWSTR,
        nServerPort: u16,
        dwReserved: DWORD,
    ) callconv(windows.WINAPI) ?HINTERNET;

    extern "winhttp" fn WinHttpOpenRequest(
        hConnect: HINTERNET,
        pwszVerb: LPCWSTR,
        pwszObjectName: LPCWSTR,
        pwszVersion: ?LPCWSTR,
        pwszReferrer: ?LPCWSTR,
        ppwszAcceptTypes: ?LPCWSTR,
        dwFlags: DWORD,
    ) callconv(windows.WINAPI) ?HINTERNET;

    extern "winhttp" fn WinHttpSendRequest(
        hRequest: HINTERNET,
        lpszHeaders: ?LPCWSTR,
        dwHeadersLength: DWORD,
        lpOptional: ?LPVOID,
        dwOptionalLength: DWORD,
        dwTotalLength: DWORD,
        dwContext: usize,
    ) callconv(windows.WINAPI) BOOL;

    extern "winhttp" fn WinHttpWriteData(
        hRequest: HINTERNET,
        lpBuffer: LPVOID,
        dwNumberOfBytesToWrite: DWORD,
        lpdwNumberOfBytesWritten: *DWORD,
    ) callconv(windows.WINAPI) BOOL;

    extern "winhttp" fn WinHttpReceiveResponse(
        hRequest: HINTERNET,
        lpReserved: ?LPVOID,
    ) callconv(windows.WINAPI) BOOL;

    extern "winhttp" fn WinHttpCloseHandle(hInternet: HINTERNET) callconv(windows.WINAPI) BOOL;

    extern "winhttp" fn WinHttpQueryHeaders(
        hRequest: HINTERNET,
        dwInfoLevel: DWORD,
        pwszName: ?LPCWSTR,
        lpBuffer: LPVOID,
        lpdwBufferLength: *DWORD,
        lpdwIndex: ?*DWORD,
    ) callconv(windows.WINAPI) BOOL;

    extern "winhttp" fn WinHttpReadData(
        hRequest: HINTERNET,
        lpBuffer: LPVOID,
        dwNumberOfBytesToRead: DWORD,
        lpdwNumberOfBytesRead: *DWORD,
    ) callconv(windows.WINAPI) BOOL;
};

// Fixed UTF-16 strings
const USER_AGENT = [_:0]u16{ 'Z', 'i', 'g', ' ', 'S', 'y', 's', 't', 'e', 'm', ' ', 'I', 'n', 'f', 'o' };
const POST_METHOD = [_:0]u16{ 'P', 'O', 'S', 'T' };

// Add helper function to convert string to UTF-16
pub fn stringToUtf16(allocator: std.mem.Allocator, input: []const u8) ![:0]u16 {
    return try std.unicode.utf8ToUtf16LeWithNull(allocator, input);
}

// Add function to read .env
fn getEnvValue(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    // Try reading from environment variable first
    if (std.process.getEnvVarOwned(allocator, key)) |value| {
        return value;
    } else |_| {
        // If no env var, read from .env file
        const exe_dir_path = try std.fs.selfExePathAlloc(allocator);
        defer allocator.free(exe_dir_path);

        // Go up one level from bin directory
        const parent_dir = std.fs.path.dirname(exe_dir_path) orelse return error.NoPath;
        const root_dir = std.fs.path.dirname(parent_dir) orelse return error.NoPath;

        const env_path = try std.fs.path.join(allocator, &[_][]const u8{ root_dir, ".env" });
        defer allocator.free(env_path);

        std.debug.print("Trying to read .env from: {s}\n", .{env_path});

        const env_file = std.fs.openFileAbsolute(env_path, .{}) catch |err| {
            std.debug.print("Error opening .env file: {}\n", .{err});
            // Fallback to default values if .env not found
            if (std.mem.eql(u8, key, "SERVER_HOST")) return "150.95.114.120";
            if (std.mem.eql(u8, key, "SERVER_PORT")) return "8081";
            if (std.mem.eql(u8, key, "UPLOAD_PATH")) return "/upload";
            if (std.mem.eql(u8, key, "BOUNDARY")) return "--boundary12345";
            return err;
        };
        defer env_file.close();

        const content = try env_file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        var lines = std.mem.split(u8, content, "\n");
        while (lines.next()) |line| {
            var parts = std.mem.split(u8, line, "=");
            if (parts.next()) |k| {
                if (std.mem.eql(u8, std.mem.trim(u8, k, " "), key)) {
                    if (parts.next()) |v| {
                        return allocator.dupe(u8, std.mem.trim(u8, v, " \r"));
                    }
                }
            }
        }
        return error.EnvVarNotFound;
    }
}

pub fn sendSystemInfo() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const exe_dir_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_dir_path);
    const exe_dir = std.fs.path.dirname(exe_dir_path) orelse return error.NoPath;
    const data_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "data" });
    defer allocator.free(data_dir_path);

    var dir = try std.fs.openDirAbsolute(data_dir_path, .{});
    defer dir.close();

    const file = try dir.openFile("current_metrics.db", .{ .mode = .read_only });
    defer file.close();

    try sendFileContent(file, "current_metrics.db");

    // Delete file after successful upload
    try dir.deleteFile("current_metrics.db");
    std.debug.print("info: Database file deleted after successful upload\n", .{});
}

// Modify sendFileContent function to send file directly
fn sendFileContent(file: std.fs.File, file_name: []const u8) !void {
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa_instance.allocator();
    defer _ = gpa_instance.deinit();

    // Read config from .env or use default values
    const server_host = "54.178.88.253";
    const server_port: u16 = 8082;
    const upload_path = "/uploads/upload";
    const boundary = "--boundary12345";

    // Convert to UTF-16
    const server_host_utf16 = try stringToUtf16(allocator, server_host);
    defer allocator.free(server_host_utf16);
    const upload_path_utf16 = try stringToUtf16(allocator, upload_path);
    defer allocator.free(upload_path_utf16);

    // Create Content-Type header
    const content_type = try std.fmt.allocPrint(allocator, "Content-Type: multipart/form-data; boundary={s}\r\n", .{boundary});
    defer allocator.free(content_type);
    const content_type_utf16 = try stringToUtf16(allocator, content_type);
    defer allocator.free(content_type_utf16);

    // Create form-data header
    var form_data = std.ArrayList(u8).init(allocator);
    defer form_data.deinit();

    try form_data.appendSlice("--");
    try form_data.appendSlice(boundary);
    try form_data.appendSlice("\r\n");
    try form_data.appendSlice("Content-Disposition: form-data; name=\"file\"; filename=\"");
    try form_data.appendSlice(file_name);
    try form_data.appendSlice("\"\r\n");
    try form_data.appendSlice("Content-Type: application/octet-stream\r\n\r\n");

    // Initialize WinHTTP session
    const hSession = WINHTTP.WinHttpOpen(
        &USER_AGENT,
        WINHTTP.WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        null,
        null,
        0,
    ) orelse return error.WinHttpOpenFailed;
    defer _ = WINHTTP.WinHttpCloseHandle(hSession);

    // Connect to server
    const hConnect = WINHTTP.WinHttpConnect(
        hSession,
        server_host_utf16,
        server_port,
        0,
    ) orelse return error.WinHttpConnectFailed;
    defer _ = WINHTTP.WinHttpCloseHandle(hConnect);

    // Create request
    const hRequest = WINHTTP.WinHttpOpenRequest(
        hConnect,
        &POST_METHOD,
        upload_path_utf16,
        null,
        null,
        null,
        0,
    ) orelse return error.WinHttpRequestFailed;
    defer _ = WINHTTP.WinHttpCloseHandle(hRequest);

    // Get file size
    const file_size = try file.getEndPos();

    // Create ending boundary
    const boundary_end = try std.fmt.allocPrint(allocator, "\r\n--{s}--\r\n", .{boundary});
    defer allocator.free(boundary_end);

    std.debug.print("Sending request to: {s}:{d}{s}\n", .{ server_host, server_port, upload_path });
    std.debug.print("Form data length: {d}\n", .{form_data.items.len});

    // Send request with Content-Type header
    if (WINHTTP.WinHttpSendRequest(
        hRequest,
        content_type_utf16,
        @intCast(content_type.len),
        @ptrCast(form_data.items.ptr),
        @intCast(form_data.items.len),
        @intCast(form_data.items.len + file_size + boundary_end.len),
        0,
    ) == 0) {
        return error.WinHttpSendRequestFailed;
    }

    // Send file content
    var buffer: [8192]u8 = undefined;
    var bytes_written: WINHTTP.DWORD = undefined;
    while (true) {
        const bytes_read = try file.read(&buffer);
        if (bytes_read == 0) break;

        if (WINHTTP.WinHttpWriteData(
            hRequest,
            @ptrCast(&buffer),
            @intCast(bytes_read),
            &bytes_written,
        ) == 0) {
            return error.WinHttpWriteDataFailed;
        }
    }

    // Send ending boundary
    if (WINHTTP.WinHttpWriteData(
        hRequest,
        @ptrCast(boundary_end.ptr),
        @intCast(boundary_end.len),
        &bytes_written,
    ) == 0) {
        return error.WinHttpWriteDataFailed;
    }

    // Receive response
    if (WINHTTP.WinHttpReceiveResponse(hRequest, null) == 0) {
        return error.WinHttpReceiveResponseFailed;
    }

    // Check status code
    var status_code: WINHTTP.DWORD = undefined;
    var size: WINHTTP.DWORD = @sizeOf(WINHTTP.DWORD);
    if (WINHTTP.WinHttpQueryHeaders(
        hRequest,
        WINHTTP.WINHTTP_QUERY_STATUS_CODE | WINHTTP.WINHTTP_QUERY_FLAG_NUMBER,
        null,
        &status_code,
        &size,
        null,
    ) == 0) {
        return error.WinHttpQueryHeadersFailed;
    }

    if (status_code != 200) {
        std.log.err("Upload failed with status code: {}", .{status_code});
        return error.UploadFailed;
    }

    // After successful upload and receive status code 200
    if (status_code == 200) {
        std.debug.print("info: Database file uploaded successfully\n", .{});
        return;
    }

    std.log.info("Database file uploaded successfully", .{});
}
