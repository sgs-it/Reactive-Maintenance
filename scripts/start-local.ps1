$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not $env:DATABASE_URL -and -not (Test-Path -LiteralPath (Join-Path $root '.env'))) {
    throw 'Set DATABASE_URL in the server environment or the workspace root .env before starting RMCS.'
}

Push-Location $root
try {
    Push-Location 'app'
    try {
        flutter build web --no-web-resources-cdn
        if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
    } finally { Pop-Location }

    Push-Location 'server'
    try {
        if (-not (Test-Path -LiteralPath 'node_modules')) {
            npm.cmd ci
            if ($LASTEXITCODE -ne 0) { throw 'Server dependency installation failed.' }
        }
        npm.cmd start
        if ($LASTEXITCODE -ne 0) { throw 'The RMCS server failed to start.' }
    } finally { Pop-Location }
} finally { Pop-Location }
