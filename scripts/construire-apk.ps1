<#
.SYNOPSIS
    Construit l'application Android de SGSUS (fichiers .apk à installer).

.DESCRIPTION
    Produit un APK par type de processeur, signé avec la clé de
    frontend/android/key.properties (fichier local, ignoré par Git) :
      * app-arm64-v8a-release.apk   : téléphones récents (Samsung Galaxy…) ;
      * app-armeabi-v7a-release.apk : anciens téléphones 32 bits ;
      * app-x86_64-release.apk      : émulateurs.
    L'application parle à l'API indiquée par -Api (par défaut : Render) et
    garde ses dernières données pour fonctionner hors ligne.

.PARAMETER Api
    Adresse HTTPS de l'API Django, terminée par /api.

.EXAMPLE
    .\scripts\construire-apk.ps1
#>
param(
    [string]$Api = "https://gestion-stage-soutenance.onrender.com/api"
)

# « Continue » : flutter écrit des messages d'information sur la sortie
# d'erreur ; seul son code de retour indique un échec.
$ErrorActionPreference = "Continue"

if ($Api -notmatch '^https://.+/api$') {
    throw "L'adresse de l'API doit commencer par https:// et se terminer par /api."
}

$Frontend = Join-Path (Split-Path -Parent $PSScriptRoot) "frontend"
Push-Location $Frontend
try {
    Write-Host "Construction des APK (plusieurs minutes la première fois)..." -ForegroundColor Cyan
    & flutter build apk --release --split-per-abi "--dart-define=API_BASE_URL=$Api"
    if ($LASTEXITCODE -ne 0) { throw "La construction de l'APK a échoué." }
}
finally {
    Pop-Location
}

$Apk = Join-Path $Frontend "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
Write-Host ""
Write-Host "APK prêt pour un téléphone Samsung récent :" -ForegroundColor Green
Write-Host "  $Apk"
Write-Host "Copiez-le sur le téléphone (câble USB, Google Drive…), ouvrez-le depuis"
Write-Host "« Mes fichiers » et autorisez l'installation d'applications inconnues."
