param([switch]$ConPruebas)

$ErrorActionPreference = 'Stop'
$repoStockIA = $PSScriptRoot
$carpetaEntornoStockIA = Join-Path $repoStockIA 'backend\.venv'
$pythonStockIA = Join-Path $carpetaEntornoStockIA 'Scripts\python.exe'
$flutterCmdStockIA = Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$flutterStockIA = if ($flutterCmdStockIA) { $flutterCmdStockIA.Source } else {
    Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat'
}

if (-not (Test-Path -LiteralPath $flutterStockIA)) {
    throw 'Falta Flutter. Instalalo y agregalo al PATH antes de ejecutar este comando.'
}

if (-not (Test-Path -LiteralPath $pythonStockIA)) {
    $pythonCrearStockIA = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $argumentosCrearStockIA = @()
    if (-not $pythonCrearStockIA) {
        $pythonCrearStockIA = Get-Command py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $argumentosCrearStockIA += '-3'
    }
    if (-not $pythonCrearStockIA) {
        throw 'Falta Python. Instalalo y agregalo al PATH antes de ejecutar este comando.'
    }
    Write-Host 'Preparando entorno Python...'
    $argumentosCrearStockIA += @('-m', 'venv', $carpetaEntornoStockIA)
    & $pythonCrearStockIA.Source @argumentosCrearStockIA
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar backend\.venv.' }
}

$requirementsStockIA = if ($ConPruebas) {
    Join-Path $repoStockIA 'backend\requirements-dev.txt'
} else {
    Join-Path $repoStockIA 'requirements.txt'
}

Write-Host 'Instalando dependencias del backend...'
& $pythonStockIA -m pip install -r $requirementsStockIA
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron instalar las dependencias Python.' }

Write-Host 'Instalando dependencias de Flutter...'
Push-Location (Join-Path $repoStockIA 'frontend')
try {
    & $flutterStockIA pub get
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron instalar las dependencias Flutter.' }
} finally {
    Pop-Location
}

Write-Host 'Dependencias listas. Para iniciar: .\iniciar-stockia.ps1'
