<#
.SYNOPSIS
    Verifies Windows x64 and Android Release build outputs and packages PureRead release artifacts into dist\.
.DESCRIPTION
    Compatible with Windows PowerShell 5.1 and PowerShell 7+ (pwsh).
    Requires prior execution of:
      flutter build windows --release
      flutter build apk --release
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$winReleaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$winExePath = Join-Path $winReleaseDir 'pureread.exe'
$apkPath = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
$mappingPath = Join-Path $repoRoot 'build\app\outputs\mapping\release\mapping.txt'

Write-Host '=== PureRead Release Packaging & Verification ==='
Write-Host "Repo root: $repoRoot"

# 1. Require top-level Windows and Android release inputs
if (-not (Test-Path -LiteralPath $winExePath -PathType Leaf)) {
    throw "Missing Windows release executable: '$winExePath'. Run 'flutter build windows --release' first."
}
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "Missing Android release APK: '$apkPath'. Run 'flutter build apk --release' first."
}

# 2. Verify Windows Release bundle artifacts
$requiredWinFiles = @(
    'pureread.exe',
    'flutter_windows.dll',
    'qjs_dart.dll',
    'sqlite3.dll',
    'dartjni.dll',
    'data\app.so',
    'data\icudtl.dat'
)

$missingWinArtifacts = New-Object System.Collections.Generic.List[string]
foreach ($relPath in $requiredWinFiles) {
    $fullPath = Join-Path $winReleaseDir $relPath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $missingWinArtifacts.Add($relPath)
    }
}

$flutterAssetsDir = Join-Path $winReleaseDir 'data\flutter_assets'
if (-not (Test-Path -LiteralPath $flutterAssetsDir -PathType Container)) {
    $missingWinArtifacts.Add('data\flutter_assets (directory)')
} else {
    $assetCount = (Get-ChildItem -LiteralPath $flutterAssetsDir -Recurse -File | Measure-Object).Count
    if ($assetCount -eq 0) {
        $missingWinArtifacts.Add('data\flutter_assets (empty)')
    }
}

if ($missingWinArtifacts.Count -gt 0) {
    throw ("Missing Windows release artifacts in '$winReleaseDir': " + ($missingWinArtifacts -join ', '))
}

$winExeItem = Get-Item -LiteralPath $winExePath
$verInfo = $winExeItem.VersionInfo
$winBundleStats = Get-ChildItem -LiteralPath $winReleaseDir -Recurse -File | Measure-Object -Property Length -Sum
$winBundleBytes = [int64]$winBundleStats.Sum
$winBundleMiB = [Math]::Round($winBundleBytes / 1MB, 2)

Write-Host ''
Write-Host '--- Windows x64 Release Bundle ---'
Write-Host "Executable      : $winExePath"
Write-Host "ProductName     : $($verInfo.ProductName)"
Write-Host "FileDescription : $($verInfo.FileDescription)"
Write-Host "CompanyName     : $($verInfo.CompanyName)"
Write-Host "FileVersion     : $($verInfo.FileVersion)"
Write-Host "ProductVersion  : $($verInfo.ProductVersion)"
Write-Host "LegalCopyright  : $($verInfo.LegalCopyright)"
Write-Host "OriginalFilename: $($verInfo.OriginalFilename)"
Write-Host "Bundle Files    : $($winBundleStats.Count)"
Write-Host "Bundle Size     : $winBundleBytes bytes ($winBundleMiB MiB)"

# 3. Verify Android APK entries and R8 mapping.txt
if (-not (Test-Path -LiteralPath $mappingPath -PathType Leaf)) {
    throw "Missing R8 mapping file: '$mappingPath'. Ensure R8 minification (isMinifyEnabled = true) ran during 'flutter build apk --release'."
}
$mappingItem = Get-Item -LiteralPath $mappingPath
if ($mappingItem.Length -le 0) {
    throw "R8 mapping file is empty: '$mappingPath'."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = $null
try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
    $entries = @($zip.Entries)
    $entryNames = @($entries | ForEach-Object { $_.FullName })

    if (-not ($entryNames -contains 'AndroidManifest.xml')) {
        throw "APK '$apkPath' is missing 'AndroidManifest.xml'."
    }

    $dexEntries = @($entryNames | Where-Object { $_ -match '^classes\d*\.dex$' } | Sort-Object)
    if ($dexEntries.Count -eq 0) {
        throw "APK '$apkPath' contains no classes*.dex entries."
    }

    $requiredSoNames = @('libflutter.so', 'libapp.so', 'libsqlite3.so', 'libqjs_dart.so')
    $allSoEntries = @($entries | Where-Object { $_.FullName -match '^lib/([^/]+)/([^/]+\.so)$' } | Sort-Object FullName)
    if ($allSoEntries.Count -eq 0) {
        throw "APK '$apkPath' contains no native libraries under lib/*/."
    }

    $abis = @(
        $allSoEntries |
            ForEach-Object {
                if ($_.FullName -match '^lib/([^/]+)/') { $Matches[1] }
            } |
            Sort-Object -Unique
    )

    foreach ($soName in $requiredSoNames) {
        $pattern = "^lib/[^/]+/$([Regex]::Escape($soName))$"
        $matched = @($entryNames | Where-Object { $_ -match $pattern })
        if ($matched.Count -eq 0) {
            throw "APK '$apkPath' is missing required native library 'lib/*/$soName'."
        }
    }

    foreach ($abi in $abis) {
        foreach ($soName in $requiredSoNames) {
            $expectedEntry = "lib/$abi/$soName"
            if (-not ($entryNames -contains $expectedEntry)) {
                throw "APK '$apkPath' ABI '$abi' is missing required native library '$expectedEntry'."
            }
        }
    }

    $apkItem = Get-Item -LiteralPath $apkPath
    $apkMiB = [Math]::Round($apkItem.Length / 1MB, 2)

    Write-Host ''
    Write-Host '--- Android Release APK & R8 Mapping ---'
    Write-Host "APK Path        : $apkPath"
    Write-Host "APK Size        : $($apkItem.Length) bytes ($apkMiB MiB)"
    Write-Host "Mapping Path    : $mappingPath"
    Write-Host "Mapping Size    : $($mappingItem.Length) bytes"
    Write-Host "DEX Entries     : $($dexEntries -join ', ')"
    Write-Host "ABIs Detected   : $($abis -join ', ')"
    Write-Host 'Native Libraries:'
    foreach ($soEntry in $allSoEntries) {
        $soSizeKiB = [Math]::Round($soEntry.Length / 1KB, 1)
        Write-Host ("  - {0} ({1} bytes, {2} KiB)" -f $soEntry.FullName, $soEntry.Length, $soSizeKiB)
    }
}
finally {
    if ($null -ne $zip) {
        $zip.Dispose()
    }
}

# 4. Package into dist\ and write SHA256SUMS.txt
$distDir = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

$distWinZip = Join-Path $distDir 'pureread-windows-x64.zip'
$distApk = Join-Path $distDir 'pureread-android-release.apk'
$sumsFile = Join-Path $distDir 'SHA256SUMS.txt'

Compress-Archive -Path (Join-Path $winReleaseDir '*') -DestinationPath $distWinZip -CompressionLevel Optimal -Force
Copy-Item -LiteralPath $apkPath -Destination $distApk -Force

$distArtifacts = @(
    (Get-Item -LiteralPath $distWinZip),
    (Get-Item -LiteralPath $distApk)
)

$sumLines = New-Object System.Collections.Generic.List[string]
foreach ($artifact in $distArtifacts) {
    $hash = (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $sizeBytes = $artifact.Length
    $sizeMiB = [Math]::Round($sizeBytes / 1MB, 2)
    $sumLines.Add(('{0}  {1}  ({2} bytes, {3} MiB)' -f $hash, $artifact.Name, $sizeBytes, $sizeMiB))
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($sumsFile, $sumLines, $utf8NoBom)

Write-Host ''
Write-Host '--- Packaged Artifacts (dist\) ---'
foreach ($line in $sumLines) {
    Write-Host $line
}
Write-Host "Checksums file  : $sumsFile"
