<#
    Prepares the uTPro SQLite sandbox on Windows.

      1. Loads sandbox.config.json, or (first run) asks a few questions and saves it.
         Anything left blank keeps the safe default (SQLite, localhost, no SMTP,
         install wizard). The saved file means the 2nd run never asks again.
      2. Downloads the latest uTPro release publish asset and extracts it to publish/.
      3. Generates publish/appsettings.Production.json from the config.
      4. (Optional) adds utpro.local / bo.utpro.local to the hosts file.
      5. Creates an empty SQLite database file when SQLite is used.
#>
param(
    [string]$Repo = 'T4VN/uTPro',
    [string]$PublishDir = 'publish',
    [string]$AppDll = 'uTPro.Project.Web.dll',
    [string]$ConfigFile = 'sandbox.config.json',
    [string]$VersionFile = '.utpro-release',
    [switch]$Reconfigure
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$headers = @{ 'User-Agent' = 'uTPro-Sandbox' }

# Data folders (relative to publish/) preserved by an "update but keep data" refresh.
$DataPaths = @('umbraco\Data', 'wwwroot\media', 'media')

function Ask([string]$prompt, [string]$default = '') {
    $label = if ($default) { "$prompt [$default]" } else { $prompt }
    $value = Read-Host $label
    if ([string]::IsNullOrWhiteSpace($value)) { return $default } else { return $value.Trim() }
}
function AskYesNo([string]$prompt) {
    $value = Read-Host "$prompt (y/N)"
    return ($value -match '^(y|yes)$')
}

# Version tag currently installed (from the marker file), or $null if unknown / not installed.
function Get-InstalledVersion([string]$publishFull, [string]$versionFile) {
    $marker = Join-Path $publishFull $versionFile
    if (Test-Path $marker) { return (Get-Content $marker -Raw).Trim() }
    return $null
}

# Download the given release's publish_output asset and lay it down in publish/.
# -PreserveData copies umbraco\Data / media back over the fresh extract (keep DB + uploads).
function Install-Release($release, [string]$publishFull, [string]$appDll, [string]$versionFile, $dataPaths, $headers, [switch]$PreserveData) {
    $asset = $release.assets | Where-Object { $_.name -like 'publish_output*.zip' } | Select-Object -First 1
    if ($null -eq $asset) { throw "No 'publish_output*.zip' asset found on release $($release.tag_name)." }

    $guid   = [guid]::NewGuid().ToString('N')
    $tmpZip = Join-Path $env:TEMP "utpro-publish-$guid.zip"
    $tmpDir = Join-Path $env:TEMP "utpro-publish-$guid"
    $bakDir = Join-Path $env:TEMP "utpro-data-$guid"

    Write-Host "Downloading $($asset.name) ($([math]::Round($asset.size/1MB)) MB)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip -Headers $headers -TimeoutSec 1800

    Write-Host "Extracting..."
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
    $root = Get-ChildItem -Path $tmpDir -Directory | Select-Object -First 1
    if ($null -eq $root) { throw "Unexpected archive layout." }

    # Back up the data folders before we wipe the old publish output.
    if ($PreserveData -and (Test-Path $publishFull)) {
        foreach ($rel in $dataPaths) {
            $src = Join-Path $publishFull $rel
            if (Test-Path $src) {
                $dst = Join-Path $bakDir $rel
                New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
                Copy-Item -Path $src -Destination $dst -Recurse -Force
            }
        }
    }

    # Replace the publish folder with the fresh extract.
    if (Test-Path $publishFull) { Remove-Item $publishFull -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $publishFull | Out-Null
    Copy-Item -Path (Join-Path $root.FullName '*') -Destination $publishFull -Recurse -Force

    # Restore the preserved data on top of the new release.
    if ($PreserveData -and (Test-Path $bakDir)) {
        foreach ($rel in $dataPaths) {
            $src = Join-Path $bakDir $rel
            if (Test-Path $src) {
                $dst = Join-Path $publishFull $rel
                if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
                New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
                Copy-Item -Path $src -Destination $dst -Recurse -Force
            }
        }
    }

    # Stamp the folder with the release tag so later runs can detect updates.
    Set-Content -Path (Join-Path $publishFull $versionFile) -Value $release.tag_name -Encoding UTF8 -NoNewline

    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $bakDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 1. Load or create the configuration -----------------------------------------
if ((Test-Path $ConfigFile) -and -not $Reconfigure) {
    Write-Host "Using existing configuration: $ConfigFile"
    $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
}
else {
    Write-Host ""
    Write-Host "=== uTPro Sandbox configuration (press Enter to accept the default) ==="
    Write-Host ""

    $connectionString = Ask "Database connection string (blank = local SQLite)" ""
    $connectionProvider = ""
    if ($connectionString) {
        $connectionProvider = Ask "  Database provider" "Microsoft.Data.SqlClient"
    }

    $useCustomDomains = AskYesNo "Use custom local domains instead of localhost?"
    $websiteUrl = "utpro.local"
    $backofficeUrl = "bo.utpro.local"
    if ($useCustomDomains) {
        $websiteUrl = Ask "  Website URL" "utpro.local"
        $backofficeUrl = Ask "  Backoffice URL" "bo.utpro.local"
    }

    $smtp = [ordered]@{ host = ""; port = 587; from = ""; username = ""; password = "" }
    if (AskYesNo "Configure SMTP (email)?") {
        $smtp.host = Ask "  SMTP host" ""
        $smtp.port = [int](Ask "  SMTP port" "587")
        $smtp.from = Ask "  From address" ""
        $smtp.username = Ask "  Username" ""
        $smtp.password = Ask "  Password" ""
    }

    $account = [ordered]@{ name = ""; email = ""; password = "" }
    if (AskYesNo "Create the backoffice admin automatically (skip the install wizard)?") {
        $account.name = Ask "  Admin name" "Administrator"
        $account.email = Ask "  Admin email" ""
        $account.password = Ask "  Admin password (min 10 chars)" ""
    }

    $cfg = [ordered]@{
        connectionString   = $connectionString
        connectionProvider = $connectionProvider
        useCustomDomains   = $useCustomDomains
        websiteUrl         = $websiteUrl
        backofficeUrl      = $backofficeUrl
        smtp               = $smtp
        backofficeAccount  = $account
    }
    ($cfg | ConvertTo-Json -Depth 8) | Set-Content $ConfigFile -Encoding UTF8
    Write-Host ""
    Write-Host "Saved configuration to $ConfigFile (delete it or run with 'reconfigure' to change)."
}

# --- 2. Download / update the release publish asset (with version check) ---------
$publishFull = [System.IO.Path]::GetFullPath($PublishDir)
$installed   = if (Test-Path (Join-Path $publishFull $AppDll)) { $true } else { $false }
$installedTag = Get-InstalledVersion $publishFull $VersionFile

# Ask GitHub for the latest release tag (used both for a fresh install and the update check).
$release = $null
try {
    Write-Host "Querying latest uTPro release..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
    Write-Host "Latest release: $($release.tag_name)"
}
catch {
    if (-not $installed) { throw "Could not query the latest uTPro release: $($_.Exception.Message)" }
    Write-Host "WARNING: could not check for updates ($($_.Exception.Message)). Using the existing publish output."
}

if (-not $installed) {
    # Fresh install: download the latest release and stamp the version.
    Install-Release $release $publishFull $AppDll $VersionFile $DataPaths $headers
    Write-Host "Publish output ready in $publishFull (version $($release.tag_name))."
}
elseif ($null -eq $release) {
    # Offline / API failure but we already have a build: just run it.
    Write-Host "Publish output already present (version $(if ($installedTag) { $installedTag } else { 'unknown' }))."
}
elseif (-not $installedTag) {
    # Existing build from before version tracking: assume it is current and stamp it,
    # so future runs can detect updates. Do not force an update this run.
    Set-Content -Path (Join-Path $publishFull $VersionFile) -Value $release.tag_name -Encoding UTF8 -NoNewline
    Write-Host "Publish output already present (marked as version $($release.tag_name))."
}
elseif ($installedTag -eq $release.tag_name) {
    # Up to date: nothing to download.
    Write-Host "Publish output already present and up to date (version $installedTag)."
}
else {
    # An update is available: let the user choose what to do.
    Write-Host ""
    Write-Host "================================================================"
    Write-Host "  A new uTPro release is available!"
    Write-Host "    Installed: $installedTag"
    Write-Host "    Latest   : $($release.tag_name)"
    Write-Host "================================================================"
    Write-Host "  [1] Update and RESET     - uninstall the old version and DELETE ALL DATA"
    Write-Host "                              (database + media), then install $($release.tag_name) clean."
    Write-Host "  [2] Keep current version - do NOT update; keep your data and run $installedTag as-is."
    Write-Host "  [3] Update and KEEP data - install $($release.tag_name) but keep your existing"
    Write-Host "                              data (database + media)."
    Write-Host ""
    $choice = Ask "Choose [1/2/3]" "2"

    switch ($choice) {
        '1' {
            Write-Host ""
            Write-Host "WARNING: this permanently removes the current database and uploaded media." -ForegroundColor Yellow
            if (AskYesNo "Are you sure you want to reset and update to $($release.tag_name)?") {
                Write-Host "Uninstalling the old version and installing $($release.tag_name) (clean)..."
                Install-Release $release $publishFull $AppDll $VersionFile $DataPaths $headers
                Write-Host "Updated to $($release.tag_name) (data reset)."
            }
            else {
                Write-Host "Update cancelled. Keeping the current version ($installedTag)."
            }
        }
        '3' {
            Write-Host "Updating to $($release.tag_name) while keeping your data..."
            Install-Release $release $publishFull $AppDll $VersionFile $DataPaths $headers -PreserveData
            Write-Host "Updated to $($release.tag_name) (data kept)."
        }
        default {
            Write-Host "Keeping the current version ($installedTag). Your data is unchanged."
        }
    }
}

# --- 3. Build appsettings.Production.json from the configuration ------------------
$dataDir = Join-Path $publishFull 'umbraco\Data'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$dbFile = Join-Path $dataDir 'Umbraco.sqlite.db'

# Connection string: use the custom one if provided, otherwise local SQLite.
if ($cfg.connectionString) {
    $connStr  = $cfg.connectionString
    $provider = if ($cfg.connectionProvider) { $cfg.connectionProvider } else { 'Microsoft.Data.SqlClient' }
    $usingSqlite = $false
}
else {
    $dbPath   = $dbFile.Replace('\', '/')
    $connStr  = "Data Source=$dbPath;Cache=Shared;Foreign Keys=True;Pooling=True"
    $provider = 'Microsoft.Data.Sqlite'
    $usingSqlite = $true
}

$settings = [ordered]@{
    ConnectionStrings = [ordered]@{
        umbracoDbDSN              = $connStr
        umbracoDbDSN_ProviderName = $provider
    }
    uTPro   = [ordered]@{ Backoffice = [ordered]@{ Enabled = [bool]$cfg.useCustomDomains } }
    Umbraco = [ordered]@{ CMS = [ordered]@{ Runtime = [ordered]@{ Mode = 'Development' } } }
}

# Custom backoffice domain
if ($cfg.useCustomDomains) {
    $settings.uTPro.Backoffice.Url = $cfg.backofficeUrl
}

# SMTP (only when a host was provided)
if ($cfg.smtp -and $cfg.smtp.host) {
    $secure = if ($cfg.smtp.port -eq 465) { 'SslOnConnect' } else { 'Auto' }
    $settings.Umbraco.CMS.Global = [ordered]@{
        Smtp = [ordered]@{
            From                = $cfg.smtp.from
            Host                = $cfg.smtp.host
            Port                = [int]$cfg.smtp.port
            Username            = $cfg.smtp.username
            Password            = $cfg.smtp.password
            SecureSocketOptions = $secure
            DeliveryMethod      = 'Network'
        }
    }
}

# Unattended install (auto-create the admin, skip the wizard)
if ($cfg.backofficeAccount -and $cfg.backofficeAccount.email) {
    $settings.Umbraco.CMS.Unattended = [ordered]@{
        InstallUnattended       = $true
        UnattendedUserName      = $cfg.backofficeAccount.name
        UnattendedUserEmail     = $cfg.backofficeAccount.email
        UnattendedUserPassword  = $cfg.backofficeAccount.password
    }
}

($settings | ConvertTo-Json -Depth 8) | Set-Content (Join-Path $publishFull 'appsettings.Production.json') -Encoding UTF8

# --- 4. Optional: hosts file entries for the custom domains ----------------------
if ($cfg.useCustomDomains) {
    $hostsFile = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $domains = @($cfg.websiteUrl, $cfg.backofficeUrl) | Where-Object { $_ }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $existing = if (Test-Path $hostsFile) { Get-Content $hostsFile } else { @() }
    $missing = $domains | Where-Object { -not ($existing -match "\s$([regex]::Escape($_))\s*$") }
    if ($missing) {
        if ($isAdmin) {
            Add-Content -Path $hostsFile -Value ($missing | ForEach-Object { "127.0.0.1`t$_" })
            Write-Host "Added to hosts file: $($missing -join ', ')"
        }
        else {
            Write-Host "NOTE: run as Administrator to auto-update the hosts file, or add these lines manually to"
            Write-Host "      $hostsFile :"
            $missing | ForEach-Object { Write-Host "        127.0.0.1`t$_" }
        }
    }
}

# --- 5. Empty SQLite file so the first boot reaches install/installer ------------
if ($usingSqlite -and -not (Test-Path $dbFile)) {
    New-Item -ItemType File -Force -Path $dbFile | Out-Null
}

Write-Host "Configuration applied."
if ($cfg.useCustomDomains) {
    Write-Host "  Website  : http://$($cfg.websiteUrl):5000"
    Write-Host "  Backoffice: http://$($cfg.backofficeUrl):5000/umbraco"
}
