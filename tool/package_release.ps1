<#
.SYNOPSIS
    Verifies Windows x64 and Android Release build outputs and packages PureRead release artifacts into dist\.
.DESCRIPTION
    Compatible with Windows PowerShell 5.1 and PowerShell 7+ (pwsh).
    Requires prior execution of:
      flutter build windows --release
      flutter build apk --release --split-per-abi   (or 'flutter build apk --release' for universal fallback)
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Test-AndroidReleaseApk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApkPath,
        [Parameter(Mandatory = $false)]
        [string]$ExpectedAbi
    )

    $requiredSoNames = @('libflutter.so', 'libapp.so', 'libsqlite3.so', 'libqjs_dart.so')
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
        $entries = @($zip.Entries)
        $entryNames = @($entries | ForEach-Object { $_.FullName })

        if (-not ($entryNames -contains 'AndroidManifest.xml')) {
            throw "APK '$ApkPath' is missing 'AndroidManifest.xml'."
        }

        $dexEntries = @($entryNames | Where-Object { $_ -match '^classes\d*\.dex$' } | Sort-Object)
        if ($dexEntries.Count -eq 0) {
            throw "APK '$ApkPath' contains no classes*.dex entries."
        }

        $allSoEntries = @($entries | Where-Object { $_.FullName -match '^lib/([^/]+)/([^/]+\.so)$' } | Sort-Object FullName)
        if ($allSoEntries.Count -eq 0) {
            throw "APK '$ApkPath' contains no native libraries under lib/*/."
        }

        $abis = @(
            $allSoEntries |
                ForEach-Object {
                    if ($_.FullName -match '^lib/([^/]+)/') { $Matches[1] }
                } |
                Sort-Object -Unique
        )

        if (-not [string]::IsNullOrWhiteSpace($ExpectedAbi)) {
            if (($abis.Count -ne 1) -or ($abis[0] -ne $ExpectedAbi)) {
                throw "Split APK '$ApkPath' expected only ABI '$ExpectedAbi', but found ABIs: $($abis -join ', ')."
            }
        }

        foreach ($soName in $requiredSoNames) {
            $pattern = "^lib/[^/]+/$([Regex]::Escape($soName))$"
            $matched = @($entryNames | Where-Object { $_ -match $pattern })
            if ($matched.Count -eq 0) {
                throw "APK '$ApkPath' is missing required native library 'lib/*/$soName'."
            }
        }

        foreach ($abi in $abis) {
            foreach ($soName in $requiredSoNames) {
                $expectedEntry = "lib/$abi/$soName"
                if (-not ($entryNames -contains $expectedEntry)) {
                    throw "APK '$ApkPath' ABI '$abi' is missing required native library '$expectedEntry'."
                }
            }
        }

        $apkItem = Get-Item -LiteralPath $ApkPath
        $apkMiB = [Math]::Round($apkItem.Length / 1MB, 2)

        Write-Host ''
        if ([string]::IsNullOrWhiteSpace($ExpectedAbi)) {
            Write-Host '--- Android Universal Release APK ---'
        } else {
            Write-Host "--- Android Split Release APK ($ExpectedAbi) ---"
        }
        Write-Host "APK Path        : $ApkPath"
        Write-Host "APK Size        : $($apkItem.Length) bytes ($apkMiB MiB)"
        Write-Host "DEX Entries     : $($dexEntries -join ', ')"
        Write-Host "ABIs Detected   : $($abis -join ', ')"
        Write-Host 'Native Libraries:'
        foreach ($soEntry in $allSoEntries) {
            $soSizeKiB = [Math]::Round($soEntry.Length / 1KB, 1)
            Write-Host ("  - {0} ({1} bytes, {2} KiB)" -f $soEntry.FullName, $soEntry.Length, $soSizeKiB)
        }

        return [pscustomobject]@{
            ApkPath   = $ApkPath
            SizeBytes = $apkItem.Length
            SizeMiB   = $apkMiB
            Abis      = $abis
        }
    }
    finally {
        if ($null -ne $zip) {
            $zip.Dispose()
        }
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$winReleaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$winExePath = Join-Path $winReleaseDir 'pureread.exe'
$apkOutputDir = Join-Path $repoRoot 'build\app\outputs\flutter-apk'
$universalApkPath = Join-Path $apkOutputDir 'app-release.apk'
$mappingPath = Join-Path $repoRoot 'build\app\outputs\mapping\release\mapping.txt'

Write-Host '=== PureRead Release Packaging & Verification ==='
Write-Host "Repo root: $repoRoot"

# 1. Require Windows release input and resolve Android release APKs (split-per-abi preferred, universal fallback)
if (-not (Test-Path -LiteralPath $winExePath -PathType Leaf)) {
    throw "Missing Windows release executable: '$winExePath'. Run 'flutter build windows --release' first."
}

$splitAbis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
$splitSpecs = @(
    foreach ($abi in $splitAbis) {
        $sourceApk = Join-Path $apkOutputDir ("app-{0}-release.apk" -f $abi)
        [pscustomobject]@{
            Abi        = $abi
            SourcePath = $sourceApk
            DistName   = ("pureread-android-{0}.apk" -f $abi)
            Exists     = (Test-Path -LiteralPath $sourceApk -PathType Leaf)
        }
    }
)
$presentSplits = @($splitSpecs | Where-Object { $_.Exists })
$missingSplits = @($splitSpecs | Where-Object { -not $_.Exists })

$apkMode = $null
$apkTargets = @()
if ($presentSplits.Count -eq $splitSpecs.Count) {
    $apkMode = 'split-per-abi'
    $apkTargets = $presentSplits
} elseif ($presentSplits.Count -gt 0) {
    $missingNames = @($missingSplits | ForEach-Object { Split-Path -Leaf $_.SourcePath })
    throw ("Incomplete split-per-abi APK outputs in '$apkOutputDir'. Missing: " + ($missingNames -join ', ') + ". Run 'flutter build apk --release --split-per-abi'.")
} elseif (Test-Path -LiteralPath $universalApkPath -PathType Leaf) {
    $apkMode = 'universal-fallback'
    $apkTargets = @(
        [pscustomobject]@{
            Abi        = $null
            SourcePath = $universalApkPath
            DistName   = 'pureread-android-release.apk'
            Exists     = $true
        }
    )
} else {
    throw "Missing Android release APKs in '$apkOutputDir'. Run 'flutter build apk --release --split-per-abi' (or 'flutter build apk --release' for universal APK)."
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

# 3. Verify R8 mapping.txt and each Android release APK
if (-not (Test-Path -LiteralPath $mappingPath -PathType Leaf)) {
    throw "Missing R8 mapping file: '$mappingPath'. Ensure R8 minification (isMinifyEnabled = true) ran during the Android release build."
}
$mappingItem = Get-Item -LiteralPath $mappingPath
if ($mappingItem.Length -le 0) {
    throw "R8 mapping file is empty: '$mappingPath'."
}

Write-Host ''
Write-Host '--- Android Release Mode & R8 Mapping ---'
Write-Host "Packaging Mode  : $apkMode"
Write-Host "Mapping Path    : $mappingPath"
Write-Host "Mapping Size    : $($mappingItem.Length) bytes"

foreach ($target in $apkTargets) {
    $null = Test-AndroidReleaseApk -ApkPath $target.SourcePath -ExpectedAbi $target.Abi
}

# 4. Package into dist\ and write SHA256SUMS.txt
$distDir = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

# Clear stale packaged Android APKs so universal/split outputs do not mix in dist\
Get-ChildItem -LiteralPath $distDir -Filter 'pureread-android-*.apk' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force

$distWinZip = Join-Path $distDir 'pureread-windows-x64.zip'
$sumsFile = Join-Path $distDir 'SHA256SUMS.txt'

Compress-Archive -Path (Join-Path $winReleaseDir '*') -DestinationPath $distWinZip -CompressionLevel Optimal -Force

$distArtifactList = New-Object System.Collections.Generic.List[System.IO.FileInfo]
$distArtifactList.Add((Get-Item -LiteralPath $distWinZip))

foreach ($target in $apkTargets) {
    $destApkPath = Join-Path $distDir $target.DistName
    Copy-Item -LiteralPath $target.SourcePath -Destination $destApkPath -Force
    $distArtifactList.Add((Get-Item -LiteralPath $destApkPath))
}

$sumLines = New-Object System.Collections.Generic.List[string]
foreach ($artifact in $distArtifactList) {
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
