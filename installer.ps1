# ============================================================
#  Gogurt's 6 Player MTG Table - Installer
#  Installs or updates the mod straight from GitHub, patched
#  with your own Cloudflare Worker URL.
# ============================================================
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRaw  = 'https://raw.githubusercontent.com/gogurt1984/Tabletop-MTG---Gogurts-DIY-Table/main'
$ModName  = "Gogurt's 6 Player MTG Table"
$FileBase = 'GogurtsMTGTable'

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host "  $ModName - Installer" -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ''

# ---- Locate the TTS Workshop folder -------------------------------
# TTS's "Mod Save Location" setting (Settings > Game) stores mods either in
# Documents (Location=0, default) or in the Steam game folder itself
# (Location=1, "Game Data"). The setting lives in TTS's PlayerPrefs in the
# registry, so it can be read directly.

$docsWorkshop = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Tabletop Simulator\Mods\Workshop'

# Resolve the Game Data location by finding the TTS install via Steam's registry
# entry and library list.
$gameDataWorkshop = $null
try {
    $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath -replace '/', '\'
    $libs = @($steamPath)
    $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        $libs += [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value.Replace('\\', '\') }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $ttsDir = Join-Path $lib 'steamapps\common\Tabletop Simulator\Tabletop Simulator_Data'
        if (Test-Path $ttsDir) {
            $gameDataWorkshop = Join-Path $ttsDir 'Mods\Workshop'
            break
        }
    }
} catch { }

# Read the Mod Save Location setting from TTS's PlayerPrefs.
# Unity suffixes the value name with a hash, so match on the prefix.
$modLocation = $null
try {
    $prefs = Get-Item 'HKCU:\Software\Berserk Games\Tabletop Simulator' -ErrorAction Stop
    $prop = $prefs.Property | Where-Object { $_ -like 'ConfigGame_h*' } | Select-Object -First 1
    if ($prop) {
        $v = $prefs.GetValue($prop)
        if ($v -is [byte[]]) { $v = [System.Text.Encoding]::UTF8.GetString($v).Trim([char]0) }
        $cfg = "$v" | ConvertFrom-Json
        if ($cfg.ConfigMods -and $null -ne $cfg.ConfigMods.Location) {
            $modLocation = [int]$cfg.ConfigMods.Location
        }
    }
} catch { }

# TTS's log files record the mods path actually in use - a fallback signal
# that also catches fully custom locations.
$logDetected = $null
$logDir = Join-Path $env:USERPROFILE 'AppData\LocalLow\Berserk Games\Tabletop Simulator'
foreach ($log in @('Player.log', 'Player-prev.log')) {
    if ($logDetected) { break }
    $logPath = Join-Path $logDir $log
    if (-not (Test-Path $logPath)) { continue }
    $m = Select-String -Path $logPath -Pattern '([A-Za-z]:[\\/][^"<>|:*?]*?[\\/]Mods)[\\/]' | Select-Object -First 1
    if ($m) {
        $candidate = Join-Path ($m.Matches[0].Groups[1].Value -replace '[\\/]+', '\') 'Workshop'
        if (Test-Path $candidate) { $logDetected = $candidate }
    }
}

$workshop = $null

# 1. TTS's own setting is authoritative when it can be read.
if ($modLocation -eq 1 -and $gameDataWorkshop) {
    $workshop = $gameDataWorkshop
    Write-Host 'TTS is set to store mods in Game Data (the Steam game folder).'
} elseif ($modLocation -eq 0) {
    $workshop = $docsWorkshop
}

# 2. Otherwise trust the location TTS's logs say it is using.
if (-not $workshop -and $logDetected) { $workshop = $logDetected }

# 3. Otherwise use whichever standard location exists; ask if both do.
if (-not $workshop) {
    $existing = @( @($docsWorkshop, $gameDataWorkshop) | Where-Object { $_ -and (Test-Path $_) } )
    if ($existing.Count -eq 1) {
        $workshop = $existing[0]
    } elseif ($existing.Count -ge 2) {
        Write-Host 'TTS can store mods in Documents or in Game Data, and both folders exist'
        Write-Host 'on this PC. Check Settings > Game > Mod Save Location in TTS if unsure.'
        Write-Host ''
        Write-Host "  [1] Documents - $docsWorkshop"
        Write-Host "  [2] Game Data - $gameDataWorkshop"
        Write-Host ''
        $choice = Read-Host 'Where should the mod be installed? (1/2)'
        if ($choice -eq '2') { $workshop = $gameDataWorkshop } else { $workshop = $docsWorkshop }
    }
}

# 4. Nothing found anywhere - ask for a custom path.
if (-not $workshop) {
    Write-Host 'Could not find a Tabletop Simulator Workshop folder on this PC.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'If you moved your TTS data to a custom location, paste your Mods\Workshop'
    Write-Host 'folder path below. Otherwise, make sure Tabletop Simulator has been run at'
    Write-Host 'least once, then run this installer again.'
    Write-Host ''
    while (-not $workshop) {
        $custom = Read-Host 'Paste your Mods\Workshop folder path (or press Enter to cancel)'
        $custom = $custom.Trim().Trim('"')
        if (-not $custom) { Write-Host 'Install cancelled.'; return }
        if ((Test-Path $custom) -and (Split-Path $custom -Leaf) -eq 'Workshop') {
            $workshop = $custom
        } elseif (Test-Path (Join-Path $custom 'Mods\Workshop')) {
            # They pasted the Tabletop Simulator root folder - accept that too
            $workshop = Join-Path $custom 'Mods\Workshop'
        } else {
            Write-Host 'That folder does not exist or is not a Workshop folder - try again.' -ForegroundColor Yellow
        }
    }
}

Write-Host "Installing to: $workshop" -ForegroundColor Green

$modPath = Join-Path $workshop "$FileBase.json"
$pngPath = Join-Path $workshop "$FileBase.png"

# ---- Find existing installs (here or in the other location) --------
# If the user switched Mod Save Location after installing, the old copy lives
# in the other folder - treat that as an update and migrate it over.
$allLocations = @( @($workshop, $docsWorkshop, $gameDataWorkshop, $logDetected) | Where-Object { $_ } | Select-Object -Unique )
$existingInstalls = @( $allLocations | Where-Object { Test-Path (Join-Path $_ "$FileBase.json") } )

if ($existingInstalls.Count -gt 0) {
    if ($existingInstalls -contains $workshop) {
        Write-Host 'Existing install found - updating it to the latest version.' -ForegroundColor Green
    } else {
        Write-Host "Existing install found in your previous mods location - moving it here." -ForegroundColor Green
    }
    $mode = 'update'
} else {
    Write-Host 'No existing install found - doing a fresh install.' -ForegroundColor Green
    $mode = 'fresh'
}

# ---- Get the worker URL --------------------------------------------
$workerHost = $null
if ($mode -eq 'update') {
    # Reuse the worker URL from any existing install
    foreach ($loc in $existingInstalls) {
        $existing = [IO.File]::ReadAllText((Join-Path $loc "$FileBase.json"))
        $m = [regex]::Match($existing, 'https://([^/"\\'']+)/img/')
        if ($m.Success -and $m.Groups[1].Value -ne 'YOUR_WORKER_URL_HERE') {
            $workerHost = $m.Groups[1].Value
            Write-Host "Using your existing worker URL: $workerHost" -ForegroundColor Green
            break
        }
    }
    if (-not $workerHost) {
        Write-Host 'Could not detect the worker URL in your existing install.' -ForegroundColor Yellow
        $mode = 'fresh'
    }
}

if (-not $workerHost) {
    Write-Host ''
    Write-Host 'You need a (free) Cloudflare Worker running the proxy script.'
    Write-Host 'See the README for setup: https://github.com/gogurt1984/Tabletop-MTG---Gogurts-DIY-Table'
    Write-Host ''
    while (-not $workerHost) {
        $raw = Read-Host 'Paste your worker URL (e.g. https://my-proxy.username.workers.dev)'
        $raw = $raw.Trim().TrimEnd('/')
        $raw = $raw -replace '^https?://', ''
        if ($raw -match '^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') {
            $workerHost = $raw
        } else {
            Write-Host 'That does not look like a valid URL - try again.' -ForegroundColor Yellow
        }
    }
}

# ---- Quick sanity check on the worker ------------------------------
try {
    $probe = Invoke-WebRequest -Uri "https://$workerHost/" -UseBasicParsing -TimeoutSec 15
    if ($probe.Content -match 'Scryfall Proxy') {
        Write-Host 'Worker check: OK' -ForegroundColor Green
    } else {
        Write-Host 'Warning: the worker responded but does not look like the proxy script.' -ForegroundColor Yellow
    }
} catch {
    Write-Host "Warning: could not reach https://$workerHost/ - continuing anyway." -ForegroundColor Yellow
}

# ---- Download the latest mod file from GitHub ----------------------
Write-Host ''
Write-Host 'Downloading the latest mod file from GitHub...'
$tmp = Join-Path $env:TEMP 'gogurt-mtg-table.json'
# ?nocache busts GitHub's raw CDN cache (5 min) so updates are picked up instantly
Invoke-WebRequest -Uri "$RepoRaw/2293586471.json?nocache=$(Get-Random)" -OutFile $tmp -UseBasicParsing
$json = [IO.File]::ReadAllText($tmp)
Remove-Item $tmp -Force

# ---- Patch in the worker URL and install ---------------------------
if (-not (Test-Path $workshop)) { New-Item -ItemType Directory -Force -Path $workshop | Out-Null }
$json = $json.Replace('YOUR_WORKER_URL_HERE', $workerHost)
[IO.File]::WriteAllText($modPath, $json)
Write-Host "Installed mod file: $modPath" -ForegroundColor Green

# Thumbnail (optional - skip silently if missing from the repo)
try {
    Invoke-WebRequest -Uri "$RepoRaw/2293586471.png?nocache=$(Get-Random)" -OutFile $pngPath -UseBasicParsing
    Write-Host 'Installed thumbnail.' -ForegroundColor Green
} catch { }

# ---- Register the mod in WorkshopFileInfos.json ---------------------
function Register-Mod([string]$folder, [string]$dir, [string]$name) {
    $wfiPath = Join-Path $folder 'WorkshopFileInfos.json'
    $entries = @()
    if (Test-Path $wfiPath) {
        try {
            $parsed = [IO.File]::ReadAllText($wfiPath) | ConvertFrom-Json
            # Keep every entry that isn't a previous install of this mod
            $entries = @($parsed | Where-Object { $_.Name -ne $name -and $_.Directory -notlike "*$FileBase.json" })
        } catch {
            Write-Host 'Warning: existing WorkshopFileInfos.json could not be read - rebuilding it.' -ForegroundColor Yellow
        }
    }
    if ($dir) {
        $entries += [pscustomobject]@{
            Directory  = $dir
            Name       = $name
            UpdateTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        }
    }
    [IO.File]::WriteAllText($wfiPath, (ConvertTo-Json -InputObject $entries -Depth 5))
}

Register-Mod $workshop $modPath $ModName
Write-Host 'Registered the mod with Tabletop Simulator.' -ForegroundColor Green

# ---- Clean up stale copies in other locations -----------------------
foreach ($loc in $existingInstalls) {
    if ($loc -eq $workshop) { continue }
    Remove-Item (Join-Path $loc "$FileBase.json") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $loc "$FileBase.png") -Force -ErrorAction SilentlyContinue
    Register-Mod $loc $null $ModName   # remove its WorkshopFileInfos entry
    Write-Host "Removed the old copy from: $loc"
}

# ---- Done ----------------------------------------------------------
Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
if ($mode -eq 'update') {
    Write-Host '  Update complete!' -ForegroundColor Cyan
} else {
    Write-Host '  Install complete!' -ForegroundColor Cyan
}
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Run this installer again any time to grab the latest version.'
Write-Host ''
