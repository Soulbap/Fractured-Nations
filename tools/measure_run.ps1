# Runs one Godot process and records wall time, exit code, peak RAM (working set) and
# peak GPU memory from the Windows "GPU Process Memory" performance counters, which are
# backend-independent (same source for D3D12 and Vulkan).
#
#   powershell -File tools/measure_run.ps1 -Exe <godot.exe> -ArgLine "<args>" -Out <json> [-TimeoutSec 420]
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$ArgLine,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$TimeoutSec = 420
)

$start = Get-Date
$p = Start-Process -FilePath $Exe -ArgumentList $ArgLine -PassThru -WindowStyle Normal
$peakWs = 0; $peakDed = 0; $peakShared = 0; $samples = 0; $timedOut = $false
while (-not $p.HasExited) {
    try {
        $p.Refresh()
        if ($p.PeakWorkingSet64 -gt $peakWs) { $peakWs = $p.PeakWorkingSet64 }
        $prefix = "pid_$($p.Id)_*"
        $ded = (Get-Counter '\GPU Process Memory(*)\Dedicated Usage' -ErrorAction SilentlyContinue).CounterSamples |
            Where-Object { $_.InstanceName -like $prefix } | Measure-Object -Property CookedValue -Sum
        $sh = (Get-Counter '\GPU Process Memory(*)\Shared Usage' -ErrorAction SilentlyContinue).CounterSamples |
            Where-Object { $_.InstanceName -like $prefix } | Measure-Object -Property CookedValue -Sum
        if ($ded.Sum -gt $peakDed) { $peakDed = $ded.Sum }
        if ($sh.Sum -gt $peakShared) { $peakShared = $sh.Sum }
        $samples++
    } catch { }
    if (((Get-Date) - $start).TotalSeconds -gt $TimeoutSec) {
        $timedOut = $true
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        break
    }
    Start-Sleep -Milliseconds 400
}
$p.WaitForExit(10000) | Out-Null
$result = [ordered]@{
    wall_s = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
    exit_code = $(if ($timedOut) { "timeout" } else { $p.ExitCode })
    peak_working_set_mb = [math]::Round($peakWs / 1MB, 0)
    peak_gpu_dedicated_mb = [math]::Round($peakDed / 1MB, 0)
    peak_gpu_shared_mb = [math]::Round($peakShared / 1MB, 0)
    samples = $samples
    args = $ArgLine
}
$result | ConvertTo-Json -Compress | Out-File -FilePath $Out -Encoding utf8
$result | ConvertTo-Json -Compress
