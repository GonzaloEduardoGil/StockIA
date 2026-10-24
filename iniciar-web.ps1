param([string]$ApiUrl = 'http://127.0.0.1:8000')
$ErrorActionPreference = 'Stop'
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
$flutterEjecutable = if ($flutterCmd) { $flutterCmd.Source } else { Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat' }
Push-Location (Join-Path $PSScriptRoot 'frontend')
try {
    & $flutterEjecutable run -d web-server --web-hostname 127.0.0.1 --web-port 5173 "--dart-define=API_BASE_URL=$ApiUrl"
} finally { Pop-Location }
