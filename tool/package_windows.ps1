# Builds dist\zaevis-<version>-win-x64.exe: an installer. The app is zaevis.exe plus a zaevis\ folder
# (Node, server, MinSync, web). A lone exe cannot carry those, so the download is an installer.
# Everything the app needs at runtime is inside (Node runtime, server, MinSync, web build, CLI).
#
#   powershell -ExecutionPolicy Bypass -File tool\package_windows.ps1 [-SkipMinsync]
#
# Needs on THIS (build) machine only: Flutter (with Visual Studio "Desktop development with C++"),
# Rust (cargo) + protobuf + cmake for MinSync (or -SkipMinsync for keyword-only search).
param([switch]$SkipMinsync)
$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Build = Join-Path $Root "build\package-win"
$Dist = Join-Path $Root "dist"
$NodeMajor = 24
$Version = (Select-String -Path (Join-Path $Root "app\pubspec.yaml") -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$Payload = Join-Path $Build "payload"

function Say($m) { Write-Host "> $m" -ForegroundColor Cyan }
function Need($cmd, $hint) { if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "$cmd 가 필요합니다: $hint" } }

Need flutter "https://docs.flutter.dev/get-started/install/windows"
if (-not $SkipMinsync) {
  Need cargo "https://rustup.rs"
  Need protoc "winget install protobuf (또는 choco install protoc)"
  Need cmake "winget install Kitware.CMake"
}

Remove-Item -Recurse -Force $Payload -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$Payload\bin", "$Payload\node", "$Build\cache", $Dist | Out-Null

# -- 1) Node runtime (official build, checksum-verified, cached) ---------------------------------
Say "Node $NodeMajor (win-x64)"
$Sums = Join-Path $Build "cache\SHASUMS256-v$NodeMajor.txt"
Invoke-WebRequest "https://nodejs.org/dist/latest-v$NodeMajor.x/SHASUMS256.txt" -OutFile $Sums
$Zip = (Select-String -Path $Sums -Pattern 'node-v[0-9.]+-win-x64\.zip').Matches[0].Value
$ZipPath = Join-Path $Build "cache\$Zip"
if (-not (Test-Path $ZipPath)) { Invoke-WebRequest "https://nodejs.org/dist/latest-v$NodeMajor.x/$Zip" -OutFile $ZipPath }
$Expected = ((Select-String -Path $Sums -Pattern " $([regex]::Escape($Zip))$").Line -split '\s+')[0]
$Actual = (Get-FileHash $ZipPath -Algorithm SHA256).Hash.ToLower()
if ($Actual -ne $Expected) { throw "Node 체크섬이 맞지 않습니다." }
$NodeDir = Join-Path $Build "cache\$($Zip -replace '\.zip$','')"
if (-not (Test-Path $NodeDir)) { Expand-Archive $ZipPath -DestinationPath (Join-Path $Build "cache") }
Copy-Item "$NodeDir\node.exe" "$Payload\node\node.exe"
Copy-Item "$NodeDir\LICENSE" "$Payload\node\LICENSE"
$Npm = "$NodeDir\npm.cmd"

# -- 2) server with production dependencies -------------------------------------------------------
Say "서버"
New-Item -ItemType Directory -Force -Path "$Payload\server" | Out-Null
Copy-Item -Recurse "$Root\server\src" "$Payload\server\src"
Copy-Item "$Root\server\package.json", "$Root\server\package-lock.json" "$Payload\server\"
Push-Location "$Payload\server"
$env:PATH = "$NodeDir;$env:PATH"
& $Npm ci --omit=dev --no-fund --no-audit --silent
Pop-Location
Get-ChildItem -Recurse -File "$Payload\server\node_modules" -Include *.map, *.d.ts, *.d.mts, *.d.cts, README.md, CHANGELOG.md, HISTORY.md | Remove-Item -Force
& "$NodeDir\node.exe" "$Root\tool\prune_modules.mjs" "$Payload\server\node_modules" win32 x64
if ($LASTEXITCODE -ne 0) { throw "설치 파일에서 불필요한 실행 파일을 지우지 못했습니다." }

# -- 3) MinSync (AutoRAG embedding engine; Rust build, cached) -----------------------------------
if (-not $SkipMinsync) {
  Say "MinSync (처음 한 번은 수 분)"
  $MinsyncBin = Join-Path $Build "cache\minsync\bin\minsync.exe"
  if (-not (Test-Path $MinsyncBin)) { cargo install minsync --locked --root (Join-Path $Build "cache\minsync") }
  Copy-Item $MinsyncBin "$Payload\bin\minsync.exe"
}

# -- 4) CLI, kit ----------------------------------------------------------------------------------
Copy-Item "$Root\bin\zaevis.cmd" "$Payload\bin\zaevis.cmd"
Copy-Item "$Root\bin\zaevis" "$Payload\bin\zaevis"
Copy-Item -Recurse "$Root\kit" "$Payload\kit"
$BuildId = if ($env:ZAEVIS_BUILD) { $env:ZAEVIS_BUILD } else { [DateTime]::UtcNow.ToString('yyyyMMddHHmmss') }
"$Version+$BuildId" | Set-Content -NoNewline "$Payload\VERSION"

# -- 5) Flutter: web (served by the bundled server) + Windows app ----------------------------------
Say "Flutter 빌드"
Push-Location "$Root\app"
if (-not (Test-Path "web")) { flutter create --platforms=web --project-name zaevis --org io.github.zaepark . | Out-Null }
if (-not (Test-Path "windows")) { flutter create --platforms=windows --project-name zaevis --org io.github.zaepark . | Out-Null }
flutter pub get
flutter build web --release
Copy-Item -Recurse "build\web" "$Payload\web"
flutter build windows --release
$AppSrc = "build\windows\x64\runner\Release"
if (-not (Test-Path "$AppSrc\zaevis.exe")) { throw "Windows 빌드 결과가 없습니다: $AppSrc" }
Pop-Location

# -- 6) assemble: zaevis.exe + its DLLs, with the payload in zaevis\ next to it ---------------------
Say "폴더 합치기"
$Stage = Join-Path $Build "stage\zaevis-$Version"
Remove-Item -Recurse -Force (Join-Path $Build "stage") -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item -Recurse "$Root\app\$AppSrc\*" $Stage
Copy-Item -Recurse $Payload "$Stage\zaevis"
$Iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $Iscc)) { throw "Inno Setup이 필요합니다: choco install innosetup" }
$ExeOut = Join-Path $Dist "zaevis-$Version-win-x64.exe"
Remove-Item $ExeOut -ErrorAction SilentlyContinue
& $Iscc "/DAppVersion=$Version" "/DStage=$Stage" "/DOutputDir=$Dist" (Join-Path $PSScriptRoot "zaevis.iss")
if (-not (Test-Path $ExeOut)) { throw "설치 exe가 없습니다: $ExeOut" }
Say "완료: $ExeOut ($([math]::Round((Get-Item $ExeOut).Length / 1MB)) MB)"
