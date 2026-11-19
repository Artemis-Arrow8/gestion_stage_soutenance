$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ComposeFile = Join-Path $ProjectRoot "docker-compose.yml"
$BackupDir = Join-Path $ProjectRoot "backups"
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$BackupId = [guid]::NewGuid().ToString("N")
$BackupName = "gestion_stages_${Timestamp}_$BackupId.sql"
$BackupFile = Join-Path $BackupDir $BackupName
$ContainerTempFile = "/tmp/$BackupName"
$ComposeArguments = @("--project-directory", $ProjectRoot, "-f", $ComposeFile)
$DbContainerId = $null

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
if (Test-Path -LiteralPath $BackupFile) {
    throw "Le fichier de sauvegarde existe déjà ; opération annulée."
}

Write-Host "Vérification de PostgreSQL..."

& docker compose @ComposeArguments exec -T db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL n'est pas disponible. Sauvegarde annulée."
}

$DbContainerId = & docker compose @ComposeArguments ps -q db
if ($LASTEXITCODE -ne 0 -or -not $DbContainerId) {
    throw "Impossible d'identifier le conteneur PostgreSQL."
}
$DbContainerId = $DbContainerId.Trim()

try {
    Write-Host "Création de la sauvegarde..."

    # Le dump est écrit dans le conteneur puis copié en binaire pour préserver son encodage.
    $DumpCommand = 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" > ' + $ContainerTempFile
    & docker compose @ComposeArguments exec -T db sh -c $DumpCommand
    if ($LASTEXITCODE -ne 0) {
        throw "La création du dump PostgreSQL a échoué."
    }

    & docker cp "$($DbContainerId):$ContainerTempFile" $BackupFile
    if ($LASTEXITCODE -ne 0) {
        throw "La copie de la sauvegarde vers l'hôte a échoué."
    }

    if (-not (Test-Path -LiteralPath $BackupFile) -or (Get-Item -LiteralPath $BackupFile).Length -eq 0) {
        throw "La sauvegarde créée est vide ou introuvable."
    }
}
catch {
    if (Test-Path -LiteralPath $BackupFile) {
        Remove-Item -LiteralPath $BackupFile
    }
    throw
}
finally {
    # Le fichier temporaire n'est supprimé qu'après sa copie vers l'hôte.
    & docker compose @ComposeArguments exec -T db rm -f $ContainerTempFile
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Le dump temporaire n'a pas pu être supprimé du conteneur."
    }
}

Write-Host "Sauvegarde créée : $BackupFile"
