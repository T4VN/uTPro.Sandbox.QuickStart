#!/usr/bin/env bash
# ====================================================================
#  uTPro Sandbox (SQLite) - uninstall / clean-up for macOS / Linux
#  Stops the running site and deletes everything the launcher generated,
#  returning the folder to its clean checked-in (git) state.
#
#  Usage:  ./uninstall.sh        (asks for confirmation)
#          ./uninstall.sh -y     (no prompt)
# ====================================================================
set -euo pipefail
cd "$(dirname "$0")"

FORCE="0"
case "${1:-}" in -y|--yes|force) FORCE="1";; esac

echo
echo "==== uTPro Sandbox (SQLite) uninstall ===="
echo
echo "This will stop the running site and delete generated files:"
echo "  - publish/                       (release output + SQLite database)"
echo "  - .dotnet/                        (locally installed .NET runtime)"
echo "  - sandbox.config / sandbox.config.json"
echo "  - downloaded archives / installers"
echo "The repo returns to its clean checked-in state."
echo

if [ "${FORCE}" = "0" ]; then
  read -r -p "Continue? (y/N): " CONFIRM
  case "${CONFIRM}" in y|Y|yes|YES) ;; *) echo "Cancelled."; exit 0;; esac
fi

echo
echo "Stopping the uTPro sandbox process (if running)..."
if command -v pkill >/dev/null 2>&1; then
  pkill -f 'uTPro.Project.Web' 2>/dev/null && echo "  stopped." || echo "  nothing running."
else
  # Fallback without pkill
  PIDS="$(ps -ax -o pid=,command= 2>/dev/null | grep 'uTPro.Project.Web' | grep -v grep | awk '{print $1}')"
  if [ -n "${PIDS}" ]; then echo "${PIDS}" | xargs kill -9 2>/dev/null || true; echo "  stopped."; else echo "  nothing running."; fi
fi

echo "Removing generated files..."
rm -rf publish .dotnet
rm -f sandbox.config sandbox.config.json dotnet-install.ps1 dotnet-install.sh
rm -f publish_output*.zip

echo
echo "Done. The sandbox is back to a clean state - run ./run.sh to set it up again."
