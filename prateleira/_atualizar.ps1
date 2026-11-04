# Atualiza a Prateleira a partir da ultima aba do Excel e publica em pages.
# PowerShell:  .\_atualizar.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
cmd.exe /c "_pub.bat"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""
Write-Host "===== _excel_week.txt ====="
if (Test-Path .\_excel_week.txt) { Get-Content .\_excel_week.txt }
Write-Host "===== _pub.txt (final) ====="
Get-Content .\_pub.txt -Tail 25
