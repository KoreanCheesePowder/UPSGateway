$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "==============================================="
Write-Host " C.P Eaton UPS Gateway Edge Driver v2.9.3 dashboard fix"
Write-Host "==============================================="
Write-Host ""

$configText = Get-Content -Raw ".\config.yml"
if ($configText -notmatch "packageKey:\s*cp-eaton-ups-gateway-v212") {
  throw "Safety check failed: packageKey mismatch."
}

& smartthings --version
if ($LASTEXITCODE -ne 0) { throw "SmartThings CLI not available." }

Write-Host "[1/2] Creating a fresh dashboard Device Presentation..."
$generated = ".\generated-device-config.json"
if (Test-Path $generated) { Remove-Item $generated -Force }
& smartthings presentation:device-config:create -i ".\device-config.json" -o $generated -j
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $generated)) {
  throw "Device presentation creation failed."
}

$dp = Get-Content -Raw $generated | ConvertFrom-Json
$vid = if ($dp.presentationId) { [string]$dp.presentationId } elseif ($dp.vid) { [string]$dp.vid } else { "" }
$mnmn = if ($dp.manufacturerName) { [string]$dp.manufacturerName } elseif ($dp.mnmn) { [string]$dp.mnmn } else { "" }
if ([string]::IsNullOrWhiteSpace($vid) -or [string]::IsNullOrWhiteSpace($mnmn)) {
  throw "Could not read VID/manufacturerName from generated Device Presentation."
}

$profilePath = ".\profiles\eaton-ups-device.yml"
$profile = Get-Content -Raw $profilePath
$profile = [regex]::Replace($profile, '(?m)^\s*mnmn:\s*.*$', "  mnmn: $mnmn")
$profile = [regex]::Replace($profile, '(?m)^\s*vid:\s*.*$', "  vid: $vid")
[System.IO.File]::WriteAllText((Resolve-Path $profilePath), $profile, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Presentation VID: $vid"
Write-Host "UPS profile: cp-eaton-ups-device-dashboard"

Write-Host "[2/2] Packaging/installing v2.9.3 dashboard fix..."
& smartthings edge:drivers:package . --install
if ($LASTEXITCODE -ne 0) { throw "Driver package/install failed." }

Write-Host ""
Write-Host "Update completed."
Write-Host "Restart the Edge Driver/container once, then fully close and reopen SmartThings."
Write-Host "The UPS device will switch itself to the refreshed profile and restore the summary from cached runtime/load values."
