#requires -Version 7.0
# Read-only comparison against the explicitly named local Android reference.
param([string]$ReferenceRoot = (Join-Path $PSScriptRoot '../fqapp-source-code-android/fqapp-master'))
$ErrorActionPreference = 'Stop'
$taskApp = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../app'))
$taskReference = [IO.Path]::GetFullPath($ReferenceRoot)
$taskCode = @(Get-Item (Join-Path $taskReference 'lib/main.dart'))
$taskCode += Get-ChildItem (Join-Path $taskReference 'lib/pages'),(Join-Path $taskReference 'lib/widgets') -File -Recurse
$taskAssets = @(Get-ChildItem (Join-Path $taskReference 'assets') -File -Recurse)
$taskDifferent = [Collections.Generic.List[string]]::new()
$taskAssetWhitespace = 0
$taskBridgeOnly = 0
foreach ($taskFile in $taskCode) {
    $taskRelative = [IO.Path]::GetRelativePath($taskReference, $taskFile.FullName)
    $taskDestination = Join-Path $taskApp $taskRelative
    if (-not (Test-Path -LiteralPath $taskDestination -PathType Leaf)) { $taskDifferent.Add($taskRelative); continue }
    # Git may normalize CRLF; a stripped blank line at EOF is nonvisual.
    $taskLeft = [IO.File]::ReadAllText($taskFile.FullName).Replace("`r`n", "`n").TrimEnd()
    $taskRight = [IO.File]::ReadAllText($taskDestination).Replace("`r`n", "`n").TrimEnd()
    if ($taskRelative.Replace('\','/') -eq 'lib/pages/listen_mode_page.dart' -and $taskRight.Contains("      player.audioOnly = true;`n")) {
        $taskRight = $taskRight.Replace("      player.audioOnly = true;`n", '')
        $taskBridgeOnly++
    }
    if ($taskLeft -cne $taskRight) { $taskDifferent.Add($taskRelative) }
}
foreach ($taskFile in $taskAssets) {
    $taskRelative = [IO.Path]::GetRelativePath($taskReference, $taskFile.FullName)
    $taskDestination = Join-Path $taskApp $taskRelative
    if (-not (Test-Path -LiteralPath $taskDestination -PathType Leaf)) { $taskDifferent.Add($taskRelative); continue }
    if ((Get-FileHash -LiteralPath $taskDestination).Hash -ne (Get-FileHash -LiteralPath $taskFile.FullName).Hash) {
        # Imported web/index.html had one whitespace-only blank line stripped
        # to pass Git whitespace checks. Permit that exact nonvisual difference.
        $taskEquivalent = $false
        if ($taskRelative.Replace('\','/') -eq 'assets/web/index.html') {
            $taskLeft = [regex]::Replace([IO.File]::ReadAllText($taskFile.FullName).Replace("`r`n", "`n"), '(?m)^[\t ]+$', '')
            $taskRight = [regex]::Replace([IO.File]::ReadAllText($taskDestination).Replace("`r`n", "`n"), '(?m)^[\t ]+$', '')
            $taskEquivalent = $taskLeft -ceq $taskRight
        }
        if ($taskEquivalent) { $taskAssetWhitespace++ } else { $taskDifferent.Add($taskRelative) }
    }
}
[pscustomobject]@{uiCodeFiles=$taskCode.Count;uiNonvisualAudioFlag=$taskBridgeOnly;assetFiles=$taskAssets.Count;assetRawIdentical=$taskAssets.Count-$taskAssetWhitespace;assetBlankLineOnly=$taskAssetWhitespace;different=$taskDifferent.ToArray();scope='main/pages/widgets normalized text with one exact audio-only platform flag exception; assets SHA256 with one web whitespace exception; no screen parity claim'} | ConvertTo-Json
if ($taskDifferent.Count) { throw 'Original UI/resource drift detected; review before delivery.' }
