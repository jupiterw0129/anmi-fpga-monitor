$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonPath = 'E:\develop\python\pythonw.exe'
try {
    if (-not (Test-Path -LiteralPath $pythonPath)) { throw "Python runtime missing: $pythonPath" }
    $launchId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $errorLog = Join-Path $taskRoot "output\launch_$launchId.stderr.log"
    $outputLog = Join-Path $taskRoot "output\launch_$launchId.stdout.log"
    New-Item -ItemType Directory -Path (Join-Path $taskRoot 'output') -Force | Out-Null
    # pythonw has no console; the interactive Qt window must remain visible.
    $process = Start-Process -FilePath $pythonPath -ArgumentList @('-B', '-X', 'utf8', ('"' + (Join-Path $taskRoot 'qt_desktop.py') + '"')) -WorkingDirectory $taskRoot -WindowStyle Normal -RedirectStandardOutput $outputLog -RedirectStandardError $errorLog -PassThru
    $processHandle = $process.Handle
    if ($process.WaitForExit(4000)) {
        if ($process.ExitCode -ne 0) {
            $details = Get-Content -LiteralPath $errorLog -Raw -ErrorAction SilentlyContinue
            throw "Console failed to start (exit $($process.ExitCode)).`n$details`nLog: $errorLog"
        }
    }
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
