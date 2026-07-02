#!/usr/bin/env bash
# ====================================================================
#  uTPro Sandbox (SQLite) - one-click launcher for macOS / Linux
#  - downloads the latest uTPro release PUBLISH asset (pre-built, no build)
#  - points it at a local SQLite database (via appsettings.Production.json)
#  - installs the .NET runtime locally if it is missing
#  - runs the website; re-runs just start it again
# ====================================================================
set -euo pipefail
cd "$(dirname "$0")"

# uTPro targets .NET 10 (Umbraco 17+). If the current release still targets
# .NET 9 it rolls forward onto the .NET 10 runtime automatically.
DOTNET_CHANNEL="10.0"
REPO="T4VN/uTPro"
PUBLISH_DIR="publish"
APP_DLL="uTPro.Project.Web.dll"
APP_URL="http://localhost:5000"
DOTNET_LOCAL="$(pwd)/.dotnet"

echo
echo "==== uTPro Sandbox (SQLite) launcher ===="
echo

# --- 1/3  Ensure a .NET runtime is available ---
DOTNET_CMD="dotnet"
if command -v dotnet >/dev/null 2>&1 && dotnet --list-runtimes 2>/dev/null | grep -qE "^Microsoft.AspNetCore.App 1[0-9]\."; then
  echo "[1/3] .NET 10 runtime (ASP.NET Core 10.0+) was found."
else
  if [ ! -x "${DOTNET_LOCAL}/dotnet" ]; then
    echo "[1/3] Installing .NET runtime ${DOTNET_CHANNEL} locally into .dotnet/ (first time only)..."
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    bash /tmp/dotnet-install.sh --channel "${DOTNET_CHANNEL}" --runtime aspnetcore --install-dir "${DOTNET_LOCAL}"
  else
    echo "[1/3] Using local .NET runtime in .dotnet/"
  fi
  DOTNET_CMD="${DOTNET_LOCAL}/dotnet"
  export DOTNET_ROOT="${DOTNET_LOCAL}"
  export PATH="${DOTNET_LOCAL}:${PATH}"
fi

# --- 2/3  Download the release + configure SQLite ---
echo "[2/3] Preparing the uTPro release (SQLite)..."

if [ ! -f "${PUBLISH_DIR}/${APP_DLL}" ]; then
  if ! command -v curl >/dev/null 2>&1; then echo "[ERROR] curl is required."; exit 1; fi

  echo "      Querying latest uTPro release..."
  ASSET_URL=$(curl -fsSL -H 'User-Agent: uTPro-Sandbox' \
      "https://api.github.com/repos/${REPO}/releases/latest" \
      | grep -o '"browser_download_url"[^,]*publish_output[^"]*\.zip"' \
      | sed -E 's/.*"(https[^"]+)"/\1/' | head -n1)
  if [ -z "${ASSET_URL}" ]; then echo "[ERROR] Could not find publish_output asset."; exit 1; fi
  echo "      Downloading $(basename "${ASSET_URL}") ..."

  TMP_ZIP="$(mktemp -t utpro-publish.XXXXXX).zip"
  TMP_DIR="$(mktemp -d -t utpro-publish.XXXXXX)"
  curl -fsSL -H 'User-Agent: uTPro-Sandbox' "${ASSET_URL}" -o "${TMP_ZIP}"

  echo "      Extracting..."
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "${TMP_ZIP}" -d "${TMP_DIR}"
  else
    tar -xf "${TMP_ZIP}" -C "${TMP_DIR}"   # bsdtar (macOS) can read zip
  fi

  # The archive contains a single top-level 'publish_output' folder.
  ROOT="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  mkdir -p "${PUBLISH_DIR}"
  cp -R "${ROOT}/." "${PUBLISH_DIR}/"
  rm -rf "${TMP_ZIP}" "${TMP_DIR}"
  echo "      Publish output ready."
else
  echo "      Publish output already present."
fi

# SQLite overlay (absolute path so it works regardless of the working directory)
DATA_DIR="$(cd "${PUBLISH_DIR}" && pwd)/umbraco/Data"
mkdir -p "${DATA_DIR}"
DB_PATH="${DATA_DIR}/Umbraco.sqlite.db"

cat > "${PUBLISH_DIR}/appsettings.Production.json" <<JSON
{
  "ConnectionStrings": {
    "umbracoDbDSN": "Data Source=${DB_PATH};Cache=Shared;Foreign Keys=True;Pooling=True",
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
JSON

# Empty SQLite file so the first boot reaches the installer.
[ -f "${DB_PATH}" ] || : > "${DB_PATH}"

# --- 3/3  Run the website ---
echo "[3/3] Starting the website at ${APP_URL}"
echo "      Open ${APP_URL}/umbraco to finish the first-time install (SQLite)."
echo "      Press Ctrl+C to stop."
echo
export ASPNETCORE_URLS="${APP_URL}"
export ASPNETCORE_ENVIRONMENT="Production"
export DOTNET_ROLL_FORWARD="Major"
cd "${PUBLISH_DIR}"
exec "${DOTNET_CMD}" "${APP_DLL}"
