Set WshShell = CreateObject("WScript.Shell")
' Thêm tham số 0 để chạy ẩn hoàn toàn
WshShell.Run chr(34) & "C:\zig-systerm-info\zig-out\bin\system-info.exe" & Chr(34), 0, False
Set WshShell = Nothing
