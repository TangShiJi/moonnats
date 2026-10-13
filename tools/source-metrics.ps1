$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$all = Get-ChildItem -LiteralPath $projectRoot -Recurse -Filter '*.mbt' -File |
  Where-Object { $_.FullName -notmatch '[\\/]_build[\\/]' }
$production = Get-ChildItem -LiteralPath $projectRoot -Filter '*.mbt' -File |
  Where-Object { $_.Name -notmatch '(?:_test|_wbtest)\.mbt$' }
$tests = $all | Where-Object { $_.Name -match '(?:_test|_wbtest)\.mbt$' }

function Measure-MoonBit([System.IO.FileInfo[]] $files) {
  $physical = 0
  $nonBlank = 0
  $effective = 0
  foreach ($file in $files) {
    $lines = Get-Content -LiteralPath $file.FullName
    $physical += $lines.Count
    $nonBlank += ($lines | Where-Object { $_.Trim().Length -gt 0 }).Count
    $effective += ($lines | Where-Object {
      $text = $_.Trim()
      $text.Length -gt 0 -and -not $text.StartsWith('//')
    }).Count
  }
  [pscustomobject]@{
    Files = $files.Count
    PhysicalLines = $physical
    NonBlankLines = $nonBlank
    NonBlankNonCommentLines = $effective
  }
}

$commitCount = [int](git -C $projectRoot rev-list --count HEAD)
$report = [pscustomobject]@{
  Production = Measure-MoonBit $production
  Tests = Measure-MoonBit $tests
  GitCommits = $commitCount
}
$report | ConvertTo-Json -Depth 3

if ($report.Production.NonBlankNonCommentLines -lt 1000) {
  throw 'Effective production MoonBit source is below 1000 lines.'
}
if ($commitCount -lt 10) {
  throw 'Repository has fewer than 10 commits.'
}
