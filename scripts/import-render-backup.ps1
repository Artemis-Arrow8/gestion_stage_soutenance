$ErrorActionPreference = "Stop"

$Container = "gestion_stage_soutenance-db-1"
$BackupPath = Join-Path (Split-Path -Parent $PSScriptRoot) "backup_docker.sql"
$TemporaryName = "sgsus-render-restore-$([guid]::NewGuid().ToString('N')).sql"
$LocalTemporaryPath = Join-Path ([System.IO.Path]::GetTempPath()) $TemporaryName
$ContainerTemporaryPath = "/tmp/$TemporaryName"
$ContainerHasTemporaryFile = $false

if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
    throw "Le fichier backup_docker.sql est introuvable à la racine du dépôt."
}

$ContainerState = & docker inspect --format '{{.State.Running}}' $Container 2>$null
if ($LASTEXITCODE -ne 0 -or ([string]$ContainerState).Trim() -ne "true") {
    throw "Le conteneur Docker $Container doit être démarré."
}

$RenderHost = Read-Host "Hôte externe PostgreSQL affiché par Render"
$RenderDatabase = Read-Host "Nom exact de la base Render"
$RenderUser = Read-Host "Utilisateur PostgreSQL Render"
if ([string]::IsNullOrWhiteSpace($RenderHost) -or
    [string]::IsNullOrWhiteSpace($RenderDatabase) -or
    [string]::IsNullOrWhiteSpace($RenderUser)) {
    throw "L'hôte, la base et l'utilisateur Render sont obligatoires."
}

try {
    $Sql = [System.IO.File]::ReadAllText($BackupPath, [System.Text.Encoding]::UTF8)
    $OwnerPattern = '(?m)^ALTER .* OWNER TO sgsus_app_user;\r?$'
    $GrantPattern = '(?m)^GRANT .* TO sgsus_app_user;\r?$'
    $OwnerCount = [regex]::Matches($Sql, $OwnerPattern).Count
    $GrantCount = [regex]::Matches($Sql, $GrantPattern).Count

    if ($OwnerCount -eq 0 -or $GrantCount -eq 0) {
        throw "Le dump ne correspond pas au format attendu ; restauration annulée."
    }

    # Les objets restaurés appartiendront à l'utilisateur Render qui exécute psql.
    $Sql = [regex]::Replace($Sql, $OwnerPattern, "")
    $Sql = [regex]::Replace($Sql, $GrantPattern, "")
    if ([regex]::IsMatch($Sql, $OwnerPattern) -or
        [regex]::IsMatch($Sql, $GrantPattern)) {
        throw "Le dump contient encore une référence au rôle local."
    }

    $RestoreGuard = @'
DO $$
BEGIN
    IF current_setting('server_version_num')::integer < 170000 THEN
        RAISE EXCEPTION 'La base Render doit être en PostgreSQL 17 ou supérieur.';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public') THEN
        RAISE EXCEPTION 'La base Render doit être vide avant la restauration.';
    END IF;
END
$$;
'@
    $RestoreSql = $RestoreGuard + [Environment]::NewLine + $Sql
    $Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $LocalTemporaryPath,
        $RestoreSql,
        $Utf8WithoutBom
    )

    Write-Host "Restauration protégée : PostgreSQL 17+, base vide, TLS et transaction unique."
    Write-Host "Tape IMPORTER pour confirmer ; le mot de passe sera demandé par psql."
    if ((Read-Host "Confirmation") -cne "IMPORTER") {
        throw "Restauration annulée."
    }

    & docker cp $LocalTemporaryPath ($Container + ":" + $ContainerTemporaryPath)
    if ($LASTEXITCODE -ne 0) {
        throw "Copie du dump préparé dans le conteneur impossible."
    }
    $ContainerHasTemporaryFile = $true

    $PsqlArguments = @(
        "exec", "-e", "PGSSLMODE=require", "-it", $Container,
        "psql",
        "--host", $RenderHost,
        "--port", "5432",
        "--username", $RenderUser,
        "--dbname", $RenderDatabase,
        "--set", "ON_ERROR_STOP=1",
        "--single-transaction",
        "--password",
        "--file", $ContainerTemporaryPath
    )
    & docker @PsqlArguments
    if ($LASTEXITCODE -ne 0) {
        throw "La restauration PostgreSQL a échoué ; vérifier le message de psql."
    }

    Write-Host "Restauration Render terminée."
}
finally {
    if ($ContainerHasTemporaryFile) {
        & docker exec $Container rm -f $ContainerTemporaryPath | Out-Null
    }
    if (Test-Path -LiteralPath $LocalTemporaryPath) {
        Remove-Item -LiteralPath $LocalTemporaryPath -Force
    }
}
