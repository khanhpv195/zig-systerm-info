Set WshShell = CreateObject("WScript.Shell")
WshShell.Run chr(34) & "C:\zig-systerm-info\zig-out\bin\system-info.exe" & Chr(34), 0
Set WshShell = Nothing
