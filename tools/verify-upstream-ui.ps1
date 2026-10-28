#requires -Version 7.0
# Source-level UI parity only; this does not claim rendered/device equivalence.
param(
    [string]$ReferenceRoot = (Join-Path $PSScriptRoot '../fqapp-source-code-android/fqapp-master'),
    [string]$ReviewFile = (Join-Path $PSScriptRoot '../docs/upstream/ui-parity-review.json')
)
$ErrorActionPreference = 'Stop'
$taskApp = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../app'))
$taskReference = [IO.Path]::GetFullPath($ReferenceRoot)
$taskReview = Get-Content -LiteralPath $ReviewFile -Raw | ConvertFrom-Json
$taskReferenceHead = (& git -C $taskReference rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $taskReferenceHead -ne $taskReview.upstreamCommit) { throw 'UI review belongs to a different upstream revision.' }

function Get-FqUiHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'missing' }
    $taskExtension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($taskExtension -in @('.dart', '.json', '.js', '.md', '.html', '.css', '.txt', '.svg', '.yaml')) {
        $taskText = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").TrimEnd()
        $taskBytes = [Text.Encoding]::UTF8.GetBytes($taskText)
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskBytes)).ToLowerInvariant()
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$taskCode = @(Get-Item (Join-Path $taskReference 'lib/main.dart'))
$taskCode += Get-ChildItem (Join-Path $taskReference 'lib/pages'),(Join-Path $taskReference 'lib/widgets') -File -Recurse
$taskAssets = @(Get-ChildItem (Join-Path $taskReference 'assets') -File -Recurse)
$taskUnexpected = [Collections.Generic.List[string]]::new()
$taskReviewed = [Collections.Generic.List[string]]::new()
$taskEqualCode = 0
$taskEqualAssets = 0
foreach ($taskFile in @($taskCode) + @($taskAssets)) {
    $taskRelative = [IO.Path]::GetRelativePath($taskReference, $taskFile.FullName).Replace('\', '/')
    $taskLeft = Get-FqUiHash $taskFile.FullName
    $taskRight = Get-FqUiHash (Join-Path $taskApp $taskRelative)
    if ($taskLeft -eq $taskRight) {
        if ($taskRelative.StartsWith('lib/')) { $taskEqualCode++ } else { $taskEqualAssets++ }
        continue
    }
    $taskMatch = @($taskReview.exceptions | Where-Object { $_.path -ceq $taskRelative })
    if ($taskMatch.Count -eq 1 -and $taskMatch[0].upstreamHash -eq $taskLeft -and
        $taskMatch[0].harmonyHash -eq $taskRight -and $taskMatch[0].reason) {
        $taskReviewed.Add($taskRelative)
    } else { $taskUnexpected.Add($taskRelative) }
}
[pscustomobject]@{
    upstreamCommit = $taskReferenceHead
    uiCodeFiles = $taskCode.Count
    uiCodeIdentical = $taskEqualCode
    assetFiles = $taskAssets.Count
    assetsIdentical = $taskEqualAssets
    reviewedAdaptations = $taskReviewed.ToArray()
    unexpectedDifferences = $taskUnexpected.ToArray()
    scope = 'Text normalized for CRLF/EOF only; binary assets SHA256. Reviewed differences require both exact content hashes. No screen or device acceptance claim.'
} | ConvertTo-Json
if ($taskUnexpected.Count) { throw 'Unreviewed UI/resource drift detected.' }
