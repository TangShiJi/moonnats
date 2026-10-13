$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$moon = (Get-Command moon -ErrorAction Stop).Source
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$output = & $moon run benchmarks/codec 2>&1
$exitCode = $LASTEXITCODE
$stopwatch.Stop()
if ($exitCode -ne 0) {
  throw ($output -join [Environment]::NewLine)
}
$decoded = [int]($output | Select-Object -Last 1)
if ($decoded -ne 100000) {
  throw "Benchmark decoded $decoded frames instead of 100000."
}
$rate = [math]::Round($decoded / [math]::Max($stopwatch.Elapsed.TotalSeconds, 0.001), 0)
[pscustomobject]@{
  Frames = $decoded
  ElapsedMilliseconds = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
  FramesPerSecondIncludingStartup = $rate
} | Format-List
