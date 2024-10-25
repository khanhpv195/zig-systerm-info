Set WshShell = CreateObject("WScript.Shell")
' Change to your project path
WshShell.Run chr(34) & "C:\zig-systerm-info\zig-out\bin\system-info.exe" & Chr(34), 0
Set WshShell = Nothing
