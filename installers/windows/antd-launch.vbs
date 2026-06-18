' Hidden launcher for antd. Task Scheduler / the installer invoke this via
' wscript.exe; Run(..., 0, False) starts antd with NO visible console window
' (antd is a console program and would otherwise flash a terminal).
Dim shell
Set shell = CreateObject("WScript.Shell")
shell.Run """C:\Program Files\Autonomi\antd\antd.exe"" --cors", 0, False
