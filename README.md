# uTPro Sandbox (SQLite)

A ready-to-run demo of [uTPro](https://github.com/T4VN/uTPro) that runs on **SQLite**
instead of SQL Server, so you can try the full uTPro site on **Windows, macOS or Linux**
without installing a database server.

Instead of building from source, the launcher downloads the **pre-built publish asset**
from the latest stable uTPro GitHub release (`publish_output*.zip`), asks a few optional
configuration questions, points it at a database (SQLite by default), and runs it. No .NET
SDK and no build step are required - only the **.NET 10 runtime** (which the launcher
installs locally if it is missing).

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

On the **first run** the launcher asks a few questions (see [Configuration](#configuration)).
Press Enter on every question to accept the safe defaults (SQLite, `localhost`, no SMTP,
manual install wizard). Your answers are saved so later runs never ask again.

Then open **http://localhost:5000/umbraco**. If you did not set up an admin automatically,
complete the first-time install wizard; uTPro's uSync content is imported on first boot.

The **second** time you run the script it reuses your saved configuration and the existing
`publish/` output and just starts the website again (no questions, no re-download).

---

## What the launcher does

| Step | Action |
|------|--------|
| 1 | Ensures the **.NET 10 runtime** (ASP.NET Core 10.0+) is available; installs one locally into `.dotnet/` if not. |
| 2 | Loads your saved config (or asks the questions the first time), downloads the latest release `publish_output*.zip`, extracts it into `publish/`, generates `appsettings.Production.json` from your answers and creates an empty SQLite database file. |
| 3 | Runs `dotnet uTPro.Project.Web.dll` from `publish/` at http://localhost:5000. |

---

## Configuration

On the first run the launcher asks the questions below and saves the answers to
`sandbox.config` (macOS/Linux) or `sandbox.config.json` (Windows). **Leave any answer blank
to keep the default.** To change them later, run `run.cmd reconfigure` / `./run.sh reconfigure`
or just delete the config file.

| Question | Default | Effect |
|----------|---------|--------|
| Database connection string | *blank* -> local **SQLite** | Any value switches uTPro to that database (you are also asked for the provider, default `Microsoft.Data.SqlClient`). |
| Use custom local domains? | No -> **localhost** | If yes, you enter a website URL (`utpro.local`) and backoffice URL (`bo.utpro.local`); the launcher enables uTPro's backoffice domain and adds the names to your hosts file (needs admin/sudo, otherwise it prints the lines to add). |
| Configure SMTP? | No -> **empty** | If yes, you enter host / port / from / username / password; written to `Umbraco:CMS:Global:Smtp`. |
| Create the backoffice admin automatically? | No -> **install wizard** | If yes, you enter name / email / password; the launcher enables Umbraco **unattended install** so the admin and schema are created on first boot with no wizard. |

The launcher turns those answers into `publish/appsettings.Production.json`, which ASP.NET
Core merges over the release's own `appsettings.json`. A default (all-blank) run produces:

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

- **Backoffice:Enabled = false** keeps the backoffice on `localhost` (the release ships with
  a `bo.utpro.local` domain); it is enabled with your URL only if you opt into custom domains.
- **Runtime:Mode = Development** - the release runs in `Production` mode, which refuses to
  boot without a configured application URL; `Development` relaxes that for a local demo.

An empty SQLite file is created up front because Umbraco's start-up database probe opens the
file read-only and would otherwise report a boot failure instead of reaching install.

---

## Files

| Path | Purpose |
|------|---------|
| `run.cmd` / `run.sh` | One-click launchers for Windows / macOS / Linux. |
| `tools/prepare.ps1` | **Windows-only** helper (called by `run.cmd`): runs the config wizard, downloads + extracts the release, generates `appsettings.Production.json`, creates the empty database. `run.sh` re-implements the same logic inline in bash, so macOS/Linux do **not** need this file. |
| `sandbox.config` / `sandbox.config.json` | Your saved answers (git-ignored; may contain passwords). |
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
- To reset the demo completely, delete the `publish/` folder (and the config file to be
  asked the questions again) and run the launcher again.
- The launcher runs uTPro's own published host (`uTPro.Project.Web.dll`); the only changes
  applied are in the generated `appsettings.Production.json` described under
  [Configuration](#configuration).

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| **Port 5000 already in use** | Edit `APP_URL` at the top of `run.cmd` / `run.sh` to another port (e.g. `http://localhost:5080`). |
| **`run.sh: Permission denied`** | Run `chmod +x run.sh` first. |
| **Download is slow or interrupted** | Just re-run the launcher to retry. It only skips downloading once `publish/` contains a complete extract; an interrupted download is re-attempted from the start. |
| **"unzip: command not found" (Linux)** | Install it, e.g. `sudo apt-get install unzip` (Debian/Ubuntu) or `sudo dnf install unzip` (Fedora). |
| **Backoffice login won't load** | Make sure you open `http://localhost:5000/umbraco` (not a custom domain); the overlay already disables uTPro's `bo.utpro.local` domain. |
| **Change your answers** | Run `run.cmd reconfigure` / `./run.sh reconfigure`, or delete the `sandbox.config` / `sandbox.config.json` file. |
| **Reset the demo** | Delete the `publish/` folder and run the launcher again. |
