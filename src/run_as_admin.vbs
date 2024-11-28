Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objShell = CreateObject("WScript.Shell")

' Lấy đường dẫn đến file VBScript
strPath = objFSO.GetParentFolderName(WScript.ScriptFullName)
strExe = objFSO.BuildPath(strPath, "system-info.exe")

' Chạy file EXE mà không cần quyền Admin
If objFSO.FileExists(strExe) Then
    objShell.Run Chr(34) & strExe & Chr(34), 1, False
Else
    MsgBox "Không tìm thấy file: " & strExe, vbCritical, "Lỗi"
End If
