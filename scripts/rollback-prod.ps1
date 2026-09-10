$ErrorActionPreference = "Stop"

$knownGoodFile = "deployment\known-good.env"

if (-not (Test-Path $knownGoodFile)) {
    throw "Known-good version file not found: $knownGoodFile"
}

$knownGoodLine = Get-Content $knownGoodFile |
    Where-Object { $_ -match "^IMAGE_TAG=" }

if (-not $knownGoodLine) {
    throw "IMAGE_TAG not found in $knownGoodFile"
}

$knownGoodTag = $knownGoodLine -replace "^IMAGE_TAG=", ""

if ([string]::IsNullOrWhiteSpace($knownGoodTag)) {
    throw "Known-good IMAGE_TAG is empty."
}

Write-Host "Rolling back to known-good image:"
Write-Host $knownGoodTag

$env:IMAGE_TAG = $knownGoodTag

docker compose `
    -f docker-compose.prod.yml `
    pull

if ($LASTEXITCODE -ne 0) {
    throw "Failed to pull known-good production images."
}

docker compose `
    -f docker-compose.prod.yml `
    up -d --no-build

if ($LASTEXITCODE -ne 0) {
    throw "Failed to start production stack during rollback."
}

Write-Host "Waiting for backend health..."

$healthy = $false

for ($i = 1; $i -le 12; $i++) {
    Start-Sleep -Seconds 5

    $response = curl.exe `
        -s `
        -H "Host: api.debyez.localhost" `
        http://localhost/api/health/full

    if ($response -match '"status":"ok"') {
        $healthy = $true
        break
    }
}

if (-not $healthy) {
    throw "Rollback verification failed."
}

Set-Content -Path "deployment\current.env" -Value "IMAGE_TAG=$knownGoodTag"

Write-Host "Rollback completed successfully."
Write-Host "Restored image tag: $knownGoodTag"
Write-Host "Current deployed version recorded in deployment\current.env"