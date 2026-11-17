param(
    [string]$PostgresBin = 'C:\Program Files\PostgreSQL\18\bin'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root

function Assert-Command([string]$operation) {
    if ($LASTEXITCODE -ne 0) { throw "$operation failed with exit code $LASTEXITCODE." }
}

$dbPort = 55433
New-Item -ItemType Directory -Force '.local' | Out-Null
if (-not (Test-Path -LiteralPath '.local/db-password.txt')) {
    $random = New-Object byte[] 24
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($random) } finally { $generator.Dispose() }
    $secret = [BitConverter]::ToString($random).Replace('-', '')
    Set-Content -LiteralPath '.local/db-password.txt' -Value $secret -NoNewline
}
$env:PGPASSWORD = Get-Content -Raw -LiteralPath '.local/db-password.txt'
$env:DATABASE_URL = "postgres://rmcs:${env:PGPASSWORD}@127.0.0.1:$dbPort/rmcs_demo"
$env:RMCS_DEMO = 'true'
$env:HOST = '127.0.0.1'
$env:PORT = '8080'
Remove-Item Env:COMPANYCAM_KEY -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath '.local/demo-db/PG_VERSION')) {
    & (Join-Path $PostgresBin 'initdb.exe') -D '.local/demo-db' -U rmcs -A scram-sha-256 --pwfile='.local/db-password.txt' --no-locale -E UTF8
    Assert-Command 'PostgreSQL initialization'
}
$pgCtl = Join-Path $PostgresBin 'pg_ctl.exe'
& $pgCtl -D '.local/demo-db' status | Out-Null
if ($LASTEXITCODE -ne 0) {
    & $pgCtl -D '.local/demo-db' -l '.local/demo-db.log' -o "-p $dbPort -h 127.0.0.1" start
    Assert-Command 'PostgreSQL startup'
}

Push-Location 'server'
try {
    if (-not (Test-Path -LiteralPath 'node_modules')) {
        npm.cmd ci
        Assert-Command 'Node dependency installation'
    }
} finally { Pop-Location }

$psql = Join-Path $PostgresBin 'psql.exe'
$exists = & $psql -h 127.0.0.1 -p $dbPort -U rmcs -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname='rmcs_demo'"
Assert-Command 'Demo database lookup'
if ($exists -ne '1') {
    & (Join-Path $PostgresBin 'createdb.exe') -h 127.0.0.1 -p $dbPort -U rmcs rmcs_demo
    Assert-Command 'Demo database creation'
}
$accounts = & $psql -h 127.0.0.1 -p $dbPort -U rmcs -d rmcs_demo -Atc "SELECT to_regclass('public.users')"
Assert-Command 'Demo account lookup'
$accountCount = '0'
if ($accounts -eq 'users') {
    $accountCount = & $psql -h 127.0.0.1 -p $dbPort -U rmcs -d rmcs_demo -Atc 'SELECT count(*) FROM users'
    Assert-Command 'Demo account count'
}
if ($accountCount -eq '0') {
    node server/src/seed.ts demo
    Assert-Command 'Demo data creation'
}

Push-Location 'app'
try {
    flutter build web --no-web-resources-cdn --dart-define=RMCS_DEMO=true
    Assert-Command 'Flutter web build'
} finally { Pop-Location }

node server/src/server.ts
