# Splatoon 1 PC Port - one-click setup.
#
# Builds the recompiler, recompiles YOUR OWN copy of the game into a native
# Windows program, and creates a ready-to-play game folder. Nothing from
# Nintendo is downloaded or shipped by this project: the game files always come
# from the dump you select. Run it through Setup.bat (double-click).
#
# Re-running is safe: finished steps are skipped, your save and shader cache are
# kept. Use -Clean to rebuild everything from scratch.

param(
    [string]$GameDump,      # folder with code\, content\, meta\ from your Wii U dump
    [string]$Mlc,           # optional local system-resource source; never prompts
    [string]$Output,        # where the playable game folder is created
    [switch]$SkipShaders,   # do not download the prebuilt shader cache
    [switch]$Clean          # delete previous build outputs first
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Fixed inputs
# ---------------------------------------------------------------------------
$Root = Split-Path -Parent $PSScriptRoot
$Recompiler = Join-Path $Root 'recompiler'
$Work = Join-Path $Root 'build'
$Downloads = Join-Path $Work 'downloads'

# Only this game executable is supported (Splatoon, Europe, AGMP01, v16).
$SupportedRpxSha256 = '45ECD1ED81A97F46B1C8AE24820CD47FBC55399B50AF09BF1F9050FE803308E5'
$BoundaryProfile = Join-Path $Root 'profiles\agmp-v16.entries'
$MinimumFunctionCount = 96300

# Prebuilt shader cache (vulkan_cache.zip) hosted on MEGA.
$ShaderMegaHandle = '6h4CGLJa'
$ShaderMegaKey = 'biEveJ_5lnR0UMdC4u-4KaMGKseyDrHgkUuj3BCwLgQ'
$ShaderZipSha256 = '0D9BB84178AB23F25A1884ADE4B461D57EA7B2C07CB8CF3208179A2776731736'
$ShaderZipSize = 856805907

# Open-source build dependencies (official upstream releases).
$SdlUrl = 'https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-2.32.10.zip'
$GlslangUrl = 'https://github.com/KhronosGroup/glslang/archive/refs/tags/16.4.0.tar.gz'
$VcpkgUrl = 'https://github.com/microsoft/vcpkg.git'
$VcpkgPackages = @('zlib', 'curl', 'volk', 'vulkan-headers')

# Cemu's shared fonts are Noto Sans replacements under SIL OFL 1.1,
# not Nintendo's fonts. Pin the exact upstream bytes for unattended setup.
$FontBaseUrl = 'https://raw.githubusercontent.com/cemu-project/Cemu/cc6fea125a5d4f559c662d13c5f4af0b6dd0876f/bin/resources/sharedFonts'
$FallbackFonts = @(
    @{ Name = 'CafeCn.ttf'; Sha256 = '6AFD751A9BB76BC788EFB50A138C6F3765624EE84D8D8203BE04D871ADE40A6A' },
    @{ Name = 'CafeKr.ttf'; Sha256 = 'C3C326F6CE1899E391DC4996B10A0C30558C5B8F36DFBAA418976862B3E2DFFB' },
    @{ Name = 'CafeStd.ttf'; Sha256 = '59E2494727B8E7A7BBF48C8749F2DBC07D438C9FABEAA9847A08EC690F9888A1' },
    @{ Name = 'CafeTw.ttf'; Sha256 = 'C8F9E16345DBC3B6E165FE12435486A748E730EBE6002B5D713EFE73D171D51C' }
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
$script:StepNumber = 0
function Step([string]$Text) {
    $script:StepNumber++
    Write-Host ''
    Write-Host ("[{0}/9] {1}" -f $script:StepNumber, $Text) -ForegroundColor Cyan
}
function Info([string]$Text) { Write-Host "      $Text" }
function Good([string]$Text) { Write-Host "      $Text" -ForegroundColor Green }
function Warn([string]$Text) { Write-Host "      $Text" -ForegroundColor Yellow }
function Fail([string]$Text) {
    Write-Host ''
    Write-Host "SETUP FAILED: $Text" -ForegroundColor Red
    Write-Host 'If you cannot fix this, open an issue on GitHub and paste this window''s text.' -ForegroundColor Red
    exit 1
}
function Check-Exit([string]$What) {
    if ($LASTEXITCODE -ne 0) { Fail "$What (exit code $LASTEXITCODE)." }
}
function Ask-YesNo([string]$Question) {
    $answer = Read-Host "      $Question [Y/N]"
    return $answer -match '^(y|yes|s|sim)$'
}
function Full-FolderPath([string]$Path) {
    $Path = $Path.Trim().Trim('"')
    if (-not $Path) { return '' }
    try { return [IO.Path]::GetFullPath($Path) }
    catch { Fail "Invalid folder path: $Path. $($_.Exception.Message)" }
}
function Ensure-Folder([string]$Path) {
    [void][IO.Directory]::CreateDirectory($Path)
}
function Initialize-WiiUFolders([string]$GameFolder) {
    # Create an empty MLC layout, like Cemu's first-run setup. The native
    # nn_save provider uses save/ for the current account and save/common/.
    # Directory creation preserves existing progress on subsequent installs.
    $folders = @(
        'save\common',
        'mlc01\sys',
        'mlc01\usr\title\00050000',
        'mlc01\usr\title\0005000c',
        'mlc01\usr\title\0005000e',
        'mlc01\usr\save\00050000',
        'mlc01\usr\boss',
        'mlc01\usr\save\00050010\1004a000\user\common\db',
        'mlc01\usr\save\00050010\1004a100\user\common\db',
        'mlc01\usr\save\00050010\1004a200\user\common\db',
        'mlc01\sys\title\0005001b\10042400\content',
        'mlc01\sys\title\0005001b\10056000\content',
        'mlc01\sys\title\0005001b\1005c000\content'
    )
    foreach ($folder in $folders) { Ensure-Folder (Join-Path $GameFolder $folder) }
}
function Ask-Folder([string]$Description, [string]$Default) {
    $dialog = $null
    $owner = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $Description
        $dialog.ShowNewFolderButton = $false
        if ($Default -and (Test-Path -LiteralPath $Default -PathType Container)) { $dialog.SelectedPath = $Default }
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        if ($dialog.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }
    } catch {
        Warn "The folder picker could not open: $($_.Exception.Message)"
    } finally {
        if ($dialog) { $dialog.Dispose() }
        if ($owner) { $owner.Dispose() }
    }
    return (Read-Host "      $Description (type or paste the full path)")
}
function File-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}
function Complete-GeneratedModule([string]$Directory) {
    foreach ($name in @('Gambit.h', 'Gambit_data.cpp', 'Gambit_register.cpp')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Directory $name) -PathType Leaf)) { return $false }
    }
    $registered = @(Select-String -LiteralPath (Join-Path $Directory 'Gambit_register.cpp') -Pattern '^\s+rbrew_register_func\(').Count
    return $registered -ge $MinimumFunctionCount
}
function Download([string]$Url, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) { return }
    Info "Downloading $(Split-Path -Leaf $Destination) ..."
    $partial = "$Destination.part"
    (New-Object Net.WebClient).DownloadFile($Url, $partial)
    Move-Item -LiteralPath $partial -Destination $Destination -Force
}
function Copy-Tree([string]$From, [string]$To) {
    & robocopy $From $To /E /NFL /NDL /NJH /NJS /NP /MT:8 | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "Copying $From failed (robocopy code $LASTEXITCODE)." }
    $global:LASTEXITCODE = 0
}
function System-ResourceRoots([string]$Dump, [string]$Destination, [string]$Source) {
    $roots = New-Object 'System.Collections.Generic.List[string]'
    $roots.Add((Join-Path $Destination 'mlc01'))
    foreach ($path in @($Source, $env:RBREW_SYSTEM_MLC_DIR, $env:RBREW_MLC_DIR)) {
        if ($path) { $roots.Add((Full-FolderPath $path)) }
    }
    # Locate an MLC or dumped wiiu-system/mlc beside the game/repository.
    # No folder names belonging to this developer's PC are assumed.
    foreach ($start in @($Dump, $Root)) {
        $parent = [IO.DirectoryInfo]::new($start)
        for ($depth = 0; $parent -and $depth -lt 5; $depth++) {
            $roots.Add($parent.FullName)
            $parent = $parent.Parent
        }
    }
    foreach ($base in @((Join-Path $env:APPDATA 'Cemu'), (Join-Path $env:LOCALAPPDATA 'Cemu'))) {
        $roots.Add($base)
        $settings = Join-Path $base 'settings.xml'
        if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) { continue }
        $reader = $null
        try {
            $options = New-Object System.Xml.XmlReaderSettings
            $options.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
            $options.XmlResolver = $null
            $reader = [System.Xml.XmlReader]::Create($settings, $options)
            $document = New-Object System.Xml.XmlDocument
            $document.XmlResolver = $null
            $document.Load($reader)
            $node = $document.SelectSingleNode('/content/mlc_path')
            if ($node -and $node.InnerText.Trim()) {
                $configured = $node.InnerText.Trim()
                if (-not [IO.Path]::IsPathRooted($configured)) { $configured = Join-Path $base $configured }
                $roots.Add($configured)
            }
        } catch {
            Warn "Could not read Cemu's custom MLC setting; continuing automatic setup."
        } finally {
            if ($reader) { $reader.Dispose() }
        }
    }
    return $roots | Select-Object -Unique
}
function Find-SystemResourceFiles([string[]]$Roots, [string]$Relative, [string[]]$Names) {
    foreach ($candidate in $Roots) {
        foreach ($suffix in @('', 'mlc01', 'mlc', 'wiiu-system\mlc')) {
            $base = $candidate
            if ($suffix) { $base = Join-Path $base $suffix }
            $directory = Join-Path $base $Relative
            $complete = $true
            foreach ($name in $Names) {
                $file = Join-Path $directory $name
                if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
                    (Get-Item -LiteralPath $file).Length -eq 0) { $complete = $false; break }
            }
            if ($complete) { return [IO.Path]::GetFullPath($directory) }
        }
    }
    return $null
}
function Copy-ResourceFiles([string]$From, [string]$To, [string[]]$Names) {
    Ensure-Folder $To
    foreach ($name in $Names) {
        $sourceFile = [IO.Path]::GetFullPath((Join-Path $From $name))
        $targetFile = [IO.Path]::GetFullPath((Join-Path $To $name))
        if (-not [string]::Equals($sourceFile, $targetFile, [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $sourceFile -Destination $targetFile -Force
        }
    }
}
function Prepare-WiiUResources([string]$Dump, [string]$Destination, [string]$Source) {
    Initialize-WiiUFolders $Destination
    $roots = @(System-ResourceRoots $Dump $Destination $Source)
    $fontRelative = 'sys\title\0005001b\10042400\content'
    $fontNames = @($FallbackFonts | ForEach-Object { $_.Name })
    $fontDestination = Join-Path $Destination ('mlc01\' + $fontRelative)
    $fontSource = Find-SystemResourceFiles $roots $fontRelative $fontNames
    if ($fontSource) {
        Copy-ResourceFiles $fontSource $fontDestination $fontNames
        Good "Shared fonts ready: $fontSource"
    } else {
        Info 'Installing the same Noto replacement fonts supplied with Cemu ...'
        $fontCache = Join-Path $Downloads 'shared-fonts'
        Ensure-Folder $fontCache
        foreach ($font in $FallbackFonts) {
            $file = Join-Path $fontCache $font.Name
            Download ($FontBaseUrl + '/' + $font.Name) $file
            if ((File-Sha256 $file) -ne $font.Sha256) {
                Remove-Item -LiteralPath $file -Force
                Fail "The replacement font $($font.Name) failed its integrity check. Run Setup.bat again to retry."
            }
        }
        Copy-ResourceFiles $fontCache $fontDestination $fontNames
        $licenses = Join-Path $Destination 'licenses'
        Ensure-Folder $licenses
        Copy-Item -LiteralPath (Join-Path $Root 'LICENSES\cemu-shared-fonts-OFL-1.1.txt') -Destination $licenses -Force
        Good 'Noto replacement fonts installed.'
    }
    # Cemu creates these directories without requiring a system-title dump.
    # Copy real Mii graphics if available; never invent resource/save data.
    $miiRelative = 'sys\title\0005001b\10056000\content'
    $miiNames = @('FFLResHigh.dat', 'FFLResHighLG.dat', 'FFLResMiddle.dat', 'FFLResMiddleLG.dat')
    $miiSource = Find-SystemResourceFiles $roots $miiRelative $miiNames
    if ($miiSource) {
        Copy-ResourceFiles $miiSource (Join-Path $Destination ('mlc01\' + $miiRelative)) $miiNames
        Good "Local Mii graphics found automatically: $miiSource"
    } else {
        Warn 'No local Mii graphics resources found; some Mii graphics may be unavailable.'
    }
    Good 'Wii U folders initialized automatically; no saves or accounts imported.'
}

# MEGA public links carry their AES key after '#': the file is AES-128-CTR
# encrypted. This helper downloads and decrypts in one streaming pass.
$MegaSource = @'
using System;
using System.IO;
using System.Net;
using System.Security.Cryptography;

public static class MegaDownload {
    static byte[] FromBase64Url(string s) {
        s = s.Replace('-', '+').Replace('_', '/');
        while (s.Length % 4 != 0) s += "=";
        return Convert.FromBase64String(s);
    }
    public static void Keys(string linkKey, out byte[] aesKey, out byte[] nonce) {
        byte[] k = FromBase64Url(linkKey);
        if (k.Length != 32) throw new Exception("Unexpected MEGA key length");
        aesKey = new byte[16];
        for (int i = 0; i < 16; i++) aesKey[i] = (byte)(k[i] ^ k[i + 16]);
        nonce = new byte[8];
        Array.Copy(k, 16, nonce, 0, 8);
    }
    public static void Fetch(string url, string linkKey, string destination, long expectedSize) {
        byte[] aesKey, nonce;
        Keys(linkKey, out aesKey, out nonce);
        using (Aes aes = Aes.Create()) {
            aes.Mode = CipherMode.ECB;
            aes.Padding = PaddingMode.None;
            aes.Key = aesKey;
            using (ICryptoTransform ecb = aes.CreateEncryptor()) {
                HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
                request.Timeout = 60000;
                request.ReadWriteTimeout = 120000;
                using (WebResponse response = request.GetResponse())
                using (Stream input = response.GetResponseStream())
                using (FileStream output = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20)) {
                    const int Chunk = 1 << 20;   // multiple of 16
                    byte[] data = new byte[Chunk];
                    byte[] counters = new byte[Chunk];
                    byte[] stream = new byte[Chunk];
                    long block = 0, total = 0;
                    int lastPercent = -1;
                    while (true) {
                        int filled = 0;
                        while (filled < Chunk) {
                            int n = input.Read(data, filled, Chunk - filled);
                            if (n <= 0) break;
                            filled += n;
                        }
                        if (filled == 0) break;
                        int blocks = (filled + 15) / 16;
                        for (int b = 0; b < blocks; b++) {
                            int o = b * 16;
                            Array.Copy(nonce, 0, counters, o, 8);
                            long c = block + b;
                            for (int i = 0; i < 8; i++) counters[o + 15 - i] = (byte)(c >> (8 * i));
                        }
                        ecb.TransformBlock(counters, 0, blocks * 16, stream, 0);
                        for (int i = 0; i < filled; i++) data[i] ^= stream[i];
                        output.Write(data, 0, filled);
                        block += blocks;
                        total += filled;
                        if (expectedSize > 0) {
                            int percent = (int)(total * 100 / expectedSize);
                            if (percent != lastPercent && percent % 5 == 0) {
                                Console.WriteLine("      " + percent + "%  (" + (total >> 20) + " / " + (expectedSize >> 20) + " MB)");
                                lastPercent = percent;
                            }
                        }
                        if (filled < Chunk) break;
                    }
                }
            }
        }
    }
}
'@

function Get-MegaFile([string]$Handle, [string]$LinkKey, [string]$Destination, [long]$ExpectedSize) {
    if (-not ('MegaDownload' -as [type])) { Add-Type -TypeDefinition $MegaSource -Language CSharp }
    $body = '[{"a":"g","g":1,"p":"' + $Handle + '"}]'
    $reply = Invoke-RestMethod -Method Post -Uri ("https://g.api.mega.co.nz/cs?id=" + (Get-Random)) -Body $body -ContentType 'application/json'
    if ($reply -is [int] -or -not $reply[0].g) { Fail "MEGA refused the shader download (reply: $reply). The link may be over its quota; try again later." }
    $partial = "$Destination.part"
    [MegaDownload]::Fetch($reply[0].g, $LinkKey, $partial, $ExpectedSize)
    Move-Item -LiteralPath $partial -Destination $Destination -Force
}

# ---------------------------------------------------------------------------
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host '   Splatoon 1 PC Port - setup' -ForegroundColor Magenta
Write-Host '   Uses only YOUR OWN game files. Keep this window open.' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

if (-not [Environment]::Is64BitOperatingSystem) { Fail 'A 64-bit Windows 10 or 11 is required.' }
if ($Clean -and (Test-Path -LiteralPath $Work)) {
    Info 'Removing previous build outputs (-Clean) ...'
    Remove-Item -LiteralPath $Work -Recurse -Force
}
Ensure-Folder $Downloads

# ---------------------------------------------------------------------------
Step 'Checking the tools needed to build'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = $null
if (Test-Path -LiteralPath $vswhere) {
    $found = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json | ConvertFrom-Json
    if ($found) { $vs = @($found)[0] }
}
$python = $null
foreach ($candidate in @(@('py', '-3'), @('python'))) {
    if (-not (Get-Command $candidate[0] -ErrorAction SilentlyContinue)) { continue }
    $extra = @(); if ($candidate.Count -gt 1) { $extra = $candidate[1..($candidate.Count - 1)] }
    $ok = $null
    try {
        $ErrorActionPreference = 'Continue'
        $ok = & $candidate[0] @extra -c "import sys; print(int(sys.version_info >= (3, 12)))" 2>$null
    } catch { $ok = $null } finally { $ErrorActionPreference = 'Stop' }
    if ("$ok".Trim() -eq '1') { $python = $candidate; break }
}
$git = Get-Command git -ErrorAction SilentlyContinue

$missing = @()
if (-not $vs) { $missing += @{ Name = 'Visual Studio 2022 Build Tools (C++ workload)'; Id = 'Microsoft.VisualStudio.2022.BuildTools'; Extra = '--override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"' } }
if (-not $python) { $missing += @{ Name = 'Python 3.12'; Id = 'Python.Python.3.12'; Extra = '' } }
if (-not $git) { $missing += @{ Name = 'Git'; Id = 'Git.Git'; Extra = '' } }
if ($missing.Count) {
    Warn 'These programs are missing:'
    foreach ($m in $missing) { Warn "  - $($m.Name)" }
    if ((Get-Command winget -ErrorAction SilentlyContinue) -and (Ask-YesNo 'Install them now automatically?')) {
        foreach ($m in $missing) {
            Info "Installing $($m.Name) ..."
            $wingetArgs = "install --id $($m.Id) -e --accept-package-agreements --accept-source-agreements $($m.Extra)"
            Start-Process winget -ArgumentList $wingetArgs -Wait -NoNewWindow
        }
        Good 'Done. Close this window and run Setup.bat again so Windows picks up the new programs.'
        exit 0
    }
    Fail 'Install the programs listed above (see README), then run Setup.bat again.'
}
$vsMajor = [int]($vs.installationVersion.Split('.')[0])
switch ($vsMajor) {
    17 { $generator = 'Visual Studio 17 2022' }
    18 { $generator = 'Visual Studio 18 2026' }
    default { Fail "Visual Studio version $vsMajor is not supported. Install Visual Studio 2022 (or newer) Build Tools." }
}
$cmake = Join-Path $vs.installationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
if (-not (Test-Path -LiteralPath $cmake)) {
    $cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
    if (-not $cmakeCommand) { Fail 'CMake was not found. Re-run the Visual Studio Installer and add "C++ CMake tools for Windows".' }
    $cmake = $cmakeCommand.Source
}
$pyExe = $python[0]; $pyArgs = @(); if ($python.Count -gt 1) { $pyArgs = $python[1..($python.Count - 1)] }
Good "Visual Studio $($vs.installationVersion), $generator"
Good "Python: $(& $pyExe @pyArgs --version)"
Good "Git: $((& git --version))"

# ---------------------------------------------------------------------------
Step 'Finding your game files'
if (-not $GameDump) {
    Info 'Select the folder of your Splatoon dump. It must contain the folders code, content and meta.'
    $GameDump = Ask-Folder 'Select your Splatoon game dump folder (contains code, content, meta)' $Root
}
# Folder names are arbitrary. Use literal paths throughout setup so names
# containing brackets (common in game dumps) are never treated as wildcards.
$GameDump = Full-FolderPath $GameDump
if (-not $GameDump) { Fail 'No game folder was selected.' }
if (-not (Test-Path -LiteralPath $GameDump -PathType Container)) { Fail "The game dump folder does not exist: $GameDump" }
foreach ($folder in @('code', 'content', 'meta')) {
    if (-not (Test-Path -LiteralPath (Join-Path $GameDump $folder) -PathType Container)) {
        Fail "Your dump is missing the $folder folder. Select the folder that contains code, content and meta; its name does not matter."
    }
}
$rpx = Join-Path $GameDump 'code\Gambit.rpx'
foreach ($required in @($rpx, (Join-Path $GameDump 'meta\meta.xml'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { Fail "Your dump is missing $required. Select the folder that contains code, content and meta." }
}
Info 'Checking the game version (this takes a few seconds) ...'
$rpxHash = File-Sha256 $rpx
if ($rpxHash -ne $SupportedRpxSha256) {
    Fail "Unsupported game version. Only Splatoon EUR (AGMP01) with update v16 (288) is supported. Your code\Gambit.rpx hash is $rpxHash."
}
Good 'Supported game: Splatoon (EUR, AGMP01, v16).'

if (-not $Output) { $Output = Join-Path $Root 'Game' }
$Output = Full-FolderPath $Output
if (-not $Output) { Fail 'No output folder was specified.' }
if (Test-Path -LiteralPath $Output -PathType Leaf) { Fail "The output path is a file, not a folder: $Output" }
Info "The game will be installed to: $Output"
Prepare-WiiUResources $GameDump $Output $Mlc

# ---------------------------------------------------------------------------
Step 'Installing open-source libraries (vcpkg: zlib, curl, volk, Vulkan headers)'
$vcpkgRoot = Join-Path $Work 'vcpkg'
$vcpkg = Join-Path $vcpkgRoot 'vcpkg.exe'
if (-not (Test-Path -LiteralPath $vcpkg)) {
    if (-not (Test-Path -LiteralPath (Join-Path $vcpkgRoot '.git'))) {
        & git clone --depth 1 $VcpkgUrl $vcpkgRoot; Check-Exit 'Downloading vcpkg'
    }
    & (Join-Path $vcpkgRoot 'bootstrap-vcpkg.bat') -disableMetrics; Check-Exit 'Preparing vcpkg'
}
& $vcpkg install @VcpkgPackages --triplet x64-windows --disable-metrics; Check-Exit 'Installing vcpkg libraries'
$toolchain = Join-Path $vcpkgRoot 'scripts\buildsystems\vcpkg.cmake'

# ---------------------------------------------------------------------------
Step 'Building the window and shader-compiler libraries (SDL2, glslang)'
$deps = Join-Path $Work 'deps'
$sdlMarker = Join-Path $deps 'sdl2-vulkan\cmake\SDL2VulkanOnly.cmake'
$glslangMarker = Join-Path $deps 'glslang-vulkan\lib\cmake\glslang\GlslangVulkanOnly.cmake'
if (-not ((Test-Path -LiteralPath $sdlMarker) -and (Test-Path -LiteralPath $glslangMarker))) {
    $sdlZip = Join-Path $Downloads 'SDL2-2.32.10.zip'
    $glslangArchive = Join-Path $Downloads 'glslang-16.4.0.tar.gz'
    Download $SdlUrl $sdlZip
    Download $GlslangUrl $glslangArchive
    $sdlSource = Join-Path $Downloads 'SDL2-2.32.10'
    if (-not (Test-Path -LiteralPath $sdlSource)) { Expand-Archive -LiteralPath $sdlZip -DestinationPath $Downloads }
    $depsBuild = Join-Path $Work 'deps-build'
    if (Test-Path -LiteralPath $depsBuild) { Remove-Item -LiteralPath $depsBuild -Recurse -Force }   # restart an interrupted build cleanly
    & $pyExe @pyArgs (Join-Path $Recompiler 'tools\build_vulkan_dependencies.py') --sdl-source $sdlSource --glslang-archive $glslangArchive --build-root $depsBuild --prefix $deps --generator $generator --cmake $cmake
    Check-Exit 'Building SDL2/glslang'
}
Good 'Libraries ready.'

# ---------------------------------------------------------------------------
Step 'Building the recompiler (RebrewU)'
$rebrewuBuild = Join-Path $Work 'rebrewu'
& $cmake -S $Recompiler -B $rebrewuBuild -G $generator -A x64 "-DCMAKE_TOOLCHAIN_FILE=$toolchain" -DVCPKG_TARGET_TRIPLET=x64-windows -DREBREWU_BUILD_TESTS=OFF
Check-Exit 'Configuring the recompiler'
& $cmake --build $rebrewuBuild --config Release --target rebrewu --parallel
Check-Exit 'Building the recompiler'
$rebrewu = Get-ChildItem -LiteralPath $rebrewuBuild -Recurse -Filter rebrewu.exe | Select-Object -First 1
if (-not $rebrewu) { Fail 'rebrewu.exe was not produced.' }
Good "Recompiler: $($rebrewu.FullName)"

# ---------------------------------------------------------------------------
Step 'Recompiling your Gambit.rpx into C++ (a few minutes)'
$generated = Join-Path $Work 'generated\Gambit'
$stamp = Join-Path $Work 'generated\source.sha256'
if (-not (Test-Path -LiteralPath $BoundaryProfile -PathType Leaf)) { Fail 'The supported-game boundary profile is missing. Extract the complete repository ZIP, including profiles, and retry.' }
# The profile is address metadata, not game code. The RPX hash above selects
# its supported version; RebrewU still validates each boundary against the RPX.
# Include it in the stamp so incomplete builds made without it regenerate.
$current = $rpxHash + ':' + (File-Sha256 $rebrewu.FullName) + ':' + (File-Sha256 $BoundaryProfile)
if (-not ((Complete-GeneratedModule $generated) -and (Test-Path -LiteralPath $stamp) -and ((Get-Content -LiteralPath $stamp -Raw).Trim() -eq $current))) {
    # A fresh folder avoids stale parts from an older, larger generation.
    if (Test-Path -LiteralPath (Join-Path $Work 'generated')) { Remove-Item -LiteralPath (Join-Path $Work 'generated') -Recurse -Force }
    Ensure-Folder $generated
    & $rebrewu.FullName recompile --rpx $rpx --output $generated --analyzer-entries $BoundaryProfile
    Check-Exit 'Recompiling Gambit.rpx'
    if (-not (Complete-GeneratedModule $generated)) { Fail 'The recompiler did not produce the complete supported-game function table. Installation stopped before building an incomplete game.' }
    Set-Content -LiteralPath $stamp -Value $current -Encoding ASCII
}
Good 'Game code recompiled (stays on your PC, inside build\generated).'

# ---------------------------------------------------------------------------
Step 'Building the game (this is the long part: 15-60 minutes)'
$gameBuild = Join-Path $Work 'game'
& $cmake -S (Join-Path $Recompiler 'port') -B $gameBuild -G $generator -A x64 "-DCMAKE_TOOLCHAIN_FILE=$toolchain" -DVCPKG_TARGET_TRIPLET=x64-windows `
    -DRBREW_GRAPHICS_BACKEND=Vulkan "-DGAMBIT_GENERATED_DIR=$generated" "-DSDL2_DIR=$(Split-Path $sdlMarker)" "-Dglslang_DIR=$(Split-Path $glslangMarker)" `
    -DRBREW_BUILD_GAME=ON -DRBREW_ENABLE_COVERAGE=OFF -DRBREW_ENABLE_PPC_FALLBACK=OFF -DRBREW_DIAGNOSTIC_RUNTIME=OFF -DRBREW_TEXTURE_DIAGNOSTICS=OFF
Check-Exit 'Configuring the game'
& $cmake --build $gameBuild --config Release --target Gambit --parallel
Check-Exit 'Building the game'
$exe = Get-ChildItem -LiteralPath $gameBuild -Recurse -Filter Splatoon.exe | Where-Object { $_.FullName -match '\\Release\\' } | Select-Object -First 1
if (-not $exe) { Fail 'Splatoon.exe was not produced.' }
Good "Built: $($exe.FullName)"

# ---------------------------------------------------------------------------
Step 'Creating the game folder'
Ensure-Folder $Output
Initialize-WiiUFolders $Output
Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $Output 'Splatoon.exe') -Force
# Any library DLLs the build placed next to the executable (normally none).
Get-ChildItem -LiteralPath $exe.DirectoryName -Filter *.dll | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $Output -Force }
# Microsoft C++ runtime, copied from your Visual Studio install.
$crt = Get-ChildItem -LiteralPath (Join-Path $vs.installationPath 'VC\Redist\MSVC') -Recurse -Directory -Filter 'Microsoft.VC14*.CRT' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\' -and $_.FullName -notmatch 'onecore|debug' } | Sort-Object FullName -Descending | Select-Object -First 1
if ($crt) {
    foreach ($dll in @('msvcp140.dll', 'msvcp140_atomic_wait.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        $source = Join-Path $crt.FullName $dll
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $Output -Force }
    }
} else { Warn 'Could not find the Visual C++ runtime DLLs; install the "Microsoft Visual C++ Redistributable (x64)" if the game does not start.' }
Info 'Copying game content (about 1.7 GB) ...'
Copy-Tree (Join-Path $GameDump 'content') (Join-Path $Output 'content')
Copy-Tree (Join-Path $GameDump 'meta') (Join-Path $Output 'meta')
Good 'Wii U folders ready. No existing game or Mii saves were imported.'
Good 'A new installation starts fresh; progress already in this output folder is kept on updates.'

# ---------------------------------------------------------------------------
Step 'Downloading the prebuilt shader cache (about 820 MB, unpacks to about 4.5 GB)'
$cacheDir = Join-Path $Output 'vulkan_cache'
if ($SkipShaders) {
    Warn 'Skipped (-SkipShaders). The game will build shaders while you play, with more stutter at first.'
} elseif (Test-Path -LiteralPath (Join-Path $cacheDir 'spirv') -PathType Container) {
    Good 'Shader cache already installed; keeping it.'
} else {
    $zip = Join-Path $Downloads 'vulkan_cache.zip'
    if ((Test-Path -LiteralPath $zip) -and ((Get-Item -LiteralPath $zip).Length -ne $ShaderZipSize)) { Remove-Item -LiteralPath $zip -Force }
    if (-not (Test-Path -LiteralPath $zip)) {
        Info 'Downloading from MEGA ...'
        Get-MegaFile $ShaderMegaHandle $ShaderMegaKey $zip $ShaderZipSize
    }
    Info 'Verifying the download ...'
    if ((File-Sha256 $zip) -ne $ShaderZipSha256) {
        Remove-Item -LiteralPath $zip -Force
        Fail 'The shader download is damaged. Run Setup.bat again to retry.'
    }
    Info 'Unpacking (this can take a few minutes) ...'
    & tar.exe -xf $zip -C $Output
    Check-Exit 'Unpacking the shader cache'
    if (-not (Test-Path -LiteralPath (Join-Path $cacheDir 'spirv') -PathType Container)) { Fail 'The shader cache did not unpack into vulkan_cache.' }
    Good 'Shader cache installed.'
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host '   Setup complete!' -ForegroundColor Green
Write-Host "   Play: $(Join-Path $Output 'Splatoon.exe')" -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
if (Ask-YesNo 'Create a desktop shortcut?') {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Splatoon PC Port.lnk'))
    $shortcut.TargetPath = Join-Path $Output 'Splatoon.exe'
    $shortcut.WorkingDirectory = $Output
    $shortcut.Save()
    Good 'Shortcut created on your desktop.'
}
