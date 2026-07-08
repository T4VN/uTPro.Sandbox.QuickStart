#!/usr/bin/env bash
# ====================================================================
#  uTPro Sandbox (SQLite) - one-click launcher for macOS / Linux
#  - asks a few config questions the first time (blank = safe defaults),
#    saves them to sandbox.config so later runs never ask again
#  - downloads the latest uTPro release PUBLISH asset (pre-built, no build)
#  - generates appsettings.Production.json (SQLite / custom / SMTP / admin)
#  - installs the .NET 10 runtime locally if it is missing, then runs
#
#  Usage:  ./run.sh              (normal run)
#          ./run.sh reconfigure  (ask the questions again)
# ====================================================================
set -euo pipefail
# Scripts live in linux-macos/ ; all generated files stay at the repo ROOT (parent).
cd "$(dirname "$0")/.."

# uTPro targets .NET 10 (Umbraco 17+). A .NET 9 release rolls forward automatically.
DOTNET_CHANNEL="10.0"
REPO="T4VN/uTPro"
PUBLISH_DIR="publish"
APP_DLL="uTPro.Project.Web.dll"
APP_URL="http://localhost:5000"
DOTNET_LOCAL="$(pwd)/.dotnet"
CONFIG_FILE="sandbox.config"
VERSION_FILE=".utpro-release"
# Data folders (relative to publish/) preserved by an "update but keep data" refresh.
DATA_PATHS=("umbraco/Data" "wwwroot/media" "media")

RECONFIGURE="0"
[ "${1:-}" = "reconfigure" ] && RECONFIGURE="1"

echo
echo "==== uTPro Sandbox (SQLite) launcher ===="
echo

# --- 1/3  Ensure the .NET 10 runtime is available ---
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

# --- 2/3  Configure + download + write settings ---
echo "[2/3] Preparing the uTPro release..."

ask()    { local v; if [ -n "${2:-}" ]; then read -r -p "$1 [$2]: " v; else read -r -p "$1: " v; fi; echo "${v:-${2:-}}"; }
ask_yn() { local v; read -r -p "$1 (y/N): " v; case "$v" in y|Y|yes|YES) return 0;; *) return 1;; esac; }
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

if [ -f "${CONFIG_FILE}" ] && [ "${RECONFIGURE}" = "0" ]; then
  echo "      Using existing configuration: ${CONFIG_FILE}"
  # shellcheck disable=SC1090
  . "./${CONFIG_FILE}"
else
  echo
  echo "=== uTPro Sandbox configuration (press Enter to accept the default) ==="
  echo
  CONNECTION_STRING="$(ask 'Database connection string (blank = local SQLite)' '')"
  CONNECTION_PROVIDER=""
  [ -n "${CONNECTION_STRING}" ] && CONNECTION_PROVIDER="$(ask '  Database provider' 'Microsoft.Data.SqlClient')"

  if ask_yn "Use custom local domains instead of localhost?"; then
    USE_CUSTOM_DOMAINS="true"
    WEBSITE_URL="$(ask '  Website URL' 'utpro.local')"
    BACKOFFICE_URL="$(ask '  Backoffice URL' 'bo.utpro.local')"
  else
    USE_CUSTOM_DOMAINS="false"; WEBSITE_URL="utpro.local"; BACKOFFICE_URL="bo.utpro.local"
  fi

  SMTP_HOST=""; SMTP_PORT="587"; SMTP_FROM=""; SMTP_USERNAME=""; SMTP_PASSWORD=""
  if ask_yn "Configure SMTP (email)?"; then
    SMTP_HOST="$(ask '  SMTP host' '')"
    SMTP_PORT="$(ask '  SMTP port' '587')"
    SMTP_FROM="$(ask '  From address' '')"
    SMTP_USERNAME="$(ask '  Username' '')"
    SMTP_PASSWORD="$(ask '  Password' '')"
  fi

  ADMIN_NAME=""; ADMIN_EMAIL=""; ADMIN_PASSWORD=""
  if ask_yn "Create the backoffice admin automatically (skip the install wizard)?"; then
    ADMIN_NAME="$(ask '  Admin name' 'Administrator')"
    ADMIN_EMAIL="$(ask '  Admin email' '')"
    ADMIN_PASSWORD="$(ask '  Admin password (min 10 chars)' '')"
  fi

  cat > "${CONFIG_FILE}" <<EOF
CONNECTION_STRING="${CONNECTION_STRING}"
CONNECTION_PROVIDER="${CONNECTION_PROVIDER}"
USE_CUSTOM_DOMAINS="${USE_CUSTOM_DOMAINS}"
WEBSITE_URL="${WEBSITE_URL}"
BACKOFFICE_URL="${BACKOFFICE_URL}"
SMTP_HOST="${SMTP_HOST}"
SMTP_PORT="${SMTP_PORT}"
SMTP_FROM="${SMTP_FROM}"
SMTP_USERNAME="${SMTP_USERNAME}"
SMTP_PASSWORD="${SMTP_PASSWORD}"
ADMIN_NAME="${ADMIN_NAME}"
ADMIN_EMAIL="${ADMIN_EMAIL}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
EOF
  echo "      Saved configuration to ${CONFIG_FILE} (delete it or run './run.sh reconfigure' to change)."
fi

# Download / update the release publish asset (with version check)

# Version tag currently installed (from the marker file), or empty if unknown / not installed.
get_installed_version() {
  [ -f "${PUBLISH_DIR}/${VERSION_FILE}" ] && tr -d '[:space:]' < "${PUBLISH_DIR}/${VERSION_FILE}" || true
}

# Download the ${ASSET_URL} publish asset and lay it down in publish/.
# Arg1: preserve data (1 = keep umbraco/Data + media, 0 = clean install).
install_release() {
  local preserve="$1"
  if ! command -v curl >/dev/null 2>&1; then echo "[ERROR] curl is required."; exit 1; fi
  [ -z "${ASSET_URL}" ] && { echo "[ERROR] Could not find publish_output asset."; exit 1; }
  echo "      Downloading $(basename "${ASSET_URL}") ..."
  local TMP_ZIP TMP_DIR BAK_DIR ROOT rel
  TMP_ZIP="$(mktemp -t utpro-publish.XXXXXX).zip"
  TMP_DIR="$(mktemp -d -t utpro-publish.XXXXXX)"
  BAK_DIR="$(mktemp -d -t utpro-data.XXXXXX)"
  curl -fsSL -H 'User-Agent: uTPro-Sandbox' "${ASSET_URL}" -o "${TMP_ZIP}"
  echo "      Extracting..."
  if command -v unzip >/dev/null 2>&1; then unzip -q "${TMP_ZIP}" -d "${TMP_DIR}"; else tar -xf "${TMP_ZIP}" -C "${TMP_DIR}"; fi
  ROOT="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n1)"

  # Back up the data folders before wiping the old publish output.
  if [ "${preserve}" = "1" ] && [ -d "${PUBLISH_DIR}" ]; then
    for rel in "${DATA_PATHS[@]}"; do
      if [ -e "${PUBLISH_DIR}/${rel}" ]; then
        mkdir -p "${BAK_DIR}/$(dirname "${rel}")"
        cp -R "${PUBLISH_DIR}/${rel}" "${BAK_DIR}/${rel}"
      fi
    done
  fi

  # Replace the publish folder with the fresh extract.
  rm -rf "${PUBLISH_DIR}"; mkdir -p "${PUBLISH_DIR}"; cp -R "${ROOT}/." "${PUBLISH_DIR}/"

  # Restore the preserved data on top of the new release.
  if [ "${preserve}" = "1" ]; then
    for rel in "${DATA_PATHS[@]}"; do
      if [ -e "${BAK_DIR}/${rel}" ]; then
        mkdir -p "${PUBLISH_DIR}/$(dirname "${rel}")"
        rm -rf "${PUBLISH_DIR}/${rel}"
        cp -R "${BAK_DIR}/${rel}" "${PUBLISH_DIR}/${rel}"
      fi
    done
  fi

  # Stamp the folder with the release tag so later runs can detect updates.
  printf '%s' "${LATEST_TAG}" > "${PUBLISH_DIR}/${VERSION_FILE}"
  rm -rf "${TMP_ZIP}" "${TMP_DIR}" "${BAK_DIR}"
}

INSTALLED_TAG="$(get_installed_version)"
LATEST_TAG=""; ASSET_URL=""
if command -v curl >/dev/null 2>&1; then
  API_JSON="$(curl -fsSL -H 'User-Agent: uTPro-Sandbox' "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)"
  LATEST_TAG="$(printf '%s' "${API_JSON}" | grep -o '"tag_name"[^,]*' | head -n1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
  ASSET_URL="$(printf '%s' "${API_JSON}" | grep -o '"browser_download_url"[^,]*publish_output[^"]*\.zip"' | sed -E 's/.*"(https[^"]+)"/\1/' | head -n1 || true)"
fi

if [ ! -f "${PUBLISH_DIR}/${APP_DLL}" ]; then
  # Fresh install: download the latest release and stamp the version.
  [ -z "${LATEST_TAG}" ] && { echo "[ERROR] Could not query the latest uTPro release."; exit 1; }
  echo "      Latest release: ${LATEST_TAG}"
  install_release 0
  echo "      Publish output ready (version ${LATEST_TAG})."
elif [ -z "${LATEST_TAG}" ]; then
  # Offline / API failure but we already have a build: just run it.
  echo "      WARNING: could not check for updates. Using the existing publish output (version ${INSTALLED_TAG:-unknown})."
elif [ -z "${INSTALLED_TAG}" ]; then
  # Existing build from before version tracking: stamp it as current, do not force an update.
  printf '%s' "${LATEST_TAG}" > "${PUBLISH_DIR}/${VERSION_FILE}"
  echo "      Publish output already present (marked as version ${LATEST_TAG})."
elif [ "${INSTALLED_TAG}" = "${LATEST_TAG}" ]; then
  echo "      Publish output already present and up to date (version ${INSTALLED_TAG})."
else
  # An update is available: let the user choose what to do.
  echo
  echo "================================================================"
  echo "  A new uTPro release is available!"
  echo "    Installed: ${INSTALLED_TAG}"
  echo "    Latest   : ${LATEST_TAG}"
  echo "================================================================"
  echo "  [1] Update and RESET     - uninstall the old version and DELETE ALL DATA"
  echo "                             (database + media), then install ${LATEST_TAG} clean."
  echo "  [2] Keep current version - do NOT update; keep your data and run ${INSTALLED_TAG} as-is."
  echo "  [3] Update and KEEP data - install ${LATEST_TAG} but keep your existing"
  echo "                             data (database + media)."
  echo
  CHOICE="$(ask 'Choose [1/2/3]' 'default: 2')"
  case "${CHOICE}" in
    1)
      echo
      echo "WARNING: this permanently removes the current database and uploaded media."
      if ask_yn "Are you sure you want to reset and update to ${LATEST_TAG}?"; then
        echo "      Uninstalling the old version and installing ${LATEST_TAG} (clean)..."
        install_release 0
        echo "      Updated to ${LATEST_TAG} (data reset)."
      else
        echo "      Update cancelled. Keeping the current version (${INSTALLED_TAG})."
      fi
      ;;
    3)
      echo "      Updating to ${LATEST_TAG} while keeping your data..."
      install_release 1
      echo "      Updated to ${LATEST_TAG} (data kept)."
      ;;
    *)
      echo "      Keeping the current version (${INSTALLED_TAG}). Your data is unchanged."
      ;;
  esac
fi

# Build appsettings.Production.json from the configuration
DATA_DIR="$(cd "${PUBLISH_DIR}" && pwd)/umbraco/Data"
mkdir -p "${DATA_DIR}"
DB_FILE="${DATA_DIR}/Umbraco.sqlite.db"
USING_SQLITE="0"
if [ -n "${CONNECTION_STRING}" ]; then
  CONN="${CONNECTION_STRING}"; PROVIDER="${CONNECTION_PROVIDER:-Microsoft.Data.SqlClient}"
else
  CONN="Data Source=${DB_FILE};Cache=Shared;Foreign Keys=True;Pooling=True"; PROVIDER="Microsoft.Data.Sqlite"; USING_SQLITE="1"
fi

BACKOFFICE_JSON="\"Backoffice\": { \"Enabled\": ${USE_CUSTOM_DOMAINS}"
[ "${USE_CUSTOM_DOMAINS}" = "true" ] && BACKOFFICE_JSON="${BACKOFFICE_JSON}, \"Url\": \"$(json_escape "${BACKOFFICE_URL}")\""
BACKOFFICE_JSON="${BACKOFFICE_JSON} }"

CMS_PARTS="\"Runtime\": { \"Mode\": \"Development\" }"
if [ -n "${SMTP_HOST}" ]; then
  SECURE="Auto"; [ "${SMTP_PORT}" = "465" ] && SECURE="SslOnConnect"
  CMS_PARTS="${CMS_PARTS}, \"Global\": { \"Smtp\": { \"From\": \"$(json_escape "${SMTP_FROM}")\", \"Host\": \"$(json_escape "${SMTP_HOST}")\", \"Port\": ${SMTP_PORT}, \"Username\": \"$(json_escape "${SMTP_USERNAME}")\", \"Password\": \"$(json_escape "${SMTP_PASSWORD}")\", \"SecureSocketOptions\": \"${SECURE}\", \"DeliveryMethod\": \"Network\" } }"
fi
if [ -n "${ADMIN_EMAIL}" ]; then
  CMS_PARTS="${CMS_PARTS}, \"Unattended\": { \"InstallUnattended\": true, \"UnattendedUserName\": \"$(json_escape "${ADMIN_NAME}")\", \"UnattendedUserEmail\": \"$(json_escape "${ADMIN_EMAIL}")\", \"UnattendedUserPassword\": \"$(json_escape "${ADMIN_PASSWORD}")\" }"
fi

cat > "${PUBLISH_DIR}/appsettings.Production.json" <<EOF
{
  "ConnectionStrings": {
    "umbracoDbDSN": "$(json_escape "${CONN}")",
    "umbracoDbDSN_ProviderName": "${PROVIDER}"
  },
  "uTPro": { ${BACKOFFICE_JSON} },
  "Umbraco": { "CMS": { ${CMS_PARTS} } }
}
EOF

# Optional: hosts file entries for the custom domains
if [ "${USE_CUSTOM_DOMAINS}" = "true" ]; then
  for d in "${WEBSITE_URL}" "${BACKOFFICE_URL}"; do
    [ -z "$d" ] && continue
    if ! grep -qE "[[:space:]]${d}([[:space:]]|\$)" /etc/hosts 2>/dev/null; then
      if [ -w /etc/hosts ]; then printf '127.0.0.1\t%s\n' "$d" >> /etc/hosts; echo "      Added to /etc/hosts: $d";
      else echo "      NOTE: add '127.0.0.1 $d' to /etc/hosts (needs sudo)."; fi
    fi
  done
fi

# Empty SQLite file so the first boot reaches install / the installer
if [ "${USING_SQLITE}" = "1" ] && [ ! -f "${DB_FILE}" ]; then : > "${DB_FILE}"; fi

# --- 3/3  Run the website ---
echo "[3/3] Starting the website at ${APP_URL}"
echo "      Open ${APP_URL}/umbraco to finish the first-time install (SQLite)."
if [ "${USE_CUSTOM_DOMAINS}" = "true" ]; then
  echo "      Custom domains: http://${WEBSITE_URL}:5000  |  http://${BACKOFFICE_URL}:5000/umbraco"
fi
echo "      Press Ctrl+C to stop."
echo
export ASPNETCORE_URLS="${APP_URL}"
export ASPNETCORE_ENVIRONMENT="Production"
export DOTNET_ROLL_FORWARD="Major"
cd "${PUBLISH_DIR}"
exec "${DOTNET_CMD}" "${APP_DLL}"
