#requires -Version 7.0
<#
.SYNOPSIS
Builds one unsigned HAP attempt and produces records for a reviewed local commit.
.DESCRIPTION
Does not stage, commit, sign, install, or run the application. The repository rule
requires a local commit after EVERY HAP attempt. Review the source and docs/builds
diff, explicitly stage the relevant files, and commit before calling this again.
Raw output stays in ignored local-reports/builds. Public records deliberately do
not copy raw diagnostics, absolute machine paths, identity or device information.
.EXAMPLE
./tools/build-hap.ps1 -Target ohos-arm64 -Mode debug
#>
[CmdletBinding()]
param(
    [ValidateSet('ohos-arm64', 'ohos-x64')][string]$Target = 'ohos-arm64',
    [ValidateSet('debug', 'release')][string]$Mode = 'debug',
    [ValidateSet('lib/main.dart', 'test_driver/harmony_acceptance.dart')][string]$DartTarget = 'lib/main.dart',
    [string]$FlutterRoot = $(if ($env:FQ_FLUTTER_ROOT) { $env:FQ_FLUTTER_ROOT } else { 'E:\Codex-bulid\toolchains\flutter-oh-3.44.9-canary1' }),
    [string]$DevEcoRoot = $(if ($env:FQ_DEVECO_ROOT) { $env:FQ_DEVECO_ROOT } else { 'F:\DevEco Studio' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskAppRoot = Join-Path $taskRoot 'app'
$taskUtf8 = [Text.UTF8Encoding]::new($false)

function Invoke-FqGit {
    param([Parameter(Mandatory)][string[]]$GitArguments)
    $taskGitText = (& git -C $taskRoot @GitArguments 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Git check failed: git $($GitArguments -join ' '). $taskGitText" }
    return $taskGitText.TrimEnd()
}

function Get-FqInputSnapshot {
    # Include tracked AND untracked non-ignored inputs, so a pre-build HEAD alone
    # cannot hide local source/config changes. Never enumerate the Android source.
    $taskNamesText = Invoke-FqGit -GitArguments @('ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', 'app', 'tools', '.gitignore', '.gitattributes')
    $taskNames = @($taskNamesText.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries) | Sort-Object -Unique)
    $taskManifestLines = [Collections.Generic.List[string]]::new()
    foreach ($taskName in $taskNames) {
        if ($taskName -match '(?i)(^|/)(signing|local-data|local-reports|fqapp-source-code-android)/|\.(hap|hsp|apk|aab|app|so|dll|dylib|a|p12|pfx|jks|keystore|cer|p7b|pem|key)$|(^|/)(device_pool\.json|local\.properties(?:\..*)?|\.env(?:\..*)?)$') {
            throw "Prohibited or machine-local file appears among controlled build inputs: $taskName"
        }
        $taskFullPath = Join-Path $taskRoot $taskName
        if (-not (Test-Path -LiteralPath $taskFullPath -PathType Leaf)) { continue } # A tracked deletion is captured by git status.
        $taskFile = Get-Item -LiteralPath $taskFullPath -Force
        if ($taskFile.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Build inputs must not be links: $taskName" }
        $taskHash = (Get-FileHash -LiteralPath $taskFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $taskManifestLines.Add("$taskHash  $taskName")
    }
    $taskManifestText = ($taskManifestLines -join "`n") + "`n"
    $taskSha256 = [Security.Cryptography.SHA256]::Create()
    try { $taskDigest = $taskSha256.ComputeHash($taskUtf8.GetBytes($taskManifestText)) }
    finally { $taskSha256.Dispose() }
    [pscustomobject]@{
        Text = $taskManifestText
        Digest = [BitConverter]::ToString($taskDigest).Replace('-', '').ToLowerInvariant()
        Count = $taskManifestLines.Count
    }
}

function Get-FqHapSnapshot {
    $taskSnapshot = @{}
    # The first build has no output directory. Search only known output roots.
    foreach ($taskOutputRoot in @((Join-Path $taskAppRoot 'build'), (Join-Path $taskAppRoot 'ohos/entry/build'))) {
        if (-not (Test-Path -LiteralPath $taskOutputRoot -PathType Container)) { continue }
        foreach ($taskHap in Get-ChildItem -LiteralPath $taskOutputRoot -Filter '*.hap' -File -Recurse -Force) {
            $taskRelative = [IO.Path]::GetRelativePath($taskRoot, $taskHap.FullName).Replace('\', '/')
            $taskSnapshot[$taskRelative] = [pscustomobject]@{
                Path = $taskRelative
                Sha256 = (Get-FileHash -LiteralPath $taskHap.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                Bytes = $taskHap.Length
                WriteTicks = $taskHap.LastWriteTimeUtc.Ticks
            }
        }
    }
    return $taskSnapshot
}

Push-Location -LiteralPath $taskRoot
try {
    $taskRepoRoot = Invoke-FqGit -GitArguments @('rev-parse', '--show-toplevel')
    if ([IO.Path]::GetFullPath($taskRepoRoot) -ne $taskRoot) { throw 'Run only in this repository, not a parent repository.' }
    $taskPending = Invoke-FqGit -GitArguments @('status', '--porcelain=v1', '--untracked-files=all', '--', 'docs/builds')
    if ($taskPending) { throw 'Uncommitted docs/builds records exist. Review and locally commit the previous attempt before another HAP build.' }
    $taskGitName = Invoke-FqGit -GitArguments @('config', 'user.name')
    $taskGitEmail = Invoke-FqGit -GitArguments @('config', 'user.email')
    if (-not $taskGitName.Trim() -or -not $taskGitEmail.Trim()) { throw 'Git user.name/user.email must be configured by the user before building.' }
    # Validate Git itself can form an identity; never store it in public records.
    $null = Invoke-FqGit -GitArguments @('var', 'GIT_AUTHOR_IDENT')
    $null = Invoke-FqGit -GitArguments @('var', 'GIT_COMMITTER_IDENT')
    $taskHead = Invoke-FqGit -GitArguments @('rev-parse', 'HEAD')
    $taskInputStatus = Invoke-FqGit -GitArguments @('status', '--porcelain=v1', '--untracked-files=all', '--', 'app', 'tools', '.gitignore', '.gitattributes')
    if (-not (Test-Path -LiteralPath (Join-Path $taskAppRoot 'pubspec.yaml') -PathType Leaf)) { throw 'app/pubspec.yaml does not exist.' }
    $taskToolchain = & (Join-Path $PSScriptRoot 'environment.ps1') -FlutterRoot $FlutterRoot -DevEcoRoot $DevEcoRoot
    # Parse JSON5 with the locked DevEco package; do not infer API values by regex.
    $taskProfileProbe = @'
const fs = require('fs');
const JSON5 = require(process.argv[1]);
const p = JSON5.parse(fs.readFileSync(process.argv[2], 'utf8'));
const product = p.app.products.find(x => x.name === 'default');
if (!product) throw Error('Missing default product');
const api = value => typeof value === 'number' ? value : Number((String(value).match(/\((\d+)(?:\.\d+)*\)$/) || [])[1]);
if (api(product.compatibleSdkVersion) !== 23 || api(product.targetSdkVersion) !== 23 || api(product.compileSdkVersion) !== 26 || product.runtimeOS !== 'HarmonyOS') {
  throw Error('Expected default product: HarmonyOS compatible API 23, target API 23, compile API 26');
}
process.stdout.write('API configuration checked');
'@
    $taskProfileCheck = & $taskToolchain.NodeCommand -e $taskProfileProbe $taskToolchain.Json5Module (Join-Path $taskAppRoot 'ohos/build-profile.json5') 2>&1
    if ($LASTEXITCODE -ne 0) { throw "API configuration gate failed: $taskProfileCheck" }
    # Collect every optional/version input before invoking the real build. The
    # finally receipt below must not depend on a later version probe succeeding.
    $taskNodeVersion = (& $taskToolchain.NodeCommand --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not determine Node version.' }
    $taskOhpmVersion = (Get-Content -LiteralPath (Join-Path $taskToolchain.DevEcoRoot 'tools/ohpm/package.json') -Raw | ConvertFrom-Json).version
    $taskHvigorVersion = (Get-Content -LiteralPath (Join-Path $taskToolchain.DevEcoRoot 'tools/hvigor/hvigor/package.json') -Raw | ConvertFrom-Json).version
    $taskJavaVersion = (Get-Content -LiteralPath (Join-Path $taskToolchain.DevEcoRoot 'jbr/release') | Where-Object { $_ -like 'JAVA_VERSION=*' }) -replace '^JAVA_VERSION="|"$', ''
    # The only shell interpolation is a validated executable path and enum values.
    # cmd.exe is necessary for Flutter's Windows .bat entrypoint.
    if ($taskToolchain.FlutterCommand -match '["\r\n%&|<>^!]') { throw 'Flutter path contains unsupported cmd.exe metacharacters.' }
    if ($DartTarget -ne 'lib/main.dart' -and $Mode -ne 'debug') { throw 'Acceptance target is debug-only.' }
    $taskCommandText = '""{0}" build hap --{1} --target-platform {2} --target {3} --no-codesign"' -f $taskToolchain.FlutterCommand, $Mode, $Target, $DartTarget

    $taskBuildId = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
    $taskRecordName = "$taskBuildId-$Mode-$Target"
    $taskRawRelative = "local-reports/builds/$taskRecordName"
    & git -C $taskRoot check-ignore --quiet -- $taskRawRelative
    if ($LASTEXITCODE -ne 0) { throw 'local-reports/builds must be Git-ignored before capturing raw logs.' }
    $taskDocsRoot = Join-Path $taskRoot 'docs/builds'
    $taskRawRoot = Join-Path $taskRoot $taskRawRelative
    New-Item -ItemType Directory -Force -Path $taskDocsRoot, $taskRawRoot | Out-Null
    $taskInputs = Get-FqInputSnapshot
    $taskBeforeHaps = Get-FqHapSnapshot
    $taskManifestName = "$taskRecordName.inputs.sha256"
    $taskManifestPath = Join-Path $taskDocsRoot $taskManifestName
    $taskRecordRelative = "docs/builds/$taskRecordName.md"
    $taskRecordPath = Join-Path $taskRoot $taskRecordRelative
    [IO.File]::WriteAllText($taskManifestPath, $taskInputs.Text, $taskUtf8)
    [IO.File]::WriteAllText((Join-Path $taskRawRoot 'input-git-status.txt'), $taskInputStatus, $taskUtf8)

    $taskBuildExit = $null
    $taskWrapperFailed = $false
    $taskAttemptStarted = $false
    $taskNewHaps = @()
    $taskInputsAfter = $null
    $taskStartedUtc = [DateTimeOffset]::UtcNow
    $taskProcess = $null
    try {
        [IO.File]::WriteAllText((Join-Path $taskRawRoot 'attempt.txt'), "Build $taskBuildId`nStarted UTC: $($taskStartedUtc.ToString('o'))`nflutter build hap --$Mode --target-platform $Target --target $DartTarget --no-codesign`n", $taskUtf8)
        Write-Host "HAP attempt $taskBuildId started. Raw logs: $taskRawRelative"
        $taskAttemptStarted = $true
        $taskProcess = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/s', '/c', $taskCommandText) -WorkingDirectory $taskAppRoot -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput (Join-Path $taskRawRoot 'stdout.log') -RedirectStandardError (Join-Path $taskRawRoot 'stderr.log')
        $taskBuildExit = $taskProcess.ExitCode
    }
    catch {
        $taskWrapperFailed = $true
        [IO.File]::WriteAllText((Join-Path $taskRawRoot 'wrapper-error.txt'), ($_ | Out-String), $taskUtf8)
    }
    finally {
        if ($taskAttemptStarted) {
            # After the actual build invocation, this finally block always writes a
            # public receipt, even when artifact/hash collection raises an error.
            try {
                $taskAfterHaps = Get-FqHapSnapshot
                $taskNewHaps = @($taskAfterHaps.Values | Where-Object {
                    -not $taskBeforeHaps.ContainsKey($_.Path) -or
                    $taskBeforeHaps[$_.Path].Sha256 -ne $_.Sha256 -or
                    $taskBeforeHaps[$_.Path].WriteTicks -ne $_.WriteTicks
                } | Sort-Object Path)
                $taskInputsAfter = Get-FqInputSnapshot
            }
            catch {
                $taskWrapperFailed = $true
                [IO.File]::AppendAllText((Join-Path $taskRawRoot 'wrapper-error.txt'), ($_ | Out-String), $taskUtf8)
            }
            $taskEndedUtc = [DateTimeOffset]::UtcNow
            $taskResult = if ($null -eq $taskBuildExit) { 'Build process exit code unavailable; wrapper failed' } elseif ($taskBuildExit -ne 0) { 'Build failed' } elseif ($taskNewHaps.Count -eq 0) { 'Command returned zero, but no new or updated HAP was found; output unverified' } elseif ($taskWrapperFailed) { 'Command returned zero; record collection incomplete' } else { 'Command returned zero and produced HAP output; package validation pending' }
            $taskExitText = if ($null -eq $taskBuildExit) { 'unavailable' } else { [string]$taskBuildExit }
            $taskChangedText = if ($null -eq $taskInputsAfter) { 'not checked because record collection failed' } elseif ($taskInputsAfter.Digest -eq $taskInputs.Digest) { 'no' } else { "yes; post-build digest $($taskInputsAfter.Digest) (review generated/changed inputs before commit)" }
            $taskArtifactLines = if ($taskNewHaps.Count) { ($taskNewHaps | ForEach-Object { "| $($_.Path) | $($_.Bytes) | $($_.Sha256) |" }) -join "`n" } else { '| None confirmed for this attempt | - | - |' }
            $taskRecordText = @"
# HAP build $taskBuildId

- Result: $taskResult
- Start / end (UTC): $($taskStartedUtc.ToString('o')) / $($taskEndedUtc.ToString('o'))
- Command: flutter build hap --$Mode --target-platform $Target --target $DartTarget --no-codesign
- Input HEAD: $taskHead
- Controlled source manifest: [$taskManifestName]($taskManifestName)
- SHA-256 of manifest (UTF-8, LF): $($taskInputs.Digest)
- Source files in manifest: $($taskInputs.Count); includes uncommitted non-ignored app/tools/config inputs. Ignored caches, runtime data, signing material and Android reference source are excluded.
- Source changed during build: $taskChangedText
- Minimum OS / target / compile: HarmonyOS 6.1.0 (API 23) / API 23 / API 26; source configuration checked, packaged metadata not yet checked.
- Flutter-OH: $($taskToolchain.FlutterVersion), commit $($taskToolchain.FlutterCommit), engine $($taskToolchain.EngineCommit)
- Dart / DevEco / SDK: $($taskToolchain.DartVersion) / $($taskToolchain.DevEcoVersion) / $($taskToolchain.SdkVersion)
- Node / ohpm / Hvigor / Java: $taskNodeVersion / $taskOhpmVersion / $taskHvigorVersion / $taskJavaVersion
- Build process exit code: $taskExitText
- Wrapper collection error: $taskWrapperFailed
- Signing: disabled by --no-codesign; no signing identity claimed.
- Package metadata / ABI / signatures / installation / simulator / real-device functions: not checked by this wrapper.
- HarmonyOS 6.1 ARM64 real-device acceptance: not performed; G1 remains pending.
- Raw logs: ignored local-reports/builds/$taskRecordName/ (stdout.log, stderr.log; wrapper-error.txt if applicable).
- Diagnosis: inspect local logs, then add a reviewed, sanitized explanation here. Raw output is deliberately not copied into Git records.
- Local commit: REQUIRED and pending review. This wrapper does not stage or commit. Review source plus this record, explicitly stage relevant paths, run git diff --check and git diff --cached --check, review staged diff, then commit before another HAP attempt.

## New or updated HAP files in this attempt

| Repository-relative path | Bytes | SHA-256 |
| --- | ---: | --- |
$taskArtifactLines

An output hash does not establish package compatibility or device acceptance. Existing unchanged HAPs are omitted. This record identifies pre-build inputs; the final local commit also includes the record and must be found through git log after committing.
"@
            [IO.File]::WriteAllText($taskRecordPath, $taskRecordText.Replace("`r`n", "`n") + "`n", $taskUtf8)
            if ($null -ne $taskInputsAfter -and $taskInputsAfter.Digest -ne $taskInputs.Digest) {
                [IO.File]::WriteAllText((Join-Path $taskDocsRoot "$taskRecordName.after.inputs.sha256"), $taskInputsAfter.Text, $taskUtf8)
            }
        }
    }

    Write-Host "Review and locally commit the related source plus $taskRecordRelative and its input manifest before another HAP attempt."
    if ($taskWrapperFailed -or $null -eq $taskBuildExit -or $taskNewHaps.Count -eq 0) { exit 1 }
    exit $taskBuildExit
}
finally {
    Pop-Location
}
