If WScript.Arguments.length = 0 Then
    Set objShell = CreateObject("Shell.Application")
    objShell.ShellExecute "wscript.exe", Chr(34) & WScript.ScriptFullName & Chr(34) & " RunAsAdministrator", "", "runas", 1
    WScript.Quit
End If

Set objFSO = CreateObject("Scripting.FileSystemObject")
strPath = objFSO.GetParentFolderName(WScript.ScriptFullName)
strExe = objFSO.BuildPath(strPath, "system-info.exe")

' Thay đổi cách chạy exe để duy trì quyền admin
Set objShell = CreateObject("Shell.Application")
objShell.ShellExecute strExe, "", strPath, "runas", 0 