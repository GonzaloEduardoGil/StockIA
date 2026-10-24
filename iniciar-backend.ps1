param([string]$HostApi = '127.0.0.1')
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot 'backend')
try {
    & '.\.venv\Scripts\python.exe' -m uvicorn server:app --reload --host $HostApi --port 8000
} finally { Pop-Location }
