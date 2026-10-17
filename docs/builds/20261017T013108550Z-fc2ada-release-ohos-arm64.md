# HAP build 20261017T013108550Z-fc2ada

- Result: Release HAP built; ARM64 application ELF and packaged metadata verified; delivered unsigned for manual device testing
- Start / end (UTC): 2026-10-17T01:31:11.4676608+00:00 / 2026-10-17T01:32:10.9780260+00:00
- Command: flutter build hap --release --target-platform ohos-arm64 --target lib/main.dart --no-codesign
- Input HEAD: 49fc14073ccd9fa4b11b0feeb6af7b9233bcddf7
- Controlled source manifest: [20261017T013108550Z-fc2ada-release-ohos-arm64.inputs.sha256](20261017T013108550Z-fc2ada-release-ohos-arm64.inputs.sha256)
- SHA-256 of manifest (UTF-8, LF): ea20a156a0a4850f4d0257cac0d2ee429498caab610c7afcef3bd095c7fdd704
- Source files in manifest: 1204; includes uncommitted non-ignored app/tools/config inputs. Ignored caches, runtime data, signing material and Android reference source are excluded.
- Source changed during build: yes; post-build digest b0e10131cf7d5845c555b5d92ffcde196958975d7367f40566b4c4d890da1466 (review generated/changed inputs before commit)
- Minimum OS / target / compile: HarmonyOS 6.1.0 (API 23) / API 23 / API 26; packaged min/target 60100023 and compile 26.0.0.105 verified.
- Flutter-OH: 3.44.9+ohos-0.0.1-canary1, commit 39285df71a97ffe0c23241dcc459d997a9d8b7c6, engine 5a2a6a42cce67f965cf540fcecf616faca624aa1
- Dart / DevEco / SDK: 3.12.2 / 26.0.0.851 / 26.0.0.105
- Node / ohpm / Hvigor / Java: v24.14.1 / 26.0.0.630 / 6.26.8 / 25.0.2
- Build process exit code: 0
- Wrapper collection error: False
- Signing: disabled by --no-codesign; no signing identity claimed.
- Package metadata / ABI / signatures / installation / simulator / real-device functions: not checked by this wrapper.
- HarmonyOS 6.1 ARM64 real-device acceptance: not performed; G1 remains pending.
- Raw logs: ignored local-reports/builds/20261017T013108550Z-fc2ada-release-ohos-arm64/ (stdout.log, stderr.log; wrapper-error.txt if applicable).
- Diagnosis: Normal lib/main.dart release/AOT build from playback repair 49fc140. Package version 1.0.120+125, debug=false. ARM64 libapp/libflutter/libfqplayer/libfqapi_core ELF machine 183 verified. Package also retains x86_64 vendor/core/player libraries because the native build configuration includes both ABIs; it contains no x86_64 Flutter engine/application and is delivered for ARM64 use only. OHPM changed exactly two lockfiles to the same pinned engine's ARM64 release HAR. Delivered local-reports/delivery/fqapp-1.0.120-20261017-playback-fix-arm64-release-unsigned.hap (104889617 bytes), SHA256 c197b3640df0804007ae44d5b8faed879eb5544483d2fa925d352af33a522d4a. Signing configuration is absent; device installation requires matching developer signature/profile. Manual device testing is assigned to the user. No physical-device acceptance or publication claimed.
- Local commit: Reviewed release lockfile changes, input manifests, this record and delivery/acceptance documentation together; see git log for the resulting local commit.

## New or updated HAP files in this attempt

| Repository-relative path | Bytes | SHA-256 |
| --- | ---: | --- |
| app/build/ohos/hap/entry-default-unsigned.hap | 104889617 | c197b3640df0804007ae44d5b8faed879eb5544483d2fa925d352af33a522d4a |
| app/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap | 104889617 | c197b3640df0804007ae44d5b8faed879eb5544483d2fa925d352af33a522d4a |

An output hash does not establish package compatibility or device acceptance. Existing unchanged HAPs are omitted. This record identifies pre-build inputs; the final local commit also includes the record and must be found through git log after committing.
