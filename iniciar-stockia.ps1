param([switch]$NoAbrirNavegador)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repoStockIA = $PSScriptRoot
$urlBackend = 'http://127.0.0.1:8000/'
$urlWeb = 'http://127.0.0.1:5173/'
$procesosIniciados = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$carpetaLogs = Join-Path $repoStockIA '.stockia\logs'
$powershellStockIA = (Get-Process -Id $PID).Path

function Test-PuertoStockIA([int]$Puerto) {
    $conexion = Get-NetTCPConnection -State Listen -LocalPort $Puerto -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $conexion) { return $false }

    # El puerto puede pertenecer a un hijo de Flutter o de PowerShell.
    $idProceso = $conexion.OwningProcess
    $visitados = @{}
    while ($idProceso -and -not $visitados.ContainsKey([string]$idProceso)) {
        $visitados[[string]$idProceso] = $true
        $proceso = Get-CimInstance Win32_Process -Filter "ProcessId = $idProceso" -ErrorAction SilentlyContinue
        if (-not $proceso) { break }
        if ($proceso.CommandLine -and
            $proceso.CommandLine.Replace('/', '\').IndexOf($repoStockIA + '\', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
        $idProceso = $proceso.ParentProcessId
    }
    throw "El puerto $Puerto esta ocupado por otra aplicacion. Liberalo antes de iniciar StockIA."
}

function Start-ServicioStockIA([string]$Nombre, [string]$Script) {
    $marca = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $salida = Join-Path $carpetaLogs "$Nombre-$marca.log"
    $errores = Join-Path $carpetaLogs "$Nombre-$marca-error.log"
    $proceso = Start-Process -FilePath $powershellStockIA -ArgumentList @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-File',
        ('"{0}"' -f (Join-Path $repoStockIA $Script))
    ) -WorkingDirectory $repoStockIA -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $salida -RedirectStandardError $errores
    $procesosIniciados.Add($proceso)
    $proceso | Add-Member -NotePropertyName ArchivoSalidaStockIA -NotePropertyValue $salida
    return $proceso
}

function Wait-ServicioStockIA([string]$Nombre, [string]$Url, [int]$Segundos, $Proceso) {
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    while ($reloj.Elapsed.TotalSeconds -lt $Segundos) {
        if ($Proceso -and $Proceso.HasExited) {
            throw "$Nombre se detuvo al iniciar. Revisa los logs en $carpetaLogs"
        }
        try {
            $respuesta = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
            $compilacionLista = $true
            if ($Nombre -eq 'Web' -and $Proceso) {
                # Flutter puede servir el HTML antes de terminar la compilacion.
                $compilacionLista = [bool](Select-String -LiteralPath $Proceso.ArchivoSalidaStockIA `
                    -SimpleMatch 'is being served at' -Quiet -ErrorAction SilentlyContinue)
            }
            if ($respuesta.StatusCode -eq 200 -and $compilacionLista) { return }
        } catch {
            # La compilacion de Flutter puede tardar durante el primer arranque.
        }
        Start-Sleep -Milliseconds 500
    }
    throw "$Nombre no estuvo listo en $Segundos segundos. Revisa los logs en $carpetaLogs"
}

function Stop-ArbolStockIA([int]$IdProceso) {
    $hijos = Get-CimInstance Win32_Process -Filter "ParentProcessId = $IdProceso" -ErrorAction SilentlyContinue
    foreach ($hijo in $hijos) { Stop-ArbolStockIA -IdProceso $hijo.ProcessId }
    Stop-Process -Id $IdProceso -Force -ErrorAction SilentlyContinue
}

try {
    $backendActivo = Test-PuertoStockIA -Puerto 8000
    $webActiva = Test-PuertoStockIA -Puerto 5173
    if (-not $backendActivo -and -not (Test-Path -LiteralPath (Join-Path $repoStockIA 'backend\.venv\Scripts\python.exe'))) {
        throw 'Falta el entorno Python backend\.venv. Prepara el backend antes de iniciar.'
    }
    if (-not $webActiva) {
        $flutter = Get-Command flutter -ErrorAction SilentlyContinue
        if (-not $flutter -and -not (Test-Path -LiteralPath (Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat'))) {
            throw 'No se encontro Flutter. Agregalo al PATH o instalalo en develop\flutter.'
        }
    }
    New-Item -ItemType Directory -Path $carpetaLogs -Force | Out-Null
    $backend = $null
    $web = $null
    if ($backendActivo) { Write-Host 'Backend de StockIA ya iniciado.' }
    else {
        Write-Host 'Iniciando backend...'
        $backend = Start-ServicioStockIA -Nombre 'backend' -Script 'iniciar-backend.ps1'
    }
    Wait-ServicioStockIA -Nombre 'Backend' -Url $urlBackend -Segundos 40 -Proceso $backend
    if ($webActiva) { Write-Host 'Web de StockIA ya iniciada.' }
    else {
        Write-Host 'Iniciando Flutter web...'
        $web = Start-ServicioStockIA -Nombre 'web' -Script 'iniciar-web.ps1'
    }
    Wait-ServicioStockIA -Nombre 'Web' -Url $urlWeb -Segundos 180 -Proceso $web
    Write-Host "StockIA disponible en $urlWeb"
    if (-not $NoAbrirNavegador) { Start-Process $urlWeb }
    if ($procesosIniciados.Count -gt 0) {
        Write-Host 'Deja esta terminal abierta. Ctrl+C detiene los servicios iniciados por este comando.'
        Write-Host "Logs: $carpetaLogs"
        while ($true) {
            foreach ($proceso in $procesosIniciados) {
                if ($proceso.HasExited) { throw 'Un servicio se detuvo. Revisa los logs.' }
            }
            Start-Sleep -Seconds 1
        }
    }
} finally {
    foreach ($proceso in $procesosIniciados) {
        Stop-ArbolStockIA -IdProceso $proceso.Id
    }
}
