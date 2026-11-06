param([Parameter(Mandatory=$true)][string]$InputDirectory)
$ErrorActionPreference = 'Stop'
foreach ($run in Get-ChildItem -LiteralPath $InputDirectory -Directory) {
    $boundaries = Join-Path $run.FullName 'boundaries.csv'
    if (-not (Test-Path -LiteralPath $boundaries)) { continue }
    $arguments = @("$PSScriptRoot/scripts/village_capture_summary.py", $boundaries,
                   '--out', (Join-Path $run.FullName 'summary.json'))
    foreach ($kind in @('cpu','gpu','presentmon')) {
        $csv = Join-Path $run.FullName "$kind.csv"
        if (Test-Path -LiteralPath $csv) { $arguments += @("--$kind", $csv) }
    }
    $record = Get-Content (Join-Path $run.FullName 'run.json') -Raw | ConvertFrom-Json
    if ($record.operation) { $arguments += '--operation' }
    if ($null -eq $record.package.scene_contract) { throw 'The run has no frozen scene contract.' }
    $arguments += @('--supplement-count', "$($record.package.scene_contract.supplement_records)")
    & "$PSScriptRoot/tools/python/python.exe" @arguments
    if ($LASTEXITCODE -ne 0) { throw "Summary failed for $($run.Name). Preserve the raw files." }
}
