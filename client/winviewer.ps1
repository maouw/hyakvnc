if (($v = (Get-ChildItem -path "$env:ProgramFiles(x86)\TurboVNC", "$env:ProgramFiles\TurboVNC" -Filter "vncvewerw.bat" -Recurse -ErrorAction SilentlyContinue).FullName) -eq $null) {
	Add-Type -AssemblyName System.Windows.Forms
	$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$openFileDialog.Filter = "TurboVNC Viewer (vncviewerw.bat)|vncviewerw.bat|All files (*.*)|*.*"
	$result = $openFileDialog.ShowDialog()
	if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    	$v = $openFileDialog.FileName
	}
}
if ($v -eq $null) {
	Write-Host "No VncViewer found."
	exit
}

try {
    Invoke-Expression "ssh -f -o StrictHostKeyChecking=no -L 5901:/mmfs1/home/altan/.hyakvnc/jobs/15346459/vnc/socket.uds -J altan@klone.hyak.uw.edu altan@g3071 sleep 10" -ErrorAction Stop | Out-Null
	Start-Process $v -ArgumentList "localhost:5901" -Wait
} catch {
    Write-Host "Could not connect to VNC server."
	exit
}
