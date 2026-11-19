<#
.SYNOPSIS
    Démarre (ou arrête) la VERSION PC de SGSUS : base de données, API Django
    et site Flutter sur cet ordinateur, sans Render ni Internet.

.DESCRIPTION
    Étapes :
      1. vérifie que Docker Desktop est lancé ;
      2. compile le site Flutter pour le PC (frontend/build/web_pc) s'il
         n'existe pas encore ou si le code a changé depuis (ou -Reconstruire) ;
      3. démarre les conteneurs (base, API, site : profil « pc ») ; l'image
         de l'API est reconstruite à partir du code actuel (cache Docker :
         quelques secondes, sans Internet si rien n'a changé) ;
      4. attend que l'API réponde, puis affiche les adresses à ouvrir.

    Première utilisation : à faire AVEC Internet (téléchargement des images
    Docker et des paquets Flutter). Ensuite, tout fonctionne hors ligne.
    Pour retrouver les mêmes données et comptes que sur Render, lancer une
    fois (avec Internet) : .\scripts\copier-render-vers-pc.ps1

.PARAMETER Reseau
    Rend le site accessible aux téléphones connectés au même Wi-Fi que le PC.

.PARAMETER Reconstruire
    Force la recompilation du site Flutter, même si le code n'a pas changé.

.PARAMETER Arreter
    Arrête la version PC. Les données sont conservées.

.EXAMPLE
    .\scripts\demarrer-pc.ps1
    .\scripts\demarrer-pc.ps1 -Reseau
    .\scripts\demarrer-pc.ps1 -Arreter
#>
param(
    [switch]$Reseau,
    [switch]$Reconstruire,
    [switch]$Arreter
)

# « Continue » : flutter et docker écrivent des messages d'information sur
# la sortie d'erreur ; seul leur code de retour ($LASTEXITCODE), vérifié
# après chaque commande, indique un échec.
$ErrorActionPreference = "Continue"

$Racine = Split-Path -Parent $PSScriptRoot
$Frontend = Join-Path $Racine "frontend"
$SitePc = Join-Path $Frontend "build\web_pc"
$FichierEnv = Join-Path $Racine ".env"
$Compose = @(
    "compose", "--project-directory", $Racine,
    "-f", (Join-Path $Racine "docker-compose.yml"),
    "--profile", "pc"
)

# Lit une variable du fichier .env (sans jamais afficher les secrets).
function Lire-VariableEnv([string]$Nom, [string]$Defaut) {
    if (Test-Path -LiteralPath $FichierEnv) {
        $Ligne = Get-Content -LiteralPath $FichierEnv -Encoding UTF8 -ErrorAction Stop |
            Where-Object { $_ -match "^\s*$Nom\s*=" } | Select-Object -First 1
        if ($Ligne) {
            $Valeur = ($Ligne -replace "^\s*$Nom\s*=\s*", "").Trim().Trim('"')
            if ($Valeur) { return $Valeur }
        }
    }
    return $Defaut
}

$Port = Lire-VariableEnv "FRONTEND_PORT" "8080"
$PortDjango = Lire-VariableEnv "DJANGO_PORT" "8001"

# 1) Docker Desktop doit être lancé.
& docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Docker ne répond pas : lancez Docker Desktop, attendez qu'il soit prêt, puis relancez ce script."
}

if ($Arreter) {
    & docker @Compose stop
    if ($LASTEXITCODE -ne 0) { throw "L'arrêt de la version PC a échoué." }
    Write-Host "Version PC arrêtée (données conservées)." -ForegroundColor Green
    return
}

# 2) Site Flutter compilé pour le PC : l'API est à la même adresse que le
#    site (« /api ») ; moteur de rendu et polices sont servis localement,
#    sans aucun accès à Google.
#    Le site est recompilé s'il manque ou si un fichier source (code,
#    page Web, polices, pubspec.yaml) est plus récent que lui.
$IndexPc = Join-Path $SitePc "index.html"
$APreparer = $Reconstruire -or -not (Test-Path -LiteralPath $IndexPc)
if (-not $APreparer) {
    $DateSite = (Get-Item -LiteralPath $IndexPc).LastWriteTime
    $Sources = @("lib", "web", "assets", "pubspec.yaml") |
        ForEach-Object { Join-Path $Frontend $_ } |
        Where-Object { Test-Path -LiteralPath $_ }
    $PlusRecent = Get-ChildItem -LiteralPath $Sources -Recurse -File |
        Where-Object { $_.LastWriteTime -gt $DateSite } | Select-Object -First 1
    $APreparer = [bool]$PlusRecent
}
if ($APreparer) {
    Write-Host "Compilation du site Flutter pour le PC (quelques minutes)..." -ForegroundColor Cyan
    Push-Location $Frontend
    try {
        & flutter build web --release --no-web-resources-cdn "--dart-define=API_BASE_URL=/api" --output $SitePc
        if ($LASTEXITCODE -ne 0) { throw "La compilation Flutter a échoué." }
    }
    finally {
        Pop-Location
    }
}

# 3) Démarrage des conteneurs. -Reseau : écoute sur toutes les interfaces
#    du PC (Wi-Fi compris) au lieu de 127.0.0.1 seulement.
$env:FRONTEND_BIND_ADDRESS = if ($Reseau) { "0.0.0.0" } else { "127.0.0.1" }
# --build : l'API tourne toujours avec le code actuel du dossier backend.
& docker @Compose up -d --build
if ($LASTEXITCODE -ne 0) { throw "Le démarrage des conteneurs a échoué." }

# 4) Attente de l'API (3 minutes au plus). Tant que Django démarre
#    (migrations, fichiers statiques), le site répond 502.
Write-Host "Démarrage de l'API..." -ForegroundColor Cyan
$Pret = $false
for ($Essai = 0; $Essai -lt 90 -and -not $Pret; $Essai++) {
    try {
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://127.0.0.1:$Port/api/" | Out-Null
        $Pret = $true
    }
    catch {
        $Code = 0
        if ($_.Exception.Response) { $Code = [int]$_.Exception.Response.StatusCode }
        # 401, 403, 404… : c'est Django qui répond, l'API fonctionne donc.
        if ($Code -ge 400 -and $Code -lt 500) { $Pret = $true }
        else { Start-Sleep -Seconds 2 }
    }
}
if (-not $Pret) {
    throw "L'API ne répond pas. Consultez les journaux : docker compose logs backend"
}

Write-Host ""
Write-Host "SGSUS est prêt sur ce PC (aucune connexion Internet nécessaire) :" -ForegroundColor Green
Write-Host "  Application    : http://localhost:$Port"
Write-Host "  Administration : http://localhost:$PortDjango/admin/"
if ($Reseau) {
    # Adresses du PC sur le réseau local (hors adaptateurs virtuels).
    $Adresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" -and
            $_.InterfaceAlias -notmatch "vEthernet|WSL|Docker|Loopback|VirtualBox|VMware"
        } |
        Select-Object -ExpandProperty IPAddress
    foreach ($Adresse in $Adresses) {
        Write-Host "  Téléphone (même Wi-Fi) : http://${Adresse}:$Port"
    }
    Write-Host "  Si Windows demande l'autorisation du pare-feu, autorisez les réseaux privés."
}
Write-Host "Pour arrêter : .\scripts\demarrer-pc.ps1 -Arreter"
