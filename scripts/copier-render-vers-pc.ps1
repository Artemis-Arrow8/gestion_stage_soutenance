<#
.SYNOPSIS
    Copie les données de Render (comptes, dossiers, planning, notes…) dans
    la base de la version PC de SGSUS.

.DESCRIPTION
    À lancer UNE FOIS, avec Internet, avant de travailler hors ligne :
      1. sauvegarde la base locale actuelle (dossier backups/) ;
      2. exporte la base Render, en lecture seule (pg_dump) ;
      3. remplace le contenu de la base locale par cet export ;
      4. redonne ses droits au compte applicatif local.
    Les comptes gardent les mêmes identifiants et mots de passe que sur
    Render. Rien n'est modifié sur Render.

    L'adresse de la base Render est lue dans .env (DATABASE_URL, adresse
    EXTERNE) ; elle n'est jamais affichée. L'export temporaire, qui contient
    les empreintes des mots de passe, est supprimé à la fin.

.EXAMPLE
    .\scripts\copier-render-vers-pc.ps1
    .\scripts\demarrer-pc.ps1
#>
# « Continue » : flutter et docker écrivent des messages d'information sur
# la sortie d'erreur ; seul leur code de retour ($LASTEXITCODE), vérifié
# après chaque commande, indique un échec.
$ErrorActionPreference = "Continue"

$Racine = Split-Path -Parent $PSScriptRoot
$FichierEnv = Join-Path $Racine ".env"
$Compose = @(
    "compose", "--project-directory", $Racine,
    "-f", (Join-Path $Racine "docker-compose.yml")
)

# Adresse de la base Render, lue dans .env sans l'afficher.
if (-not (Test-Path -LiteralPath $FichierEnv)) { throw "Fichier .env introuvable à la racine du projet." }
$Ligne = Get-Content -LiteralPath $FichierEnv -Encoding UTF8 -ErrorAction Stop |
    Where-Object { $_ -match '^\s*DATABASE_URL\s*=' } | Select-Object -First 1
if (-not $Ligne) { throw "DATABASE_URL (adresse externe de la base Render) est absente de .env." }
$UrlRender = ($Ligne -replace '^\s*DATABASE_URL\s*=\s*', '').Trim().Trim('"').Trim("'")
if ($UrlRender -notmatch '^postgres(ql)?://') { throw "DATABASE_URL doit commencer par postgresql://" }

& docker info *> $null
if ($LASTEXITCODE -ne 0) { throw "Docker ne répond pas : lancez Docker Desktop puis relancez ce script." }

# Base locale démarrée et prête.
& docker @Compose up -d db
if ($LASTEXITCODE -ne 0) { throw "Impossible de démarrer la base locale." }
for ($Essai = 0; $Essai -lt 30; $Essai++) {
    & docker @Compose exec -T db sh -c 'pg_isready -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 2
}

# 1) Sauvegarde de la base locale actuelle (retour arrière possible).
Write-Host "1/4 Sauvegarde de la base locale actuelle..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "backup.ps1")

$Dossier = Join-Path ([System.IO.Path]::GetTempPath()) ("sgsus-render-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $Dossier -ErrorAction Stop | Out-Null
try {
    # 2) Export de Render par un conteneur PostgreSQL 17 (même version que
    #    Render). L'adresse passe par une variable d'environnement : elle
    #    n'apparaît pas dans la ligne de commande.
    Write-Host "2/4 Export de la base Render (lecture seule)..." -ForegroundColor Cyan
    $env:SGSUS_RENDER_URL = $UrlRender
    & docker run --rm -e SGSUS_RENDER_URL -v "${Dossier}:/sortie" postgres:17 `
        sh -c 'pg_dump --no-owner --no-privileges --file=/sortie/render.sql "$SGSUS_RENDER_URL"'
    if ($LASTEXITCODE -ne 0) {
        throw "L'export de Render a échoué (connexion Internet ? adresse externe dans .env ?). Base locale inchangée."
    }
    $Export = Join-Path $Dossier "render.sql"
    if (-not (Select-String -LiteralPath $Export -Pattern 'CREATE TABLE public\.' -Quiet)) {
        throw "L'export de Render est vide ou inattendu. Base locale inchangée."
    }

    # 3) Remplacement du contenu local (API arrêtée pendant l'opération).
    Write-Host "3/4 Remplacement des données locales..." -ForegroundColor Cyan
    & docker @Compose stop backend
    & docker @Compose cp $Export db:/tmp/render.sql
    if ($LASTEXITCODE -ne 0) { throw "Copie de l'export dans le conteneur impossible." }
    $Restauration = 'psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" ' +
        '-c "DROP SCHEMA public CASCADE; CREATE SCHEMA public AUTHORIZATION pg_database_owner; GRANT USAGE ON SCHEMA public TO PUBLIC;" ' +
        '&& psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/render.sql; ' +
        'code=$?; rm -f /tmp/render.sql; exit $code'
    & docker @Compose exec -T db sh -c $Restauration
    if ($LASTEXITCODE -ne 0) {
        throw "La restauration a échoué. La sauvegarde de l'ancienne base est dans le dossier backups/."
    }

    # 4) Droits du compte applicatif sur les tables restaurées.
    Write-Host "4/4 Droits du compte applicatif..." -ForegroundColor Cyan
    & docker @Compose run --rm db-role-init
    if ($LASTEXITCODE -ne 0) { throw "L'attribution des droits a échoué." }
}
finally {
    Remove-Item Env:SGSUS_RENDER_URL -ErrorAction SilentlyContinue
    # L'export contient les empreintes des mots de passe : on le supprime.
    Remove-Item -LiteralPath $Dossier -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Données de Render copiées sur le PC." -ForegroundColor Green
Write-Host "Lancez maintenant : .\scripts\demarrer-pc.ps1"
