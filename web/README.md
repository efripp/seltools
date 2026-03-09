# SelTools Fleet Browser (Static)

## Run locally

Use the built-in PowerShell static host (no Python required):

```powershell
cd web
.\start-web.ps1
```

Then open `http://localhost:8080` in Chrome or Edge.

Optional custom port:

```powershell
.\start-web.ps1 -Port 9090
```

Stop the host with `Ctrl+C`.

## Notes

- No backend server logic and no external dependencies are used by the app itself.
- The app reads/writes directly to files in the selected data folder via the File System Access API.
- When prompted, browse to `/seltools/data` (the folder that contains `desiredstate.csv` and `devices/`).
- The selected folder handle is persisted in IndexedDB for reconnect convenience.
- Inventory Browser view includes:
  - inventory snapshot history from `data/devices/<serial>.json`
  - SER event stream browsing from `data/events/<serial>/ser.jsonl` when available
