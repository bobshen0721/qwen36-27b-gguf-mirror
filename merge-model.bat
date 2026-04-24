@echo off
setlocal EnableExtensions

set "BASE=%~1"
if "%BASE%"=="" set "BASE=Qwen3.6-27B-UD-IQ2_XXS.gguf"
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "PARTS_DIR=%CD%"
if not exist "%PARTS_DIR%\%BASE%.001" set "PARTS_DIR=%SCRIPT_DIR%"

if not exist "%PARTS_DIR%\%BASE%.001" (
  echo [ERROR] Cannot find "%BASE%.001".
  echo Put this BAT in the parts folder, or run it while your current directory is the parts folder.
  exit /b 1
)

set "OUTPUT=%PARTS_DIR%\%BASE%"
set "MANIFEST=%PARTS_DIR%\checksums.sha256"
if not exist "%MANIFEST%" set "MANIFEST=%SCRIPT_DIR%\checksums.sha256"

if exist "%OUTPUT%" (
  echo [ERROR] Output already exists: "%OUTPUT%"
  echo Delete or move the merged file first, then rerun.
  exit /b 1
)

echo Merging parts from "%PARTS_DIR%"...

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$base = $env:BASE;" ^
  "$dir = $env:PARTS_DIR;" ^
  "$output = $env:OUTPUT;" ^
  "$parts = Get-ChildItem -LiteralPath $dir -Filter ($base + '.???') | Sort-Object Name;" ^
  "if (-not $parts) { throw 'No parts found.' }" ^
  "$expected = 1;" ^
  "foreach ($part in $parts) { $expectedName = '{0}.{1:000}' -f $base, $expected; if ($part.Name -ne $expectedName) { throw ('Missing or out-of-order part. Expected {0}, found {1}.' -f $expectedName, $part.Name) }; $expected++ }" ^
  "$buffer = New-Object byte[] (4MB);" ^
  "$out = [System.IO.File]::Open($output, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None);" ^
  "try { foreach ($part in $parts) { Write-Host ('Adding ' + $part.Name); $in = [System.IO.File]::OpenRead($part.FullName); try { while (($read = $in.Read($buffer, 0, $buffer.Length)) -gt 0) { $out.Write($buffer, 0, $read) } } finally { $in.Dispose() } } } finally { $out.Dispose() }"

if errorlevel 1 (
  echo [ERROR] Merge failed.
  if exist "%OUTPUT%" del /f /q "%OUTPUT%" >nul 2>nul
  exit /b 1
)

echo.
echo SHA256 of merged file:
certutil -hashfile "%OUTPUT%" SHA256

if exist "%MANIFEST%" (
  echo.
  echo Expected entry from checksums.sha256:
  powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
    "$pattern = '^[0-9A-Fa-f]{64} \*' + [regex]::Escape($env:BASE) + '$';" ^
    "$line = Get-Content -LiteralPath $env:MANIFEST | Where-Object { $_ -match $pattern } | Select-Object -First 1;" ^
    "if ($line) { $line }"
)

echo.
echo Done. Run verify-model.ps1 for an exact manifest check if needed.
exit /b 0
