# ============================================================
#  Gogurt's 6 Player MTG Table - Installer
#  Installs or updates the mod straight from GitHub, patched
#  with your own Cloudflare Worker URL.
# ============================================================
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRaw  = 'https://raw.githubusercontent.com/gogurt1984/Tabletop-MTG-Mod---Temp-Fix/main'
$ModName  = "Gogurt's 6 Player MTG Table"
$FileBase = 'GogurtsMTGTable'

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host "  $ModName - Installer" -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ''

# ---- Locate the TTS Workshop folder -------------------------------
$docs = [Environment]::GetFolderPath('MyDocuments')
$workshop = Join-Path $docs 'My Games\Tabletop Simulator\Mods\Workshop'
if (-not (Test-Path $workshop)) {
    Write-Host "Could not find the Tabletop Simulator Workshop folder at:" -ForegroundColor Yellow
    Write-Host "  $workshop" -ForegroundColor Yellow
    Write-Host "Make sure Tabletop Simulator has been run at least once." -ForegroundColor Yellow
    $ans = Read-Host 'Create the folder anyway and continue? (y/n)'
    if ($ans -notmatch '^[Yy]') { Write-Host 'Install cancelled.'; return }
    New-Item -ItemType Directory -Force -Path $workshop | Out-Null
}

$modPath = Join-Path $workshop "$FileBase.json"
$pngPath = Join-Path $workshop "$FileBase.png"
$alreadyInstalled = Test-Path $modPath

# ---- Choose install mode -------------------------------------------
# Existing install -> update it in place, keeping the worker URL.
# No install found -> fresh install, which prompts for a worker URL.
if ($alreadyInstalled) {
    Write-Host 'Existing install found - updating it to the latest version.' -ForegroundColor Green
    $mode = 'update'
} else {
    Write-Host 'No existing install found - doing a fresh install.' -ForegroundColor Green
    $mode = 'fresh'
}

# ---- Get the worker URL --------------------------------------------
$workerHost = $null
if ($mode -eq 'update') {
    # Reuse the worker URL from the currently installed file
    $existing = [IO.File]::ReadAllText($modPath)
    $m = [regex]::Match($existing, 'https://([^/"\\'']+)/img/')
    if ($m.Success -and $m.Groups[1].Value -ne 'YOUR_WORKER_URL_HERE') {
        $workerHost = $m.Groups[1].Value
        Write-Host "Using your existing worker URL: $workerHost" -ForegroundColor Green
    } else {
        Write-Host 'Could not detect the worker URL in your existing install.' -ForegroundColor Yellow
        $mode = 'fresh'
    }
}

if (-not $workerHost) {
    Write-Host ''
    Write-Host 'You need a (free) Cloudflare Worker running the proxy script.'
    Write-Host 'See the README for setup: https://github.com/gogurt1984/Tabletop-MTG-Mod---Temp-Fix'
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
Invoke-WebRequest -Uri "$RepoRaw/2293586471.json" -OutFile $tmp -UseBasicParsing
$json = [IO.File]::ReadAllText($tmp)
Remove-Item $tmp -Force

# ---- Patch in the worker URL and install ---------------------------
$json = $json.Replace('YOUR_WORKER_URL_HERE', $workerHost)
[IO.File]::WriteAllText($modPath, $json)
Write-Host "Installed mod file: $modPath" -ForegroundColor Green

# Thumbnail (optional - skip silently if missing from the repo)
try {
    Invoke-WebRequest -Uri "$RepoRaw/2293586471.png" -OutFile $pngPath -UseBasicParsing
    Write-Host 'Installed thumbnail.' -ForegroundColor Green
} catch { }

# ---- Register the mod in WorkshopFileInfos.json ---------------------
$wfiPath = Join-Path $workshop 'WorkshopFileInfos.json'
$entries = @()
if (Test-Path $wfiPath) {
    try {
        $parsed = [IO.File]::ReadAllText($wfiPath) | ConvertFrom-Json
        # Keep every entry that isn't a previous install of this mod
        $entries = @($parsed | Where-Object { $_.Name -ne $ModName -and $_.Directory -notlike "*$FileBase.json" })
    } catch {
        Write-Host 'Warning: existing WorkshopFileInfos.json could not be read - rebuilding it.' -ForegroundColor Yellow
    }
}
$entries += [pscustomobject]@{
    Directory  = $modPath
    Name       = $ModName
    UpdateTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}
[IO.File]::WriteAllText($wfiPath, (ConvertTo-Json -InputObject $entries -Depth 5))
Write-Host 'Registered the mod with Tabletop Simulator.' -ForegroundColor Green

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
Write-Host "In Tabletop Simulator: Create > Games > Workshop > `"$ModName`""
Write-Host 'Run this installer again any time to grab the latest version.'
Write-Host ''
