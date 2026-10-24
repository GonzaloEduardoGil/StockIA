param([string]$ApiUrl = 'http://10.0.2.2:8000')
# El valor predeterminado corresponde al emulador Android.
# Para un celular físico, indicar la IP accesible del backend con -ApiUrl.
$ErrorActionPreference = 'Stop'
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
$flutterEjecutable = if ($flutterCmd) { $flutterCmd.Source } else { Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat' }
Push-Location (Join-Path $PSScriptRoot 'frontend')
try {
    & $flutterEjecutable build apk --debug "--dart-define=API_BASE_URL=$ApiUrl"
} finally { Pop-Location }
