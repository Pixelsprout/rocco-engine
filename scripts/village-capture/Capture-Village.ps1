param(
    [Parameter(Mandatory=$true)][ValidateSet('cpu','gpu','pacing')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Machine,
    [ValidateRange(1,3)][int]$Runs = 3,
    [ValidateRange(10,900)][int]$Timeout = 300,
    [switch]$Operation
)
$ErrorActionPreference = 'Stop'
$arguments = @("$PSScriptRoot/scripts/village_capture.py", '--package', $PSScriptRoot,
               '--mode', $Mode, '--output', $Output, '--runs', "$Runs", '--timeout', "$Timeout")
if ($Machine) { $arguments += @('--machine', $Machine) }
if ($Operation) { $arguments += '--operation' }
& "$PSScriptRoot/tools/python/python.exe" @arguments
if ($LASTEXITCODE -ne 0) { throw "Village capture failed with exit $LASTEXITCODE. Preserve the output directory." }
