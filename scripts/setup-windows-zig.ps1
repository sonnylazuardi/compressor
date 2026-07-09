$ErrorActionPreference = "Stop"
$zigRoot = Join-Path $env:LOCALAPPDATA "zig-0.16.0"
$zigExe = Join-Path $zigRoot "zig.exe"

if (-not (Test-Path $zigExe)) {
  $zip = Join-Path $env:TEMP "zig-x86_64-windows-0.16.0.zip"
  Write-Host "Downloading Zig 0.16.0..."
  Invoke-WebRequest -Uri "https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip" -OutFile $zip
  $extract = Join-Path $env:TEMP "zig-extract-0.16.0"
  if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $extract -Force
  $inner = Get-ChildItem $extract | Select-Object -First 1
  if (Test-Path $zigRoot) { Remove-Item $zigRoot -Recurse -Force }
  Move-Item $inner.FullName $zigRoot
  Write-Host "Installed Zig to $zigRoot"
} else {
  Write-Host "Zig already at $zigExe"
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$zigRoot*") {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$zigRoot", "User")
  Write-Host "Added Zig to user PATH"
}

$env:Path = "$zigRoot;" + [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
& $zigExe version
