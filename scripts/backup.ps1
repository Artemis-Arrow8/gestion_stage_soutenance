$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BackupDir = Join-Path $ProjectRoot "backups"
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$BackupFile = Join-Path $BackupDir "gestion_stages_$Timestamp.sql"

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

Write-Host "Verification de PostgreSQL..."

docker compose -f (Join-Path $ProjectRoot "docker-compose.yml") exec -T db pg_isready
if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL n'est pas disponible. Sauvegarde annulee."
}

Write-Host "Creation de la sauvegarde..."

docker compose -f (Join-Path $ProjectRoot "docker-compose.yml") exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' |
    Set-Content -Path $BackupFile -Encoding utf8

if ($LASTEXITCODE -ne 0 -or (Get-Item $BackupFile).Length -eq 0) {
    Remove-Item $BackupFile -ErrorAction SilentlyContinue
    throw "La sauvegarde a echoue."
}

Write-Host "Sauvegarde creee : $BackupFile"
