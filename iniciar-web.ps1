param([string]$ApiUrl = 'http://127.0.0.1:8000')
$ErrorActionPreference = 'Stop'
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
$flutterEjecutable = if ($flutterCmd) { $flutterCmd.Source } else { Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat' }
Push-Location (Join-Path $PSScriptRoot 'frontend')
try {
    # Windows puede conservar el atributo de solo lectura en carpetas de
    # compilaciones anteriores. Limpiar solo ese atributo del cache generado.
    $cacheAssetsStockIA = [IO.Path]::GetFullPath((Join-Path (Get-Location) 'build\flutter_assets'))
    $buildStockIA = [IO.Path]::GetFullPath((Join-Path (Get-Location) 'build'))
    if (-not $cacheAssetsStockIA.StartsWith($buildStockIA + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'La carpeta de assets generados no esta dentro del build.'
    }
    if (Test-Path -LiteralPath $cacheAssetsStockIA) {
        $elementosStockIA = @((Get-Item -LiteralPath $cacheAssetsStockIA -Force)) +
            @(Get-ChildItem -LiteralPath $cacheAssetsStockIA -Recurse -Force)
        foreach ($elementoStockIA in $elementosStockIA) {
            if ($elementoStockIA.Attributes -band [IO.FileAttributes]::ReadOnly) {
                $elementoStockIA.Attributes = $elementoStockIA.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)
            }
        }
    }
    & $flutterEjecutable run -d web-server --web-hostname 127.0.0.1 --web-port 5173 "--dart-define=API_BASE_URL=$ApiUrl"
} finally { Pop-Location }
