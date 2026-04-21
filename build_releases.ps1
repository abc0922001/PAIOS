# build_releases.ps1

Write-Host "--- Starting PAIOS Build Process ---"

# 1. Parse version from pubspec.yaml
$VersionName = ""
$VersionCode = ""

$Content = Get-Content "pubspec.yaml"
foreach ($Line in $Content) {
    if ($Line -match "version:\s*([0-9\.]+)\+([0-9]+)") {
        $VersionName = $Matches[1]
        $VersionCode = $Matches[2]
        break
    }
}

if ($VersionName -eq "") {
    Write-Host "Error: Could not find version in pubspec.yaml"
    exit
}

Write-Host "Version: $VersionName"
Write-Host "Build: $VersionCode"

$Dest = "build"
if (-not (Test-Path $Dest)) {
    New-Item -ItemType Directory -Path $Dest
}

# 2. Build APK for GitHub
Write-Host "Step 1/2: Building APK (GitHub)..."
$ApkSuffix = "GitHub"
$FullApkName = "PAIOS_v" + $VersionName + "_" + $ApkSuffix + ".apk"
$BuildNameGit = $VersionName + "-" + $ApkSuffix

# Using spaces instead of = to ensure Flutter CLI parses correctly
flutter build apk --release --build-name $BuildNameGit --build-number $VersionCode

if ($LASTEXITCODE -eq 0) {
    $SourceApk = "build\app\outputs\flutter-apk\app-release.apk"
    Copy-Item $SourceApk ($Dest + "\" + $FullApkName) -Force
    Write-Host ("Saved APK to: " + $Dest + "\" + $FullApkName)
} else {
    Write-Host "APK Build Failed"
}

# 3. Build AAB for Play Store
Write-Host "Step 2/2: Building AAB (Play Store)..."
$AabSuffix = "PlayStore"
$FullAabName = "PAIOS_v" + $VersionName + "_" + $AabSuffix + ".aab"
$BuildNamePlay = $VersionName + "-" + $AabSuffix

flutter build appbundle --release --build-name $BuildNamePlay --build-number $VersionCode

if ($LASTEXITCODE -eq 0) {
    $SourceAab = "build\app\outputs\bundle\release\app-release.aab"
    Copy-Item $SourceAab ($Dest + "\" + $FullAabName) -Force
    Write-Host ("Saved AAB to: " + $Dest + "\" + $FullAabName)
} else {
    Write-Host "AAB Build Failed"
}

Write-Host "Done."
