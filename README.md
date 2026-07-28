# GhostServer

A local Zig mock server for **REST** and **WebSocket**. It reads JSON configs and returns prepared responses with `!{ACTION}` preprocessing.

Requires **Zig 0.16+**.

## Build and run

```bash
zig build
zig build run
```

`zig build run` starts both services by default using `config-rest.json` + `config-ws.json`.

Explicitly:

```bash
.\zig-out\bin\GhostServer.exe --rest config-rest.json --ws config-ws.json
zig build run -- --rest config-rest.json --ws config-ws.json
```

Single mode only:

```bash
.\zig-out\bin\GhostServer.exe --rest config-rest.json
.\zig-out\bin\GhostServer.exe --ws config-ws.json
```

With no arguments, the exe looks for `config-rest.json` / `config-ws.json` next to itself, then in the current working directory.

If you see `AddressInUse` / exit code 255, another GhostServer is already running on 8080/8081. Stop it and start again.

```bash
zig build test
```

## Host (bind)

`host` is **optional** (default `127.0.0.1`). You usually do not need it in the config.

| Value | Meaning |
|-------|---------|
| `127.0.0.1` (default) | local only — browser/apps on this PC |
| `0.0.0.0` | all interfaces — phone/other PC can use your LAN IP (e.g. `http://192.168.0.50:8080`) |

Do not put a random public IP here. Bind address ≠ “my Wi‑Fi IP”. For LAN access set `"host": "0.0.0.0"`, then connect to the machine’s real LAN address.
## Configs

### REST — `config-rest.json`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mode` | string | `rest` | must be `rest` |
| `host` | string | `127.0.0.1` | optional bind address (`0.0.0.0` for LAN) |
| `port` | number | `8080` | port |
| `cors` | bool | `true` | CORS + auto OPTIONS |
| `routes` | array | `[]` | REST endpoints |

Route fields: `method`, `path`, `status`, `delay_ms`, `headers`, `body`.

### WebSocket — `config-ws.json`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mode` | string | — | `ws` |
| `host` | string | `127.0.0.1` | optional bind address (`0.0.0.0` for LAN) |
| `port` | number | `8081` | port |
| `path` | string | `/ws` | upgrade path |
| `interval_ms` | number | `1000` | message spam interval |
| `message` | any | — | message template (with actions) |

WS example:

```json
{
  "mode": "ws",
  "port": 8081,
  "path": "/ws",
  "interval_ms": 1000,
  "message": {
    "ts": "!{TIMESTAMP_MS}",
    "iso": "!{TIMESTAMP_ISO}",
    "payload": "!{RANDOM_INT_IN_RANGE} 1 100",
    "label": "!{RANDOM_STRING} tick pulse beat"
  }
}
```

To allow LAN clients, add `"host": "0.0.0.0"`.
## Actions (`!{...}`)

A string value that starts with `!{ACTION_NAME}` is evaluated on **every** REST request / WS message.

| Action | Arguments | Result |
|--------|-----------|--------|
| `RANDOM_INT_IN_RANGE` | `min max` | random integer (inclusive) |
| `RANDOM_INT` | `n1 n2 ...` | one of the listed integers |
| `RANDOM_INT_MATRIX` | `outer inner min max` | 2D int array (e.g. slot reels) |
| `RANDOM_FLOAT_IN_RANGE` | `min max` | random float in `[min, max)` |
| `RANDOM_FLOAT` | `f1 f2 ...` | one of the listed floats |
| `RANDOM_FLOAT_MATRIX` | `outer inner min max` | 2D float array |
| `RANDOM_BOOL` | — | `true` / `false` |
| `RANDOM_STRING` | `Word1 Word2 ...` | one random token |
| `NULLABLE_RANDOM_INT` | `n1 n2 ...` | one listed int, or `null` |
| `NULLABLE_RANDOM_FLOAT` | `f1 f2 ...` | one listed float, or `null` |
| `NULLABLE_RANDOM_BOOL` | — | `true` / `false` / `null` |
| `NULLABLE_RANDOM_STRING` | `Word1 Word2 ...` | one listed token, or `null` |
| `SEQUENCE_INT` | `n1 n2 ...` | round-robin through listed integers |
| `SEQUENCE_FLOAT` | `f1 f2 ...` | round-robin through listed floats |
| `SEQUENCE_BOOL` | `b1 b2 ...` | round-robin through listed bools (`true`/`false`) |
| `SEQUENCE_STRING` | `Word1 Word2 ...` | round-robin through listed tokens |
| `LOREM` | `n` | `n` words of lorem ipsum text |
| `BASE64` | `png` \| `jpg` | fake image bytes as base64 (`jpeg` alias for `jpg`) |
| `NULLABLE_BASE64` | `png` \| `jpg` | same as `BASE64`, or `null` |
| `TIMESTAMP_MS` | — | unix time in milliseconds |
| `TIMESTAMP_ISO` | — | `YYYY-MM-DDTHH:MM:SSZ` |
| `ID` | — | random 8-digit integer (`10000000`…`99999999`) |
| `UUID` | — | random UUID v4 string |

Identical `!{SEQUENCE_*}` markers share one counter for the lifetime of the process (e.g. `"!{SEQUENCE_INT} 1 2 3"` → `1`, then `2`, then `3`, then `1`, …).

Add new actions in `src/actions.zig` (`builtins`).

## Console testing

### REST

In PowerShell use `curl.exe`:

```powershell
curl.exe http://127.0.0.1:8080/api/health
curl.exe http://127.0.0.1:8080/api/roll
curl.exe http://127.0.0.1:8080/api/scenario
curl.exe http://127.0.0.1:8080/api/spinMachine
curl.exe -X POST http://127.0.0.1:8080/api/login
```

### WebSocket

PowerShell has no convenient built-in client:

```powershell
# websocat (if installed):
websocat ws://127.0.0.1:8081/ws

# WebSocket (Node 22+)
node -e "const ws=new WebSocket('ws://127.0.0.1:8081/ws'); ws.onmessage=e=>console.log(e.data)"

# or via npx:
npx --yes wscat -c ws://127.0.0.1:8081/ws
```

Every `interval_ms` the server sends JSON with a timestamp and payload.

## From a web project

```js
// REST
const res = await fetch("http://127.0.0.1:8080/api/users");
const data = await res.json();

// WebSocket
const ws = new WebSocket("ws://127.0.0.1:8081/ws");
ws.onmessage = (e) => console.log(JSON.parse(e.data));
```

## Examples UI

Vite + React playground with live REST / WebSocket examples (code + Run result):

```bash
zig build run                        # terminal 1 — mock on 8080/8081
cd web && npm install && npm run dev # terminal 2 — http://127.0.0.1:5173
```

Open [http://127.0.0.1:5173](http://127.0.0.1:5173). CORS is enabled on the REST mock; the page calls `http://127.0.0.1:8080` and `ws://127.0.0.1:8081/ws` directly.

## Layout

```
config-rest.json   # REST mock
config-ws.json     # WebSocket spam
src/main.zig       # CLI --rest / --ws
src/config.zig     # config parsing
src/actions.zig    # !{ACTION}
src/server.zig     # REST + WS listeners
web/               # Vite + React examples playground
```
