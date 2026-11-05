param(
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Machine,
    [switch]$Operation
)
$ErrorActionPreference = 'Stop'
$arguments = @("$PSScriptRoot/scripts/village_bench_capture.py", '--package', $PSScriptRoot, '--output', $Output)
if ($Machine) { $arguments += @('--machine', $Machine) }
if ($Operation) { $arguments += '--operation' }
& "$PSScriptRoot/tools/python/python.exe" @arguments
if ($LASTEXITCODE -ne 0) { throw "Benchmark capture failed with exit $LASTEXITCODE. Preserve the output directory." }
