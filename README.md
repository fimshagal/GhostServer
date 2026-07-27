# GhostServer

A local Zig mock server for **REST** and **WebSocket**. It reads JSON configs and returns prepared responses with `![[ACTION]]` preprocessing.

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

Bind only works for an IP that exists on a local network interface:

- `127.0.0.1` — local only
- `0.0.0.0` — all interfaces (clients use the machine’s LAN IP)
- `171.0.0.1` — **no**, unless that address is assigned to an adapter

## Configs

### REST — `config-rest.json`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mode` | string | `rest` | must be `rest` |
| `host` | string | `127.0.0.1` | bind address |
| `port` | number | `8080` | port |
| `cors` | bool | `true` | CORS + auto OPTIONS |
| `routes` | array | `[]` | REST endpoints |

Route fields: `method`, `path`, `status`, `delay_ms`, `headers`, `body`.

### WebSocket — `config-ws.json`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mode` | string | — | `ws` |
| `host` | string | `127.0.0.1` | bind address |
| `port` | number | `8081` | port |
| `path` | string | `/ws` | upgrade path |
| `interval_ms` | number | `1000` | message spam interval |
| `message` | any | — | message template (with actions) |

WS example:

```json
{
  "mode": "ws",
  "host": "127.0.0.1",
  "port": 8081,
  "path": "/ws",
  "interval_ms": 1000,
  "message": {
    "ts": "![[TIMESTAMP_MS]]",
    "iso": "![[TIMESTAMP_ISO]]",
    "payload": "![[RANDOM_INT_IN_RANGE]] 1 100",
    "label": "![[RANDOM_STRING]] tick pulse beat"
  }
}
```

## Actions (`![[...]]`)

A string value that starts with `![[ACTION_NAME]]` is evaluated on **every** REST request / WS message.

| Action | Arguments | Result |
|--------|-----------|--------|
| `RANDOM_INT_IN_RANGE` | `min max` | random integer (inclusive) |
| `RANDOM_FLOAT_IN_RANGE` | `min max` | random float in `[min, max)` |
| `RANDOM_BOOL` | — | `true` / `false` |
| `RANDOM_STRING` | `Word1 Word2 ...` | one random token |
| `TIMESTAMP_MS` | — | unix time in milliseconds |
| `TIMESTAMP_ISO` | — | `YYYY-MM-DDTHH:MM:SSZ` |
| `UUID` | — | random UUID v4 string |

Add new actions in `src/actions.zig` (`builtins`).

## Console testing

### REST

In PowerShell use `curl.exe`:

```powershell
curl.exe http://127.0.0.1:8080/api/health
curl.exe http://127.0.0.1:8080/api/roll
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

## Layout

```
config-rest.json   # REST mock
config-ws.json     # WebSocket spam
src/main.zig       # CLI --rest / --ws
src/config.zig     # config parsing
src/actions.zig    # ![[ACTION]]
src/server.zig     # REST + WS listeners
```
