$ErrorActionPreference = 'Stop'

Write-Host "=== Magick Builder Setup ===" -ForegroundColor Cyan
Write-Host "Preparing a fresh Windows installation for Magick Builder...`n"

# 1. Install ImageMagick via Winget (Windows Package Manager)
Write-Host "Step 1: Checking for ImageMagick CLI..." -ForegroundColor Yellow
if (-not (Get-Command "magick" -ErrorAction SilentlyContinue)) {
    Write-Host "  -> magick.exe not found. Downloading and installing via Winget (this may take a moment)..." -ForegroundColor Cyan
    # This silently installs the official ImageMagick package from the Microsoft Winget repository
    winget install --id ImageMagick.ImageMagick --exact --accept-package-agreements --accept-source-agreements --silent
    Write-Host "  -> [SUCCESS] ImageMagick installed globally." -ForegroundColor Green
} else {
    Write-Host "  -> [OK] ImageMagick is already installed on this system." -ForegroundColor Green
}

# 2. Setup Bin Folder and Download matching Magick.NET DLLs
Write-Host "`nStep 2: Building portable 'bin' folder with matching 14.11.0 libraries..." -ForegroundColor Yellow
$binPath = Join-Path $PSScriptRoot "bin"
if (-not (Test-Path $binPath)) {
    New-Item -ItemType Directory -Force -Path $binPath | Out-Null
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "  -> Querying NuGet for the latest stable Magick.NET version..." -ForegroundColor Cyan
$versionData = Invoke-RestMethod -Uri "https://api.nuget.org/v3-flatcontainer/magick.net-q16-anycpu/index.json"
# Filter out pre-releases (versions containing a '-') and grab the absolute latest
$latestVersion = @($versionData.versions) | Where-Object { $_ -notmatch '-' } | Select-Object -Last 1
Write-Host "  -> Found latest version: $latestVersion" -ForegroundColor Green

Write-Host "  -> Downloading Core ($latestVersion)..." -ForegroundColor Cyan
Invoke-WebRequest "https://www.nuget.org/api/v2/package/Magick.NET.Core/$latestVersion" -OutFile "$binPath\core.zip"
Write-Host "  -> Downloading Native Wrapper ($latestVersion)..." -ForegroundColor Cyan
Invoke-WebRequest "https://www.nuget.org/api/v2/package/Magick.NET-Q16-AnyCPU/$latestVersion" -OutFile "$binPath\wrapper.zip"

Write-Host "  -> Extracting and sorting DLLs..." -ForegroundColor Cyan
Expand-Archive -Path "$binPath\core.zip" -DestinationPath "$binPath\core" -Force
Expand-Archive -Path "$binPath\wrapper.zip" -DestinationPath "$binPath\wrapper" -Force

Move-Item "$binPath\core\lib\netstandard20\Magick.NET.Core.dll" -Destination $binPath -Force
Move-Item "$binPath\wrapper\lib\netstandard20\Magick.NET-Q16-AnyCPU.dll" -Destination $binPath -Force
Move-Item "$binPath\wrapper\runtimes\win-x64\native\Magick.Native-Q16-x64.dll" -Destination $binPath -Force

Remove-Item "$binPath\*.zip" -Force
Remove-Item "$binPath\core", "$binPath\wrapper" -Recurse -Force

Write-Host "`n=== SETUP COMPLETE! ===" -ForegroundColor Green
Write-Host "You can now launch magick-builder-test01.ps1!" -ForegroundColor White

Start-Sleep -Seconds 5