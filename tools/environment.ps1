#requires -Version 7.0
<#
.SYNOPSIS
Sets the locked HarmonyOS G1 toolchain for this PowerShell process only.
.EXAMPLE
$toolchain = . ./tools/environment.ps1
#>
[CmdletBinding()]
param(
    [string]$FlutterRoot = $(if ($env:FQ_FLUTTER_ROOT) { $env:FQ_FLUTTER_ROOT } else { 'E:\Codex-bulid\toolchains\flutter-oh-3.44.9-canary1' }),
    [string]$DevEcoRoot = $(if ($env:FQ_DEVECO_ROOT) { $env:FQ_DEVECO_ROOT } else { 'F:\DevEco Studio' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$FlutterRoot = [IO.Path]::GetFullPath($FlutterRoot)
$DevEcoRoot = [IO.Path]::GetFullPath($DevEcoRoot)
$taskSdkRoot = Join-Path $DevEcoRoot 'sdk'
$taskSdkDefault = Join-Path $taskSdkRoot 'default'
$taskRequired = @(
    (Join-Path $FlutterRoot 'bin/flutter.bat'),
    (Join-Path $FlutterRoot 'bin/cache/flutter.version.json'),
    (Join-Path $DevEcoRoot 'product-info.json'),
    (Join-Path $taskSdkDefault 'sdk-pkg.json'),
    (Join-Path $DevEcoRoot 'tools/node/node.exe'),
    (Join-Path $DevEcoRoot 'tools/ohpm/bin/ohpm.bat'),
    (Join-Path $DevEcoRoot 'tools/hvigor/bin/hvigorw.bat'),
    (Join-Path $DevEcoRoot 'jbr/bin/java.exe'),
    (Join-Path $taskSdkDefault 'openharmony/toolchains/hdc.exe')
)
foreach ($taskRequiredPath in $taskRequired) {
    if (-not (Test-Path -LiteralPath $taskRequiredPath -PathType Leaf)) {
        throw "Required toolchain file is missing: $taskRequiredPath. Supply -FlutterRoot/-DevEcoRoot or FQ_FLUTTER_ROOT/FQ_DEVECO_ROOT."
    }
}

$taskFlutterVersion = Get-Content -LiteralPath (Join-Path $FlutterRoot 'bin/cache/flutter.version.json') -Raw | ConvertFrom-Json
$taskFlutterHead = (& git -C $FlutterRoot rev-parse HEAD 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $taskFlutterHead -ne '39285df71a97ffe0c23241dcc459d997a9d8b7c6') {
    throw 'Flutter-OH checkout does not match the locked G1 commit.'
}
if ($taskFlutterVersion.frameworkRevision -ne $taskFlutterHead -or
    $taskFlutterVersion.frameworkVersion -ne '3.44.9+ohos-0.0.1-canary1' -or
    $taskFlutterVersion.dartSdkVersion -ne '3.12.2') {
    throw 'Flutter cached version/Dart metadata does not match the locked G1 toolchain.'
}
& git -C $FlutterRoot diff --quiet HEAD --
if ($LASTEXITCODE -ne 0) { throw 'Flutter-OH has tracked source changes; review and record them before updating this toolchain lock.' }

$taskDevEcoVersion = Get-Content -LiteralPath (Join-Path $DevEcoRoot 'product-info.json') -Raw | ConvertFrom-Json
$taskSdkVersion = Get-Content -LiteralPath (Join-Path $taskSdkDefault 'sdk-pkg.json') -Raw | ConvertFrom-Json
if ($taskDevEcoVersion.version -ne '26.0.0.851' -or $taskSdkVersion.data.apiVersion -ne '26' -or
    $taskSdkVersion.data.version -ne '26.0.0.105') {
    throw 'DevEco/SDK metadata differs from the locked G1 versions; review the toolchain record before changing this lock.'
}

# These assignments affect only this process and children. No setx, registry or
# persistent Flutter config is used. DEVECO_SDK_HOME is the directory containing
# default/sdk-pkg.json, as required by this Flutter-OH SDK discovery implementation.
$env:FQ_FLUTTER_ROOT = $FlutterRoot
$env:FQ_DEVECO_ROOT = $DevEcoRoot
$env:FLUTTER_ROOT = $FlutterRoot
$env:DEVECO_SDK_HOME = $taskSdkRoot
$env:HOS_SDK_HOME = $taskSdkRoot
$env:OHOS_SDK_HOME = $taskSdkRoot
$env:OHOS_NDK_HOME = Join-Path $taskSdkDefault 'openharmony/native'
$env:JAVA_HOME = Join-Path $DevEcoRoot 'jbr'
$env:NODE_HOME = Join-Path $DevEcoRoot 'tools/node'
$env:OHPM_HOME = Join-Path $DevEcoRoot 'tools/ohpm'
$env:HVIGOR_HOME = Join-Path $DevEcoRoot 'tools/hvigor'
$taskPathEntries = @(
    (Join-Path $FlutterRoot 'bin'),
    (Join-Path $env:JAVA_HOME 'bin'),
    $env:NODE_HOME,
    (Join-Path $env:OHPM_HOME 'bin'),
    (Join-Path $env:HVIGOR_HOME 'bin'),
    (Join-Path $taskSdkDefault 'openharmony/toolchains'),
    (Join-Path $env:OHOS_NDK_HOME 'build-tools/cmake/bin'),
    (Join-Path $env:OHOS_NDK_HOME 'llvm/bin')
)
$env:PATH = (($taskPathEntries + ($env:PATH -split ';')) | Select-Object -Unique) -join ';'

[pscustomobject]@{
    FlutterRoot = $FlutterRoot
    DevEcoRoot = $DevEcoRoot
    FlutterCommand = Join-Path $FlutterRoot 'bin/flutter.bat'
    NodeCommand = Join-Path $env:NODE_HOME 'node.exe'
    Json5Module = Join-Path $env:HVIGOR_HOME 'hvigor-ohos-plugin/node_modules/json5'
    FlutterVersion = $taskFlutterVersion.frameworkVersion
    FlutterCommit = $taskFlutterHead
    EngineCommit = $taskFlutterVersion.engineRevision
    DartVersion = $taskFlutterVersion.dartSdkVersion
    DevEcoVersion = $taskDevEcoVersion.version
    SdkVersion = $taskSdkVersion.data.version
    SdkApi = [int]$taskSdkVersion.data.apiVersion
    MinimumApi = 23
    TargetApi = 23
}
