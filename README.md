# uTPro Sandbox (SQLite)

A ready-to-run demo of [uTPro](https://github.com/T4VN/uTPro) that runs on **SQLite**
instead of SQL Server, so you can try the full uTPro site on **Windows, macOS or Linux**
without installing a database server.

Instead of building from source, the launcher downloads the **pre-built publish asset**
from the latest stable uTPro GitHub release (`publish_output*.zip`), points it at a local
SQLite database, and runs it. No .NET SDK and no build step are required - only the
**.NET 10 runtime** (which the launcher installs locally if it is missing).

> **Requires .NET 10.** uTPro is moving to Umbraco 17 on .NET 10, so the launcher
> requires a .NET 10 runtime. While the current release still targets .NET 9, it runs on
> the .NET 10 runtime automatically via `DOTNET_ROLL_FORWARD=Major`.

---

## Prerequisites

The launcher takes care of the .NET runtime for you; you only need the basics:

| Platform | Needs | Notes |
|----------|-------|-------|
| All | **Git** | To clone the repo. |
| All | **.NET 10 runtime** | Auto-installed into `.dotnet/` if missing (no admin rights needed). |
| Windows | PowerShell + `curl` | Both ship with Windows 10/11. |
| macOS / Linux | `curl` + `unzip` (or `tar`) | Usually pre-installed; install via your package manager if not. |

Internet access is required on the first run to download the uTPro release and, if needed,
the .NET runtime.

---

## Quick start (one click)

**Windows**
```cmd
git clone https://github.com/T4VN/uTPro.Sandbox.SQLite.git
cd uTPro.Sandbox.SQLite
run.cmd
```

**macOS / Linux**
```bash
git clone https://github.com/T4VN/uTPro.Sandbox.SQLite.git
cd uTPro.Sandbox.SQLite
chmod +x run.sh
./run.sh
```

Then open **http://localhost:5000/umbraco** and complete the first-time install wizard.
The database is an empty SQLite file, so you install from scratch; uTPro's uSync content
is imported on first boot.

The **second** time you run the script it detects the existing `publish/` output and just
starts the website again (no re-download), keeping any data you created.

---

## What the launcher does

| Step | Action |
|------|--------|
| 1 | Ensures the **.NET 10 runtime** (ASP.NET Core 10.0+) is available; installs one locally into `.dotnet/` if not. |
| 2 | Downloads the latest release `publish_output*.zip`, extracts it into `publish/`, writes an SQLite `appsettings.Production.json` overlay and creates an empty SQLite database file. |
| 3 | Runs `dotnet uTPro.Project.Web.dll` from `publish/` at http://localhost:5000. |

### The SQLite overlay
The launcher writes `publish/appsettings.Production.json` on top of the release's own
`appsettings.json`. ASP.NET Core merges it, so only these settings are changed:

```json
{
  "ConnectionStrings": {
    "umbracoDbDSN": "Data Source=<abs>/publish/umbraco/Data/Umbraco.sqlite.db;Cache=Shared;Foreign Keys=True;Pooling=True",
    "umbracoDbDSN_ProviderName": "Microsoft.Data.Sqlite"
  },
  "uTPro":  { "Backoffice": { "Enabled": false } },
  "Umbraco": { "CMS": { "Runtime": { "Mode": "Development" } } }
}
```

- **ConnectionStrings** - switches uTPro from SQL Server to a local SQLite file (absolute
  path so it resolves no matter where the app is started).
- **uTPro:Backoffice:Enabled = false** - the release ships with a custom backoffice domain
  (`bo.utpro.local`); disabling it keeps the backoffice on `localhost`.
- **Umbraco:CMS:Runtime:Mode = Development** - the release runs in `Production` mode, which
  refuses to boot without a configured application URL. `Development` relaxes that for a
  local demo.

An empty SQLite file is created up front because Umbraco's start-up database probe opens
the file read-only and would otherwise report a boot failure instead of showing the installer.

---

## Files

| Path | Purpose |
|------|---------|
| `run.cmd` / `run.sh` | One-click launchers for Windows / macOS / Linux. |
| `tools/prepare-sqlite.ps1` | **Windows-only** helper (called by `run.cmd`): download + extract the release, write the SQLite overlay, create the empty database. `run.sh` re-implements the same logic inline in bash, so macOS/Linux do **not** need this file. |
| `publish/` | Downloaded release output (git-ignored, created at run time). |
| `.dotnet/` | Locally installed .NET runtime, if the launcher had to fetch one (git-ignored). |

---

## Updating to a newer uTPro release

The launcher always downloads the **latest** release. To refresh, delete the downloaded
output and run again:

```bash
rm -rf publish        # Windows: delete the "publish" folder
```

---

## Notes & limitations

- SQLite is intended for **evaluation / demo / development**, not production. It does not
  handle high write-concurrency well (you may hit `database is locked` under load).
- The first boot takes longer while Umbraco creates the schema and uSync imports content.
- To reset the demo completely, delete the `publish/` folder and run again.
- The launcher runs uTPro's own published host (`uTPro.Project.Web.dll`); the only change
  applied is the SQLite configuration overlay described above.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| **Port 5000 already in use** | Edit `APP_URL` at the top of `run.cmd` / `run.sh` to another port (e.g. `http://localhost:5080`). |
| **`run.sh: Permission denied`** | Run `chmod +x run.sh` first. |
| **Download is slow or interrupted** | Just re-run the launcher to retry. It only skips downloading once `publish/` contains a complete extract; an interrupted download is re-attempted from the start. |
| **"unzip: command not found" (Linux)** | Install it, e.g. `sudo apt-get install unzip` (Debian/Ubuntu) or `sudo dnf install unzip` (Fedora). |
| **Backoffice login won't load** | Make sure you open `http://localhost:5000/umbraco` (not a custom domain); the overlay already disables uTPro's `bo.utpro.local` domain. |
| **Reset the demo** | Delete the `publish/` folder and run the launcher again. |
