$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$FfmpegVersion = "8.1.2"
$FfmpegTag = "n8.1.2"
$FfmpegTagObject = "1c2c67c0b9f7f66ab32c19dcf7f227bcd290aa4c"
$FfmpegCommit = "38b88335f99e76ed89ff3c93f877fdefce736c13"
$FfmpegRepository = "https://github.com/FFmpeg/FFmpeg.git"

$NvCodecHeadersTag = "n13.0.19.0"
$NvCodecHeadersCommit = "e844e5b26f46bb77479f063029595293aa8f812d"
$NvCodecHeadersRepository = "https://git.videolan.org/git/ffmpeg/nv-codec-headers.git"

$Dav1dVersion = "1.5.1"
$Dav1dTag = "1.5.1"
$Dav1dCommit = "42b2b24fb8819f1ed3643aa9cf2a62f03868e3aa"
$Dav1dRepository = "https://code.videolan.org/videolan/dav1d.git"

$PackageNotice = "FFmpeg libraries built by KawaiiEngine for WebMiere - licensed under LGPL v3 or later."
$ExpectedLicense = "LGPL version 3 or later"
$ExpectedDlls = @(
    "avcodec-62.dll",
    "avformat-62.dll",
    "avutil-60.dll",
    "swscale-9.dll",
    "swresample-6.dll"
)
$ExpectedImportLibs = @(
    "avcodec.lib",
    "avformat.lib",
    "avutil.lib",
    "swscale.lib",
    "swresample.lib"
)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$WorkRoot = Join-Path $RepoRoot "build\ffmpeg-webmiere"
$SourceRoot = Join-Path $WorkRoot "src"
$BuildRoot = Join-Path $WorkRoot "build"
$InstallRoot = Join-Path $WorkRoot "install"
$DepsRoot = Join-Path $WorkRoot "deps"
$PackageRoot = Join-Path $WorkRoot "package"
$ProbeBuildRoot = Join-Path $WorkRoot "probe"
$ComplianceRoot = Join-Path $WorkRoot "compliance"
$ArtifactsRoot = Join-Path $RepoRoot "artifacts"

$FfmpegSourceDir = Join-Path $SourceRoot "ffmpeg"
$NvCodecHeadersSourceDir = Join-Path $SourceRoot "nv-codec-headers"
$Dav1dSourceDir = Join-Path $SourceRoot "dav1d"
$FfmpegBuildDir = Join-Path $BuildRoot "ffmpeg"
$Dav1dBuildDir = Join-Path $BuildRoot "dav1d"
$NvCodecHeadersPrefix = Join-Path $DepsRoot "ffnvcodec"
$Dav1dPrefix = Join-Path $DepsRoot "dav1d"
$Dav1dMesonNativeFile = Join-Path $BuildRoot "dav1d-msvc-native.ini"

$RuntimePackageRoot = Join-Path $PackageRoot "runtime"
$DevelopmentPackageRoot = Join-Path $PackageRoot "dev"
$ConfigureCommandFile = Join-Path $ComplianceRoot "ffmpeg-configure.txt"
$ConfigureOutputFile = Join-Path $ComplianceRoot "ffmpeg-configure-output.txt"
$BuildInfoFile = Join-Path $ComplianceRoot "FFmpeg-BUILD-INFO.txt"
$SourceInfoFile = Join-Path $ComplianceRoot "FFmpeg-SOURCE.txt"
$ChangesDiffFile = Join-Path $ComplianceRoot "ffmpeg-changes.diff"
$RuntimeReportFile = Join-Path $ComplianceRoot "ffmpeg-runtime-report.txt"
$RuntimeProbeFile = Join-Path $ComplianceRoot "ffmpeg-runtime-probe.txt"
$LgplFile = Join-Path $ComplianceRoot "COPYING.LGPLv3"
$GplFile = Join-Path $ComplianceRoot "COPYING.GPLv3"
$Dav1dLicenseFile = Join-Path $ComplianceRoot "COPYING.dav1d"
$SourceArchiveRoot = Join-Path $ComplianceRoot "source"
$FfmpegSourceArchive = Join-Path $SourceArchiveRoot "ffmpeg-$FfmpegVersion-$FfmpegCommit.tar.gz"
$NvCodecHeadersSourceArchive = Join-Path $SourceArchiveRoot "nv-codec-headers-$NvCodecHeadersCommit.tar.gz"
$Dav1dSourceArchive = Join-Path $SourceArchiveRoot "dav1d-$Dav1dVersion-$Dav1dCommit.tar.gz"
$ArtifactChecksumFile = Join-Path $ArtifactsRoot "SHA256SUMS.txt"
$ProbeSourceFile = Join-Path $PSScriptRoot "ffmpeg-runtime-probe.c"
$script:MsvcPathMsys = ""
$script:MsvcToolPathMsys = ""

function Write-Step {
    param([string] $Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [string[]] $ArgumentList = @(),
        [string] $WorkingDirectory = (Get-Location).Path
    )

    Push-Location $WorkingDirectory
    try {
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath exited with code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

function Get-NativeOutput {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [string[]] $ArgumentList = @(),
        [string] $WorkingDirectory = (Get-Location).Path
    )

    Push-Location $WorkingDirectory
    try {
        $output = & $FilePath @ArgumentList 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath exited with code $LASTEXITCODE`n$($output -join "`n")"
        }
        return ($output -join "`n")
    } finally {
        Pop-Location
    }
}

function Get-NativeOutputAllowFailure {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [string[]] $ArgumentList = @(),
        [string] $WorkingDirectory = (Get-Location).Path
    )

    Push-Location $WorkingDirectory
    try {
        $output = & $FilePath @ArgumentList 2>&1
        return ($output -join "`n")
    } finally {
        Pop-Location
    }
}

function Quote-Bash {
    param([string] $Value)
    return "'" + $Value.Replace("'", "'\''") + "'"
}

function Get-MsysCommand {
    param([string] $Command)
    $pathPrefix = "/usr/bin:/mingw64/bin"
    if ($script:MsvcToolPathMsys) {
        $pathPrefix = "/mingw64/bin`:$script:MsvcToolPathMsys`:/usr/bin`:$script:MsvcPathMsys"
    } elseif ($script:MsvcPathMsys) {
        $pathPrefix = "/mingw64/bin`:$script:MsvcPathMsys`:/usr/bin"
    }
    return "export PATH=$(Quote-Bash $pathPrefix)`:`$PATH; " + $Command
}

function Convert-ToMsysPath {
    param([string] $Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $pathForBash = $fullPath.Replace("\", "/")
    $converted = Get-NativeOutput -FilePath $script:BashPath -ArgumentList @("-c", (Get-MsysCommand "/usr/bin/cygpath -u $(Quote-Bash $pathForBash)"))
    return $converted.Trim()
}

function Invoke-Bash {
    param([Parameter(Mandatory = $true)][string] $Command)
    Invoke-Native -FilePath $script:BashPath -ArgumentList @("-c", (Get-MsysCommand $Command))
}

function Get-BashOutput {
    param([Parameter(Mandatory = $true)][string] $Command)
    return Get-NativeOutput -FilePath $script:BashPath -ArgumentList @("-c", (Get-MsysCommand $Command))
}

function Convert-WindowsPathListToMsys {
    param([string] $PathList)

    $converted = New-Object System.Collections.Generic.List[string]
    foreach ($entry in ($PathList -split ";")) {
        $trimmed = $entry.Trim().Trim('"')
        if (-not $trimmed) {
            continue
        }
        if (-not (Test-Path $trimmed)) {
            continue
        }

        $converted.Add((Convert-ToMsysPath $trimmed))
    }

    return (($converted | Select-Object -Unique) -join ":")
}

function Find-MsysBash {
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($env:MSYS2_LOCATION) {
        $candidates.Add((Join-Path $env:MSYS2_LOCATION "usr\bin\bash.exe"))
    }

    if ($env:MSYS2_ROOT_WIN) {
        $candidates.Add((Join-Path $env:MSYS2_ROOT_WIN "usr\bin\bash.exe"))
    }

    foreach ($command in (Get-Command bash.exe -All -ErrorAction SilentlyContinue)) {
        $candidates.Add($command.Source)
    }

    $candidates.Add("C:\msys64\usr\bin\bash.exe")

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path $candidate)) {
            continue
        }

        $probe = & $candidate -lc 'export PATH=/usr/bin:/mingw64/bin:$PATH; command -v git >/dev/null && test -x /usr/bin/make.exe && command -v meson >/dev/null && command -v ninja >/dev/null && command -v pkg-config >/dev/null && (command -v nasm >/dev/null || test -x /mingw64/bin/nasm.exe)' 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $candidate
        }
    }

    throw "MSYS2 bash with git, make, meson, ninja, pkg-config, and nasm was not found."
}

function Import-VsDevEnvironment {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe was not found. This workflow requires a GitHub-hosted Windows runner with Visual Studio 2022."
    }

    $vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    if (-not $vsInstall) {
        throw "Visual Studio 2022 with the x64 MSVC toolchain was not found."
    }

    $vcvars = Join-Path $vsInstall "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvars)) {
        throw "vcvars64.bat was not found at $vcvars."
    }

    $importScript = Join-Path ([System.IO.Path]::GetTempPath()) "import-vs-env-$PID.cmd"
    $importScriptLines = @(
        "@echo off",
        "call `"$vcvars`" >nul",
        "if errorlevel 1 exit /b %errorlevel%",
        "set"
    )
    [System.IO.File]::WriteAllLines($importScript, $importScriptLines, [System.Text.Encoding]::ASCII)

    try {
        $environment = & cmd.exe /d /s /c "`"$importScript`""
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to initialize the Visual Studio 2022 x64 developer environment."
        }
    } finally {
        Remove-Item -LiteralPath $importScript -Force -ErrorAction SilentlyContinue
    }

    $importedCount = 0
    foreach ($line in $environment) {
        if ($line -match "^(.*?)=(.*)$") {
            $name = $Matches[1]
            $value = $Matches[2]
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
            Set-Item -LiteralPath "Env:$name" -Value $value
            $importedCount++
        }
    }

    Write-Host "Imported $importedCount Visual Studio environment variables."
}

function Assert-FileExists {
    param([string] $Path)
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
}

function Assert-DirectoryExists {
    param([string] $Path)
    if (-not (Test-Path $Path -PathType Container)) {
        throw "Required directory is missing: $Path"
    }
}

function Assert-HeaderDefine {
    param(
        [string] $Path,
        [string] $Name,
        [int] $ExpectedValue
    )

    $pattern = "^\s*#define\s+$([regex]::Escape($Name))\s+$ExpectedValue\b"
    if (-not (Select-String -Path $Path -Pattern $pattern -Quiet)) {
        throw "Expected $Name to be $ExpectedValue in $Path."
    }
}

function Assert-ConfigureOutput {
    param([string] $Pattern, [string] $Description)
    if (-not (Select-String -Path $ConfigureOutputFile -Pattern $Pattern -Quiet)) {
        throw "Configure output did not confirm: $Description"
    }
}

function Copy-ComplianceFiles {
    param([string] $Destination)

    Copy-Item $BuildInfoFile $Destination
    Copy-Item $SourceInfoFile $Destination
    Copy-Item $ConfigureCommandFile $Destination
    Copy-Item $ConfigureOutputFile $Destination
    Copy-Item $ChangesDiffFile $Destination
    Copy-Item $RuntimeReportFile $Destination
    Copy-Item $RuntimeProbeFile $Destination
    Copy-Item $LgplFile $Destination
    Copy-Item $GplFile $Destination
    Copy-Item $Dav1dLicenseFile $Destination

    $destSource = Join-Path $Destination "source"
    New-Item -ItemType Directory -Force -Path $destSource | Out-Null
    Copy-Item $FfmpegSourceArchive $destSource
    Copy-Item $NvCodecHeadersSourceArchive $destSource
    Copy-Item $Dav1dSourceArchive $destSource
}

function Convert-ToManifestPath {
    param([string] $Path)
    return $Path.Replace("\", "/")
}

function Get-Sha256Hex {
    param([string] $Path)
    Assert-FileExists $Path
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Convert-ToStringArray {
    param([AllowNull()][object] $Value)

    $result = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Value) {
        return [string[]]@()
    }

    if ($Value -is [string]) {
        return [string[]]@($Value)
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            if ($null -ne $item) {
                $result.Add([string]$item)
            }
        }
        return $result.ToArray()
    }

    return [string[]]@([string]$Value)
}

function Write-Sha256Manifest {
    param(
        [string] $Root,
        [string] $ManifestPath,
        [AllowNull()][object] $RelativePaths
    )

    if ((Split-Path $ManifestPath -Leaf) -ne "SHA256SUMS.txt") {
        throw "SHA256 manifest path must end with SHA256SUMS.txt: $ManifestPath"
    }

    $expectedPaths = @(Convert-ToStringArray $RelativePaths)
    if ($expectedPaths.Count -eq 0) {
        throw "SHA256 manifest requires at least one entry: $ManifestPath"
    }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($relativePath in $expectedPaths) {
        $manifestRelativePath = Convert-ToManifestPath $relativePath
        $filePath = Join-Path $Root ($manifestRelativePath.Replace("/", "\"))
        $lines.Add("$(Get-Sha256Hex $filePath)  $manifestRelativePath")
    }

    $manifestParent = Split-Path $ManifestPath -Parent
    if ($manifestParent) {
        New-Item -ItemType Directory -Force -Path $manifestParent | Out-Null
    }

    [string[]] $manifestLines = $lines.ToArray()
    [System.IO.File]::WriteAllLines($ManifestPath, $manifestLines, [System.Text.UTF8Encoding]::new($false))
    Assert-FileExists $ManifestPath
    Write-Host "SHA256 manifest destination: $ManifestPath"
    Write-Host "SHA256 manifest entries written: $($manifestLines.Count)"
    Write-Host "SHA256 manifest exists: yes"
    Assert-Sha256Manifest -Root $Root -ManifestPath $ManifestPath -ExpectedRelativePaths $expectedPaths
}

function Assert-Sha256Manifest {
    param(
        [string] $Root,
        [string] $ManifestPath,
        [string[]] $ExpectedRelativePaths
    )

    Assert-FileExists $ManifestPath
    $records = @{}
    foreach ($line in (Get-Content -Path $ManifestPath)) {
        if ($line -notmatch "^([0-9a-f]{64})  (.+)$") {
            throw "Invalid SHA256 manifest line in $ManifestPath`: $line"
        }

        $hash = $Matches[1]
        $recordRelativePath = Convert-ToManifestPath $Matches[2]
        if ($records.ContainsKey($recordRelativePath)) {
            throw "Duplicate SHA256 manifest entry in $ManifestPath`: $recordRelativePath"
        }
        $records[$recordRelativePath] = $hash
    }

    foreach ($expectedRelativePath in $ExpectedRelativePaths) {
        $expectedManifestRelativePath = Convert-ToManifestPath $expectedRelativePath
        if (-not $records.ContainsKey($expectedManifestRelativePath)) {
            throw "SHA256 manifest $ManifestPath omits expected file: $expectedManifestRelativePath"
        }

        $filePath = Join-Path $Root ($expectedManifestRelativePath.Replace("/", "\"))
        $actualHash = Get-Sha256Hex $filePath
        if ($records[$expectedManifestRelativePath] -ne $actualHash) {
            throw "SHA256 mismatch for $expectedManifestRelativePath in $ManifestPath. Expected $($records[$expectedManifestRelativePath]); got $actualHash."
        }
    }
}

function Invoke-RuntimeProbe {
    param(
        [string] $IncludeDir,
        [string] $BuildDir,
        [string] $BinDir,
        [string] $OutputFile
    )

    Assert-FileExists $ProbeSourceFile
    $avutilImportLib = @(Get-ChildItem -Path $BuildDir -Recurse -Filter "avutil.lib" -File)
    if ($avutilImportLib.Count -ne 1) {
        throw "Expected exactly one generated avutil.lib under $BuildDir; found $($avutilImportLib.Count)."
    }
    $avcodecImportLib = @(Get-ChildItem -Path $BuildDir -Recurse -Filter "avcodec.lib" -File)
    if ($avcodecImportLib.Count -ne 1) {
        throw "Expected exactly one generated avcodec.lib under $BuildDir; found $($avcodecImportLib.Count)."
    }
    $libDirs = @($avcodecImportLib[0].DirectoryName, $avutilImportLib[0].DirectoryName) | Select-Object -Unique

    New-Item -ItemType Directory -Force -Path $ProbeBuildRoot | Out-Null
    $probeExe = Join-Path $ProbeBuildRoot "ffmpeg-runtime-probe.exe"
    $compileArgs = @(
        "/nologo",
        "/W3",
        "/I", $IncludeDir,
        $ProbeSourceFile,
        "/Fe:$probeExe",
        "/link"
    )
    foreach ($libDir in $libDirs) {
        $compileArgs += "/LIBPATH:$libDir"
    }
    $compileArgs += @(
        "avcodec.lib",
        "avutil.lib"
    )
    Invoke-Native -FilePath "cl.exe" -ArgumentList $compileArgs -WorkingDirectory $ProbeBuildRoot

    $oldPath = $env:PATH
    try {
        $env:PATH = "$BinDir;$oldPath"
        $probeOutput = & $probeExe 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "FFmpeg runtime probe exited with code $LASTEXITCODE.`n$($probeOutput -join "`n")"
        }
    } finally {
        $env:PATH = $oldPath
    }

    [System.IO.File]::WriteAllLines($OutputFile, $probeOutput, [System.Text.UTF8Encoding]::new($false))
    $probeText = $probeOutput -join "`n"
    Assert-ContainsProbeText -ProbeText $probeText -Pattern "(?m)^version=.*$([regex]::Escape($FfmpegVersion))" -Description "FFmpeg version contains $FfmpegVersion"
    Assert-ContainsProbeText -ProbeText $probeText -Pattern "(?m)^version=.*kawaiiengine-webmiere" -Description "FFmpeg extra version contains kawaiiengine-webmiere"
    Assert-ContainsProbeText -ProbeText $probeText -Pattern "(?m)^license=$([regex]::Escape($ExpectedLicense))$" -Description "runtime license is $ExpectedLicense"
    foreach ($flag in @(
        "--enable-version3",
        "--disable-gpl",
        "--disable-nonfree",
        "--enable-shared",
        "--disable-static",
        "--enable-libdav1d",
        "--enable-decoder=av1",
        "--enable-decoder=libdav1d",
        "--enable-decoder=vp9",
        "--enable-decoder=opus",
        "--enable-demuxer=matroska",
        "--enable-protocol=file",
        "--enable-nvdec",
        "--enable-hwaccel=av1_nvdec",
        "--enable-hwaccel=vp9_nvdec"
    )) {
        Assert-ContainsProbeText -ProbeText $probeText -Pattern ([regex]::Escape($flag)) -Description "runtime configuration contains $flag"
    }
    Assert-ContainsProbeText -ProbeText $probeText -Pattern "(?m)^decoder\.av1=present$" -Description "runtime has native av1 decoder"
    Assert-ContainsProbeText -ProbeText $probeText -Pattern "(?m)^decoder\.libdav1d=present$" -Description "runtime has libdav1d decoder"
}

function Assert-ContainsProbeText {
    param(
        [string] $ProbeText,
        [string] $Pattern,
        [string] $Description
    )

    if ($ProbeText -notmatch $Pattern) {
        throw "Runtime probe did not confirm: $Description"
    }
}

function Get-ToolVersionReport {
    $clVersion = Get-NativeOutputAllowFailure -FilePath "cl.exe"
    $linkVersion = Get-NativeOutputAllowFailure -FilePath "link.exe"
    $libVersion = Get-NativeOutputAllowFailure -FilePath "lib.exe"
    $dumpbinVersion = Get-NativeOutputAllowFailure -FilePath "dumpbin.exe"
    $gitVersion = Get-NativeOutput -FilePath "git.exe" -ArgumentList @("--version")
    $bashVersion = Get-BashOutput "bash --version | head -n 1"
    $msysVersion = Get-BashOutput "uname -a"
    $makeVersion = Get-BashOutput "/usr/bin/make --version | head -n 1"
    $mesonVersion = Get-BashOutput "meson --version"
    $ninjaVersion = Get-BashOutput "ninja --version"
    $nasmVersion = Get-BashOutput '"$NASM_EXE_MSYS" -v'
    $pkgConfigVersion = Get-BashOutput "pkg-config --version"

    return @"
Compiler and build tool versions
================================

cl.exe:
$clVersion

link.exe:
$linkVersion

lib.exe:
$libVersion

dumpbin.exe:
$dumpbinVersion

git:
$gitVersion

MSYS2 bash:
$bashVersion

MSYS2 uname:
$msysVersion

make:
$makeVersion

meson:
$mesonVersion

ninja:
$ninjaVersion

nasm:
$nasmVersion

pkg-config:
$pkgConfigVersion
"@
}

Write-Step "Preparing directories"
foreach ($path in @($WorkRoot, $ArtifactsRoot)) {
    if (Test-Path $path) {
        Remove-Item -Recurse -Force $path
    }
}
foreach ($path in @($SourceRoot, $FfmpegBuildDir, $Dav1dBuildDir, $InstallRoot, $DepsRoot, $Dav1dPrefix, $ComplianceRoot, $SourceArchiveRoot, $RuntimePackageRoot, $DevelopmentPackageRoot, $ArtifactsRoot)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

$env:MSYS2_PATH_TYPE = "inherit"
$script:BashPath = Find-MsysBash
Write-Host "Using MSYS2 bash: $script:BashPath"

Write-Step "Initializing Visual Studio 2022 x64 MSVC environment"
Import-VsDevEnvironment
$clCommand = Get-Command cl.exe -ErrorAction Stop
Write-Host "PowerShell cl.exe path: $($clCommand.Source)"
$script:MsvcPathMsys = Convert-WindowsPathListToMsys $env:PATH
$msysClPath = (Get-BashOutput 'command -v cl.exe || true').Trim()
Write-Host "MSYS2 cl.exe path: $msysClPath"
if (-not $msysClPath) {
    throw "cl.exe was not found inside MSYS2 bash after importing the Visual Studio environment."
}
$script:MsvcToolPathMsys = (Get-BashOutput 'dirname "$(command -v cl.exe)"').Trim()
Write-Host "MSYS2 MSVC tool directory: $script:MsvcToolPathMsys"
$msysLinkPath = (Get-BashOutput 'command -v link.exe || true').Trim()
Write-Host "MSYS2 link.exe path: $msysLinkPath"
if (-not $msysLinkPath -or $msysLinkPath -eq "/usr/bin/link.exe") {
    throw "MSVC link.exe was not selected inside MSYS2 bash after importing the Visual Studio environment."
}

Write-Step "Cloning pinned FFmpeg source"
Invoke-Native -FilePath "git.exe" -ArgumentList @("clone", "--branch", $FfmpegTag, "--depth", "1", $FfmpegRepository, $FfmpegSourceDir)
$actualFfmpegCommit = (Get-NativeOutput -FilePath "git.exe" -ArgumentList @("-C", $FfmpegSourceDir, "rev-parse", "HEAD")).Trim()
$actualFfmpegTagObject = (Get-NativeOutput -FilePath "git.exe" -ArgumentList @("-C", $FfmpegSourceDir, "rev-parse", $FfmpegTag)).Trim()
if ($actualFfmpegCommit -ne $FfmpegCommit) {
    throw "FFmpeg tag $FfmpegTag resolved to $actualFfmpegCommit, expected $FfmpegCommit."
}
if ($actualFfmpegTagObject -ne $FfmpegTagObject) {
    throw "FFmpeg tag object for $FfmpegTag resolved to $actualFfmpegTagObject, expected $FfmpegTagObject."
}

Write-Step "Cloning pinned nv-codec-headers source"
Invoke-Native -FilePath "git.exe" -ArgumentList @("clone", "--branch", $NvCodecHeadersTag, "--depth", "1", $NvCodecHeadersRepository, $NvCodecHeadersSourceDir)
$actualNvCodecHeadersCommit = (Get-NativeOutput -FilePath "git.exe" -ArgumentList @("-C", $NvCodecHeadersSourceDir, "rev-parse", "HEAD")).Trim()
if ($actualNvCodecHeadersCommit -ne $NvCodecHeadersCommit) {
    throw "nv-codec-headers tag $NvCodecHeadersTag resolved to $actualNvCodecHeadersCommit, expected $NvCodecHeadersCommit."
}

Write-Step "Cloning pinned dav1d source"
Invoke-Native -FilePath "git.exe" -ArgumentList @("clone", "--branch", $Dav1dTag, "--depth", "1", $Dav1dRepository, $Dav1dSourceDir)
$actualDav1dCommit = (Get-NativeOutput -FilePath "git.exe" -ArgumentList @("-C", $Dav1dSourceDir, "rev-parse", "HEAD")).Trim()
if ($actualDav1dCommit -ne $Dav1dCommit) {
    throw "dav1d tag $Dav1dTag resolved to $actualDav1dCommit, expected $Dav1dCommit."
}

$FfmpegSourceDirMsys = Convert-ToMsysPath $FfmpegSourceDir
$NvCodecHeadersSourceDirMsys = Convert-ToMsysPath $NvCodecHeadersSourceDir
$Dav1dSourceDirMsys = Convert-ToMsysPath $Dav1dSourceDir
$FfmpegBuildDirMsys = Convert-ToMsysPath $FfmpegBuildDir
$Dav1dBuildDirMsys = Convert-ToMsysPath $Dav1dBuildDir
$InstallRootMsys = Convert-ToMsysPath $InstallRoot
$NvCodecHeadersPrefixMsys = Convert-ToMsysPath $NvCodecHeadersPrefix
$Dav1dPrefixMsys = Convert-ToMsysPath $Dav1dPrefix
$Dav1dMesonNativeFileMsys = Convert-ToMsysPath $Dav1dMesonNativeFile
$FfmpegSourceArchiveMsys = Convert-ToMsysPath $FfmpegSourceArchive
$NvCodecHeadersSourceArchiveMsys = Convert-ToMsysPath $NvCodecHeadersSourceArchive
$Dav1dSourceArchiveMsys = Convert-ToMsysPath $Dav1dSourceArchive

$env:FFMPEG_SOURCE_DIR_MSYS = $FfmpegSourceDirMsys
$env:NV_CODEC_HEADERS_SOURCE_DIR_MSYS = $NvCodecHeadersSourceDirMsys
$env:DAV1D_SOURCE_DIR_MSYS = $Dav1dSourceDirMsys
$env:FFMPEG_BUILD_DIR_MSYS = $FfmpegBuildDirMsys
$env:DAV1D_BUILD_DIR_MSYS = $Dav1dBuildDirMsys
$env:INSTALL_ROOT_MSYS = $InstallRootMsys
$env:NV_CODEC_HEADERS_PREFIX_MSYS = $NvCodecHeadersPrefixMsys
$env:DAV1D_PREFIX_MSYS = $Dav1dPrefixMsys
$env:DAV1D_MESON_NATIVE_FILE_MSYS = $Dav1dMesonNativeFileMsys
$env:FFMPEG_SOURCE_ARCHIVE_MSYS = $FfmpegSourceArchiveMsys
$env:NV_CODEC_HEADERS_SOURCE_ARCHIVE_MSYS = $NvCodecHeadersSourceArchiveMsys
$env:DAV1D_SOURCE_ARCHIVE_MSYS = $Dav1dSourceArchiveMsys
$env:FFMPEG_COMMIT = $FfmpegCommit
$env:NV_CODEC_HEADERS_COMMIT = $NvCodecHeadersCommit
$env:DAV1D_COMMIT = $Dav1dCommit
$env:FFMPEG_ARCHIVE_PREFIX = "ffmpeg-$FfmpegVersion-$FfmpegCommit/"
$env:NV_CODEC_HEADERS_ARCHIVE_PREFIX = "nv-codec-headers-$NvCodecHeadersCommit/"
$env:DAV1D_ARCHIVE_PREFIX = "dav1d-$Dav1dVersion-$Dav1dCommit/"

$nasmExeMsys = (Get-BashOutput 'if [ -x /mingw64/bin/nasm.exe ]; then echo /mingw64/bin/nasm.exe; elif command -v nasm >/dev/null 2>&1; then command -v nasm; else echo "nasm not found" >&2; exit 1; fi').Trim()
$env:NASM_EXE_MSYS = $nasmExeMsys
$nasmExeForMeson = (Get-BashOutput '/usr/bin/cygpath -w "$NASM_EXE_MSYS"').Trim().Replace("\", "/")
Assert-FileExists $nasmExeForMeson
$clExeForMeson = (Get-Command cl.exe -ErrorAction Stop).Source.Replace("\", "/")
$libExeForMeson = (Get-Command lib.exe -ErrorAction Stop).Source.Replace("\", "/")

$processorCount = 2
if ($env:NUMBER_OF_PROCESSORS) {
    $processorCount = [int]$env:NUMBER_OF_PROCESSORS
}
$parallelism = [Math]::Max(2, $processorCount)

Write-Step "Creating exact corresponding source archives"
Invoke-Bash 'cd "$FFMPEG_SOURCE_DIR_MSYS" && git archive --format=tar --prefix="$FFMPEG_ARCHIVE_PREFIX" "$FFMPEG_COMMIT" | gzip -n > "$FFMPEG_SOURCE_ARCHIVE_MSYS"'
Invoke-Bash 'cd "$NV_CODEC_HEADERS_SOURCE_DIR_MSYS" && git archive --format=tar --prefix="$NV_CODEC_HEADERS_ARCHIVE_PREFIX" "$NV_CODEC_HEADERS_COMMIT" | gzip -n > "$NV_CODEC_HEADERS_SOURCE_ARCHIVE_MSYS"'
Invoke-Bash 'cd "$DAV1D_SOURCE_DIR_MSYS" && git archive --format=tar --prefix="$DAV1D_ARCHIVE_PREFIX" "$DAV1D_COMMIT" | gzip -n > "$DAV1D_SOURCE_ARCHIVE_MSYS"'

Write-Step "Installing nv-codec-headers into an isolated prefix"
Invoke-Bash 'cd "$NV_CODEC_HEADERS_SOURCE_DIR_MSYS" && /usr/bin/make PREFIX="$NV_CODEC_HEADERS_PREFIX_MSYS" install'

Write-Step "Building and installing dav1d static library"
$dav1dMesonNative = @"
[binaries]
c = '$clExeForMeson'
ar = '$libExeForMeson'
pkg-config = 'pkg-config'
nasm = '$nasmExeForMeson'

[built-in options]
b_vscrt = 'mt'
"@
[System.IO.File]::WriteAllText($Dav1dMesonNativeFile, $dav1dMesonNative, [System.Text.UTF8Encoding]::new($false))
Invoke-Bash 'meson setup "$DAV1D_BUILD_DIR_MSYS" "$DAV1D_SOURCE_DIR_MSYS" --prefix "$DAV1D_PREFIX_MSYS" --libdir lib --buildtype=release --default-library=static --native-file "$DAV1D_MESON_NATIVE_FILE_MSYS" -Denable_tools=false -Denable_examples=false -Denable_tests=false'
Invoke-Bash "meson compile -C `"$Dav1dBuildDirMsys`" -j$parallelism"
Invoke-Bash 'meson install -C "$DAV1D_BUILD_DIR_MSYS"'
$dav1dStaticArchive = Join-Path $Dav1dPrefix "lib\libdav1d.a"
$dav1dMsvcLibrary = Join-Path $Dav1dPrefix "lib\dav1d.lib"
if (-not (Test-Path $dav1dMsvcLibrary) -and (Test-Path $dav1dStaticArchive)) {
    Copy-Item -LiteralPath $dav1dStaticArchive -Destination $dav1dMsvcLibrary
}
Assert-FileExists (Join-Path $Dav1dPrefix "include\dav1d\dav1d.h")
Assert-FileExists $dav1dMsvcLibrary
Assert-FileExists (Join-Path $Dav1dPrefix "lib\pkgconfig\dav1d.pc")
if (Test-Path (Join-Path $Dav1dPrefix "bin\dav1d.dll")) {
    throw "dav1d was expected to be static, but dav1d.dll was installed."
}

$ConfigureArgs = @(
    "--prefix=$InstallRootMsys",
    "--toolchain=msvc",
    "--arch=x86_64",
    "--x86asmexe=$nasmExeMsys",
    "--enable-version3",
    "--disable-gpl",
    "--disable-nonfree",
    "--enable-shared",
    "--disable-static",
    "--extra-version=kawaiiengine-webmiere",
    "--pkg-config-flags=--static",
    "--disable-programs",
    "--disable-doc",
    "--disable-network",
    "--disable-avdevice",
    "--disable-avfilter",
    "--disable-everything",
    "--disable-autodetect",
    "--disable-amf",
    "--disable-cuvid",
    "--disable-cuda-nvcc",
    "--disable-d3d11va",
    "--disable-d3d12va",
    "--disable-dxva2",
    "--disable-libnpp",
    "--disable-mediafoundation",
    "--disable-nvenc",
    "--enable-libdav1d",
    "--enable-ffnvcodec",
    "--enable-nvdec",
    "--enable-avcodec",
    "--enable-avformat",
    "--enable-avutil",
    "--enable-swscale",
    "--enable-swresample",
    "--enable-demuxer=matroska",
    "--enable-protocol=file",
    "--enable-decoder=av1",
    "--enable-decoder=libdav1d",
    "--enable-decoder=vp9",
    "--enable-decoder=opus",
    "--enable-parser=av1",
    "--enable-parser=vp9",
    "--enable-parser=opus",
    "--enable-hwaccel=av1_nvdec",
    "--enable-hwaccel=vp9_nvdec"
)

$pkgConfigPathMsys = "$NvCodecHeadersPrefixMsys/lib/pkgconfig`:$Dav1dPrefixMsys/lib/pkgconfig"
$env:PKG_CONFIG_PATH = $pkgConfigPathMsys
$configureCommandLines = @(
    "cd $FfmpegBuildDirMsys",
    "PKG_CONFIG_PATH=$pkgConfigPathMsys $FfmpegSourceDirMsys/configure \"
)
for ($i = 0; $i -lt $ConfigureArgs.Count; $i++) {
    $suffix = ""
    if ($i -lt ($ConfigureArgs.Count - 1)) {
        $suffix = " \"
    }
    $configureCommandLines += "  $($ConfigureArgs[$i])$suffix"
}
$configureCommand = ($configureCommandLines -join "`n") + "`n"
[System.IO.File]::WriteAllText($ConfigureCommandFile, $configureCommand, [System.Text.UTF8Encoding]::new($false))

$quotedConfigureArgs = ($ConfigureArgs | ForEach-Object { Quote-Bash $_ }) -join " "
$configureShellCommand = "cd `"$FfmpegBuildDirMsys`" && `"$FfmpegSourceDirMsys`"/configure $quotedConfigureArgs"

Write-Step "Configuring FFmpeg"
$configureOutput = & $script:BashPath -c (Get-MsysCommand $configureShellCommand) 2>&1
$configureExitCode = $LASTEXITCODE
[System.IO.File]::WriteAllText($ConfigureOutputFile, ($configureOutput -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
if ($configureExitCode -ne 0) {
    Write-Host "FFmpeg configure output:"
    foreach ($line in $configureOutput) {
        Write-Host $line
    }

    $configLog = Join-Path $FfmpegBuildDir "ffbuild\config.log"
    if (Test-Path $configLog) {
        Write-Host "FFmpeg config.log tail:"
        Get-Content -Path $configLog -Tail 220 | ForEach-Object { Write-Host $_ }
    }
    throw "FFmpeg configure failed. See $ConfigureOutputFile."
}

Write-Step "Building and installing FFmpeg shared libraries"
Invoke-Bash "cd `"$FfmpegBuildDirMsys`" && /usr/bin/make -j$parallelism && /usr/bin/make install"

Write-Step "Generating source-change diff"
$diffOutput = & git.exe -C $FfmpegSourceDir diff --binary $FfmpegCommit -- . 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create FFmpeg source diff.`n$($diffOutput -join "`n")"
}
$diffText = $diffOutput -join "`n"
[System.IO.File]::WriteAllText($ChangesDiffFile, $diffText, [System.Text.UTF8Encoding]::new($false))
if ($diffText.Length -ne 0) {
    throw "FFmpeg source tree differs from pinned commit $FfmpegCommit. See $ChangesDiffFile."
}
Copy-Item (Join-Path $FfmpegSourceDir "COPYING.LGPLv3") $LgplFile
Copy-Item (Join-Path $FfmpegSourceDir "COPYING.GPLv3") $GplFile
Copy-Item (Join-Path $Dav1dSourceDir "COPYING") $Dav1dLicenseFile

Write-Step "Running compliance checks"
$configHeader = Join-Path $FfmpegBuildDir "config.h"
$componentHeader = Join-Path $FfmpegBuildDir "config_components.h"
Assert-FileExists $configHeader
Assert-FileExists $componentHeader

Assert-HeaderDefine $configHeader "CONFIG_GPL" 0
Assert-HeaderDefine $configHeader "CONFIG_NONFREE" 0
Assert-HeaderDefine $configHeader "CONFIG_VERSION3" 1
Assert-HeaderDefine $configHeader "CONFIG_AVCODEC" 1
Assert-HeaderDefine $configHeader "CONFIG_AVFORMAT" 1
Assert-HeaderDefine $configHeader "CONFIG_AVUTIL" 1
Assert-HeaderDefine $configHeader "CONFIG_SWSCALE" 1
Assert-HeaderDefine $configHeader "CONFIG_SWRESAMPLE" 1
Assert-HeaderDefine $configHeader "CONFIG_AVDEVICE" 0
Assert-HeaderDefine $configHeader "CONFIG_AVFILTER" 0
Assert-HeaderDefine $configHeader "CONFIG_NETWORK" 0
Assert-HeaderDefine $configHeader "CONFIG_LIBDAV1D" 1
Assert-HeaderDefine $configHeader "CONFIG_NVENC" 0
Assert-HeaderDefine $configHeader "CONFIG_CUDA_NVCC" 0
Assert-HeaderDefine $configHeader "CONFIG_NVDEC" 1

Assert-HeaderDefine $componentHeader "CONFIG_MATROSKA_DEMUXER" 1
Assert-HeaderDefine $componentHeader "CONFIG_FILE_PROTOCOL" 1
Assert-HeaderDefine $componentHeader "CONFIG_AV1_DECODER" 1
Assert-HeaderDefine $componentHeader "CONFIG_LIBDAV1D_DECODER" 1
Assert-HeaderDefine $componentHeader "CONFIG_VP9_DECODER" 1
Assert-HeaderDefine $componentHeader "CONFIG_OPUS_DECODER" 1
Assert-HeaderDefine $componentHeader "CONFIG_AV1_PARSER" 1
Assert-HeaderDefine $componentHeader "CONFIG_VP9_PARSER" 1
Assert-HeaderDefine $componentHeader "CONFIG_OPUS_PARSER" 1
Assert-HeaderDefine $componentHeader "CONFIG_AV1_NVDEC_HWACCEL" 1
Assert-HeaderDefine $componentHeader "CONFIG_VP9_NVDEC_HWACCEL" 1
Assert-HeaderDefine $componentHeader "CONFIG_BILATERAL_CUDA_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_BWDIF_CUDA_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_CHROMAKEY_CUDA_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_COLORSPACE_CUDA_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_HWUPLOAD_CUDA_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_OVERLAY_CUDA_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_PAD_CUDA_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_SCALE_CUDA_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_SCALE_NPP_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_SCALE2REF_NPP_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_SHARPEN_NPP_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_THUMBNAIL_CUDA_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_TRANSPOSE_NPP_FILTER" 0
Assert-HeaderDefine $componentHeader "CONFIG_YADIF_CUDA_FILTER" 0

Assert-ConfigureOutput "^License:\s+$([regex]::Escape($ExpectedLicense))$" "runtime license is $ExpectedLicense"
Assert-ConfigureOutput "\blibdav1d\b" "libdav1d is enabled"

$installBin = Join-Path $InstallRoot "bin"
$installLib = Join-Path $InstallRoot "lib"
Assert-DirectoryExists $installBin
foreach ($dll in $ExpectedDlls) {
    Assert-FileExists (Join-Path $installBin $dll)
}
$actualDlls = Get-ChildItem -Path $installBin -Filter "*.dll" -File | Select-Object -ExpandProperty Name | Sort-Object
$expectedDllsSorted = $ExpectedDlls | Sort-Object
if (($actualDlls -join "|") -ne ($expectedDllsSorted -join "|")) {
    throw "Runtime DLL set mismatch. Expected $($expectedDllsSorted -join ', '); got $($actualDlls -join ', ')."
}

foreach ($program in @("ffmpeg.exe", "ffprobe.exe", "ffplay.exe")) {
    if (Test-Path (Join-Path $installBin $program)) {
        throw "Programs were disabled, but $program was generated."
    }
}

$unexpectedStaticLibs = Get-ChildItem -Path $InstallRoot -Recurse -Include "*.a" -ErrorAction SilentlyContinue
if ($unexpectedStaticLibs) {
    throw "Static or MinGW import libraries were generated unexpectedly: $($unexpectedStaticLibs.FullName -join ', ')"
}

$runtimeReport = New-Object System.Collections.Generic.List[string]
$runtimeReport.Add($PackageNotice)
$runtimeReport.Add("")
$runtimeReport.Add("Runtime license: $ExpectedLicense")
$runtimeReport.Add("FFmpeg tag: $FfmpegTag")
$runtimeReport.Add("FFmpeg tag object: $FfmpegTagObject")
$runtimeReport.Add("FFmpeg commit: $FfmpegCommit")
$runtimeReport.Add("nv-codec-headers tag: $NvCodecHeadersTag")
$runtimeReport.Add("nv-codec-headers commit: $NvCodecHeadersCommit")
$runtimeReport.Add("dav1d tag: $Dav1dTag")
$runtimeReport.Add("dav1d commit: $Dav1dCommit")
$runtimeReport.Add("")
$runtimeReport.Add("DLL dependency report")
$runtimeReport.Add("=====================")

$forbiddenDependencyPattern = "(?i)(msys-|mingw|libgcc|libstdc\+\+|libwinpthread)"
foreach ($dll in $ExpectedDlls) {
    $dllPath = Join-Path $installBin $dll
    $dumpbinOutput = & dumpbin.exe /dependents $dllPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "dumpbin failed for $dllPath.`n$($dumpbinOutput -join "`n")"
    }

    $runtimeReport.Add("")
    $runtimeReport.Add("[$dll]")
    foreach ($line in $dumpbinOutput) {
        $runtimeReport.Add($line.ToString())
    }

    if ($dumpbinOutput -match $forbiddenDependencyPattern) {
        throw "Unexpected MSYS, MinGW, libgcc, libstdc++, or libwinpthread dependency detected in $dll."
    }
}

[System.IO.File]::WriteAllLines($RuntimeReportFile, $runtimeReport, [System.Text.UTF8Encoding]::new($false))

Write-Step "Building and running FFmpeg runtime probe"
Invoke-RuntimeProbe -IncludeDir (Join-Path $InstallRoot "include") -BuildDir $FfmpegBuildDir -BinDir $installBin -OutputFile $RuntimeProbeFile

Write-Step "Writing build and source compliance records"
$toolVersionReport = Get-ToolVersionReport
$buildInfo = @"
$PackageNotice

Build summary
=============

Target: Windows x64
Runner: GitHub-hosted windows-2022
Toolchain: Visual Studio 2022 MSVC with MSYS2 build tools
Linkage: FFmpeg shared libraries only; dav1d static library linked into avcodec
Runtime license: $ExpectedLicense

FFmpeg version: $FfmpegVersion
FFmpeg tag: $FfmpegTag
FFmpeg tag object: $FfmpegTagObject
FFmpeg commit: $FfmpegCommit
nv-codec-headers tag: $NvCodecHeadersTag
nv-codec-headers commit: $NvCodecHeadersCommit
dav1d version: $Dav1dVersion
dav1d tag: $Dav1dTag
dav1d commit: $Dav1dCommit

Expected DLLs:
$($ExpectedDlls -join "`n")

$toolVersionReport
"@
[System.IO.File]::WriteAllText($BuildInfoFile, $buildInfo, [System.Text.UTF8Encoding]::new($false))

$sourceInfo = @"
$PackageNotice

FFmpeg source
=============

Repository: $FfmpegRepository
Version: $FfmpegVersion
Tag: $FfmpegTag
Annotated tag object: $FfmpegTagObject
Resolved commit: $FfmpegCommit
Source archive: source/$(Split-Path $FfmpegSourceArchive -Leaf)
Source diff verification: ffmpeg-changes.diff was generated and verified empty

nv-codec-headers source
=======================

Repository: $NvCodecHeadersRepository
Tag: $NvCodecHeadersTag
Resolved commit: $NvCodecHeadersCommit
Source archive: source/$(Split-Path $NvCodecHeadersSourceArchive -Leaf)

dav1d source
============

Repository: $Dav1dRepository
Version: $Dav1dVersion
Tag: $Dav1dTag
Resolved commit: $Dav1dCommit
Source archive: source/$(Split-Path $Dav1dSourceArchive -Leaf)
"@
[System.IO.File]::WriteAllText($SourceInfoFile, $sourceInfo, [System.Text.UTF8Encoding]::new($false))

Write-Step "Packaging runtime files"
$runtimeBin = Join-Path $RuntimePackageRoot "bin"
New-Item -ItemType Directory -Force -Path $runtimeBin | Out-Null
foreach ($dll in $ExpectedDlls) {
    Copy-Item (Join-Path $installBin $dll) $runtimeBin
}
Copy-ComplianceFiles -Destination $RuntimePackageRoot

Write-Step "Packaging development files"
$developmentInclude = Join-Path $DevelopmentPackageRoot "include"
$developmentLib = Join-Path $DevelopmentPackageRoot "lib"
New-Item -ItemType Directory -Force -Path $developmentInclude, $developmentLib | Out-Null
Copy-Item (Join-Path $InstallRoot "include\*") $developmentInclude -Recurse

$importLibs = Get-ChildItem -Path $InstallRoot -Recurse -Filter "*.lib" -File
foreach ($importLib in $importLibs) {
    Copy-Item $importLib.FullName $developmentLib
}

Copy-ComplianceFiles -Destination $DevelopmentPackageRoot

foreach ($header in @(
    "include\libavcodec\avcodec.h",
    "include\libavformat\avformat.h",
    "include\libavutil\avutil.h",
    "include\libswscale\swscale.h",
    "include\libswresample\swresample.h"
)) {
    Assert-FileExists (Join-Path $DevelopmentPackageRoot $header)
}
foreach ($importLib in $ExpectedImportLibs) {
    Assert-FileExists (Join-Path $developmentLib $importLib)
}
$actualImportLibs = Get-ChildItem -Path $developmentLib -Filter "*.lib" -File | Select-Object -ExpandProperty Name | Sort-Object
$expectedImportLibsSorted = $ExpectedImportLibs | Sort-Object
if (($actualImportLibs -join "|") -ne ($expectedImportLibsSorted -join "|")) {
    throw "Development package import library set mismatch. Expected $($expectedImportLibsSorted -join ', '); got $($actualImportLibs -join ', ')."
}
$pkgConfigDirs = Get-ChildItem -Path $DevelopmentPackageRoot -Recurse -Directory -Filter "pkgconfig" -ErrorAction SilentlyContinue
if ($pkgConfigDirs) {
    throw "Development package must not contain pkgconfig directories: $($pkgConfigDirs.FullName -join ', ')"
}
$pcFiles = Get-ChildItem -Path $DevelopmentPackageRoot -Recurse -File -Filter "*.pc" -ErrorAction SilentlyContinue
if ($pcFiles) {
    throw "Development package must not contain pkg-config .pc files: $($pcFiles.FullName -join ', ')"
}

Write-Step "Generating package SHA-256 manifests"
$ffmpegSourceArchiveName = Split-Path $FfmpegSourceArchive -Leaf
$nvCodecHeadersSourceArchiveName = Split-Path $NvCodecHeadersSourceArchive -Leaf
$dav1dSourceArchiveName = Split-Path $Dav1dSourceArchive -Leaf
$runtimeManifestFiles = @(
    ($ExpectedDlls | ForEach-Object { "bin/$_" })
    "COPYING.LGPLv3"
    "COPYING.GPLv3"
    "COPYING.dav1d"
    "source/$ffmpegSourceArchiveName"
    "source/$nvCodecHeadersSourceArchiveName"
    "source/$dav1dSourceArchiveName"
)
$developmentManifestFiles = @(
    ($ExpectedImportLibs | ForEach-Object { "lib/$_" })
    "COPYING.LGPLv3"
    "COPYING.GPLv3"
    "COPYING.dav1d"
    "source/$ffmpegSourceArchiveName"
    "source/$nvCodecHeadersSourceArchiveName"
    "source/$dav1dSourceArchiveName"
)
Write-Sha256Manifest -Root $RuntimePackageRoot -ManifestPath (Join-Path $RuntimePackageRoot "SHA256SUMS.txt") -RelativePaths ([string[]]$runtimeManifestFiles)
Write-Sha256Manifest -Root $DevelopmentPackageRoot -ManifestPath (Join-Path $DevelopmentPackageRoot "SHA256SUMS.txt") -RelativePaths ([string[]]$developmentManifestFiles)

Write-Step "Checking required package artifacts"
$requiredComplianceFiles = @(
    "FFmpeg-BUILD-INFO.txt",
    "FFmpeg-SOURCE.txt",
    "ffmpeg-configure.txt",
    "ffmpeg-configure-output.txt",
    "ffmpeg-changes.diff",
    "ffmpeg-runtime-report.txt",
    "ffmpeg-runtime-probe.txt",
    "COPYING.LGPLv3",
    "COPYING.GPLv3",
    "COPYING.dav1d",
    "SHA256SUMS.txt",
    "source\$(Split-Path $FfmpegSourceArchive -Leaf)",
    "source\$(Split-Path $NvCodecHeadersSourceArchive -Leaf)",
    "source\$(Split-Path $Dav1dSourceArchive -Leaf)"
)
foreach ($package in @($RuntimePackageRoot, $DevelopmentPackageRoot)) {
    foreach ($file in $requiredComplianceFiles) {
        Assert-FileExists (Join-Path $package $file)
    }
}
foreach ($dll in $ExpectedDlls) {
    Assert-FileExists (Join-Path $RuntimePackageRoot "bin\$dll")
}

$runtimeZip = Join-Path $ArtifactsRoot "ffmpeg-webmiere-windows-x64-runtime.zip"
$developmentZip = Join-Path $ArtifactsRoot "ffmpeg-webmiere-windows-x64-dev.zip"
Compress-Archive -Path (Join-Path $RuntimePackageRoot "*") -DestinationPath $runtimeZip -Force
Compress-Archive -Path (Join-Path $DevelopmentPackageRoot "*") -DestinationPath $developmentZip -Force
Assert-FileExists $runtimeZip
Assert-FileExists $developmentZip

Write-Step "Generating final ZIP SHA-256 manifest"
$artifactManifestFiles = @(
    (Split-Path $runtimeZip -Leaf),
    (Split-Path $developmentZip -Leaf)
)
Write-Sha256Manifest -Root $ArtifactsRoot -ManifestPath $ArtifactChecksumFile -RelativePaths ([string[]]$artifactManifestFiles)

Write-Step "Build complete"
Write-Host "Runtime package: $runtimeZip"
Write-Host "Development package: $developmentZip"
Write-Host "ZIP checksum manifest: $ArtifactChecksumFile"
