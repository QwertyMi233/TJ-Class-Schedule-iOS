param(
    [Parameter(Mandatory = $true)][string]$FlutterSdk,
    [Parameter(Mandatory = $true)][string]$AndroidSdk,
    [Parameter(Mandatory = $true)][string]$JavaHome,
    [string]$ArtifactSuffix = ''
)
$ErrorActionPreference = 'Stop'
$taskSource = Split-Path -Parent $PSScriptRoot
$taskDart = Join-Path $FlutterSdk 'bin\cache\dart-sdk\bin\dart.exe'
$taskSnapshot = Join-Path $FlutterSdk 'bin\cache\flutter_tools.snapshot'
foreach ($taskFile in @($taskDart, $taskSnapshot, (Join-Path $JavaHome 'bin\java.exe'))) {
    if (!(Test-Path -LiteralPath $taskFile)) { throw "缺少构建工具：$taskFile" }
}
$taskStage = Join-Path ([IO.Path]::GetTempPath()) ('xunhui-build-' + [Guid]::NewGuid().ToString('N'))
if ($taskStage -match '[^\x00-\x7F]') { throw '临时目录需要使用 ASCII 路径。' }
New-Item -ItemType Directory -Path $taskStage | Out-Null
foreach ($taskItem in @('lib', 'test', 'assets', 'android', 'packages', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')) {
    Copy-Item -LiteralPath (Join-Path $taskSource $taskItem) -Destination $taskStage -Recurse
}
$taskArtifacts = Join-Path $taskSource 'artifacts'
New-Item -ItemType Directory -Force -Path $taskArtifacts | Out-Null
$env:FLUTTER_ROOT = $FlutterSdk
$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
$env:PATH = "$JavaHome\bin;$env:PATH"
Push-Location $taskStage
try {
    & $taskDart $taskSnapshot --no-version-check pub get --offline
    if ($LASTEXITCODE -ne 0) { throw '依赖解析失败，请先用正常 Flutter 环境下载依赖。' }
    & $taskDart $taskSnapshot --no-version-check analyze --no-pub *> (Join-Path $taskArtifacts 'verification-analyze.log')
    if ($LASTEXITCODE -ne 0) { throw '静态检查失败，请查看 artifacts 日志。' }
    & $taskDart $taskSnapshot --no-version-check test --no-pub --timeout 60s *> (Join-Path $taskArtifacts 'verification-tests.log')
    if ($LASTEXITCODE -ne 0) { throw '测试失败，请查看 artifacts 日志。' }
    $taskProxy = Join-Path $taskStage '.tooling\flutter-sdk'
    New-Item -ItemType Directory -Path (Join-Path $taskProxy 'bin') -Force | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $taskProxy 'bin\cache') -Target (Join-Path $FlutterSdk 'bin\cache') | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $taskProxy 'packages') -Target (Join-Path $FlutterSdk 'packages') | Out-Null
    $taskWrapper = @"
@echo off
set "FLUTTER_ROOT=$FlutterSdk"
"$taskDart" "$taskSnapshot" --no-version-check %*
"@
    Set-Content -LiteralPath (Join-Path $taskProxy 'bin\flutter.bat') -Value $taskWrapper -Encoding ascii
    $taskProxyProperty = $taskProxy.Replace('\', '\\')
    $taskAndroidProperty = $AndroidSdk.Replace('\', '\\')
    $taskVersion = (Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version: (.+)\+(.+)$').Matches[0]
    @"
flutter.sdk=$taskProxyProperty
sdk.dir=$taskAndroidProperty
flutter.buildMode=release
flutter.versionName=$($taskVersion.Groups[1].Value)
flutter.versionCode=$($taskVersion.Groups[2].Value)
"@ | Set-Content -LiteralPath 'android\local.properties' -Encoding ascii
    & .\android\gradlew.bat -p android --offline assembleRelease :app:testDebugUnitTest '-Ptarget-platform=android-arm64' '-Psplit-per-abi=true' '-Ptarget=lib/main.dart' *> (Join-Path $taskArtifacts 'verification-build.log')
    if ($LASTEXITCODE -ne 0) { throw 'APK 构建失败，请查看 artifacts 日志。' }
    if ($ArtifactSuffix -notmatch '^[A-Za-z0-9-]*$') { throw '安装包后缀格式无效。' }
    $taskApk = Join-Path $taskArtifacts "TJ-Class-Schedule-v$($taskVersion.Groups[1].Value)$ArtifactSuffix-arm64.apk"
    Copy-Item -LiteralPath 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk' -Destination $taskApk -Force
    if (Test-Path 'artifacts\preview-*.png') { Copy-Item -Path 'artifacts\preview-*.png' -Destination $taskArtifacts -Force }
    (Get-FileHash -LiteralPath $taskApk -Algorithm SHA256).Hash | Set-Content -LiteralPath "$taskApk.sha256.txt"
    Copy-Item -Path 'build\app\test-results\testDebugUnitTest\*.xml' -Destination $taskArtifacts -Force
    Write-Output "安装包：$taskApk"
    Write-Output "构建目录：$taskStage"
} finally { Pop-Location }
