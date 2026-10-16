#requires -Version 7.0
param([ValidateSet('ohos-arm64','ohos-x64')][string]$Target='ohos-arm64')
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'environment.ps1') | Out-Null
$env:RUSTUP_HOME='E:\Codex-bulid\toolchains\fq-rustup'
$env:CARGO_HOME='E:\Codex-bulid\toolchains\fq-cargo'
$env:Path=$env:CARGO_HOME+'\bin;'+$env:Path
$taskVersion=(& rustc.exe +stable -V | Out-String).Trim()
if($LASTEXITCODE -ne 0 -or $taskVersion -ne 'rustc 1.99.1 (58cf8f9c3 2026-10-13)') {
    throw 'Rust toolchain mismatch: expected 1.99.1 (58cf8f9c3). Install the locked version first.'
}
$taskRustTarget=if($Target -eq 'ohos-arm64'){'aarch64-unknown-linux-ohos'}else{'x86_64-unknown-linux-ohos'}
$taskAbi=if($Target -eq 'ohos-arm64'){'arm64-v8a'}else{'x86_64'}
$taskClangTarget=if($Target -eq 'ohos-arm64'){'aarch64-linux-ohos'}else{'x86_64-linux-ohos'}
$taskEnvTarget=$taskRustTarget.Replace('-','_')
$taskClang=Join-Path $env:OHOS_NDK_HOME 'llvm/bin/clang.exe'
$taskAr=Join-Path $env:OHOS_NDK_HOME 'llvm/bin/llvm-ar.exe'
$taskSysroot=($env:OHOS_NDK_HOME+'/sysroot').Replace('\','/')
[Environment]::SetEnvironmentVariable('CARGO_TARGET_'+$taskEnvTarget.ToUpperInvariant()+'_LINKER',$taskClang,'Process')
[Environment]::SetEnvironmentVariable('CC_'+$taskEnvTarget,$taskClang,'Process')
[Environment]::SetEnvironmentVariable('AR_'+$taskEnvTarget,$taskAr,'Process')
[Environment]::SetEnvironmentVariable('CFLAGS_'+$taskEnvTarget,'--target='+$taskClangTarget+' --sysroot="'+$taskSysroot+'" -D__MUSL__','Process')
$env:CC_SHELL_ESCAPED_FLAGS='1'
$env:CARGO_ENCODED_RUSTFLAGS=@('-C',('link-arg=--target='+$taskClangTarget),'-C',('link-arg=--sysroot='+$taskSysroot)) -join [char]31
$taskRustRoot=Join-Path $taskRoot 'app/rust'
$taskSources=@(Get-ChildItem (Join-Path $taskRustRoot 'src'),(Join-Path $taskRustRoot 'assets') -Recurse -File)
$taskSources+=Get-Item (Join-Path $taskRustRoot 'Cargo.toml'),(Join-Path $taskRustRoot 'Cargo.lock'),(Join-Path $taskRustRoot 'build.rs')
$taskSources+=Get-ChildItem (Join-Path $taskRoot 'app/native/crypto_core'),(Join-Path $taskRoot 'app/native/third_party/tiny_aes') -Recurse -File
$taskManifest=(@($taskSources | Sort-Object FullName | ForEach-Object {
    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetRelativePath($taskRoot,$_.FullName).Replace('\','/')
}) -join "`n")+"`n"
$taskDigest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($taskManifest))).ToLowerInvariant()
$taskLocal=Join-Path $taskRoot 'local-reports/native'
New-Item -ItemType Directory -Force $taskLocal | Out-Null
& cargo.exe +stable build --manifest-path (Join-Path $taskRustRoot 'Cargo.toml') --locked --release --target $taskRustTarget
if($LASTEXITCODE -ne 0){throw 'Rust build failed; no native library was copied.'}
$taskLibrary=Join-Path $taskRustRoot "target/$taskRustTarget/release/libfqapi_core.so"
$taskDestination=Join-Path $taskRoot "app/ohos/entry/libs/$taskAbi"
New-Item -ItemType Directory -Force $taskDestination | Out-Null
Copy-Item -LiteralPath $taskLibrary -Destination $taskDestination -Force
$taskReport=[ordered]@{target=$Target;rustTarget=$taskRustTarget;rustVersion=$taskVersion;sourceDigest=$taskDigest;librarySha256=(Get-FileHash $taskLibrary -Algorithm SHA256).Hash.ToLowerInvariant();builtAtUtc=[DateTime]::UtcNow.ToString('o')}
[IO.File]::WriteAllText((Join-Path $taskLocal "$Target.json"),($taskReport|ConvertTo-Json)+"`n",[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $taskLocal "$Target.inputs.sha256"),$taskManifest,[Text.UTF8Encoding]::new($false))
Write-Host "Built $Target from source digest $taskDigest; native receipt is in ignored local-reports/native."
