<#
    Prepares the uTPro SQLite sandbox on Windows:
      1. Downloads the latest STABLE uTPro release publish asset (publish_output*.zip)
         and extracts it into the publish folder (only if not already present).
      2. Writes an appsettings.Production.json overlay that points the connection
         string at a local SQLite database and relaxes settings for a local demo.
      3. Creates an empty SQLite database file so Umbraco boots into the installer
         instead of failing (its start-up probe opens the file read-only).
#>
param(
    [string]$Repo = 'T4VN/uTPro',
    [string]$PublishDir = 'publish',
    [string]$AppDll = 'uTPro.Project.Web.dll'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # keeps downloads fast & the console clean
$headers = @{ 'User-Agent' = 'uTPro-Sandbox' }

$publishFull = [System.IO.Path]::GetFullPath($PublishDir)

# 1. Download + extract the release publish asset (once) --------------------------
if (-not (Test-Path (Join-Path $publishFull $AppDll))) {
    Write-Host "Querying latest uTPro release..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
    Write-Host "Latest release: $($release.tag_name)"

    $asset = $release.assets | Where-Object { $_.name -like 'publish_output*.zip' } | Select-Object -First 1
    if ($null -eq $asset) { throw "No 'publish_output*.zip' asset found on release $($release.tag_name)." }

    $guid   = [guid]::NewGuid().ToString('N')
    $tmpZip = Join-Path $env:TEMP "utpro-publish-$guid.zip"
    $tmpDir = Join-Path $env:TEMP "utpro-publish-$guid"

    Write-Host "Downloading $($asset.name) ($([math]::Round($asset.size/1MB)) MB)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip -Headers $headers -TimeoutSec 1800

    Write-Host "Extracting..."
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

    # The archive contains a single top-level 'publish_output' folder.
    $root = Get-ChildItem -Path $tmpDir -Directory | Select-Object -First 1
    if ($null -eq $root) { throw "Unexpected archive layout." }

    New-Item -ItemType Directory -Force -Path $publishFull | Out-Null
    Copy-Item -Path (Join-Path $root.FullName '*') -Destination $publishFull -Recurse -Force

    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Publish output ready in $publishFull"
} else {
    Write-Host "Publish output already present."
}

# 2. SQLite overlay ---------------------------------------------------------------
$dataDir = Join-Path $publishFull 'umbraco\Data'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$dbPath = (Join-Path $dataDir 'Umbraco.sqlite.db').Replace('\', '/')

$overlay = @"
{
  "ConnectionStrings": {
    "umbracoDbDSN": "Data Source=$dbPath;Cache=Shared;Foreign Keys=True;Pooling=True",
    "umbracoDbDSN_ProviderName": "Microsoft.Data.Sqlite"
  },
  "uTPro": {
    "Backoffice": { "Enabled": false }
  },
  "Umbraco": {
    "CMS": {
      "Runtime": { "Mode": "Development" }
    }
  }
}
"@
Set-Content -Path (Join-Path $publishFull 'appsettings.Production.json') -Value $overlay -Encoding UTF8

# 3. Empty SQLite file so the first boot reaches the installer --------------------
$dbFile = Join-Path $dataDir 'Umbraco.sqlite.db'
if (-not (Test-Path $dbFile)) { New-Item -ItemType File -Force -Path $dbFile | Out-Null }

Write-Host "SQLite sandbox configured."
