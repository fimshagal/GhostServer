# GhostServer

Локальний mock-сервер на Zig: **REST** і **WebSocket**. Читає JSON-конфіги й віддає заготовлені відповіді з `![[ACTION]]` препроцесингом.

Потрібен **Zig 0.16+**.

## Збірка і запуск

```bash
zig build
zig build run
```

`zig build run` за замовчуванням піднімає обидва сервіси з `config-rest.json` + `config-ws.json`.

Явно:

```bash
.\zig-out\bin\GhostServer.exe --rest config-rest.json --ws config-ws.json
zig build run -- --rest config-rest.json --ws config-ws.json
```

Лише один режим:

```bash
.\zig-out\bin\GhostServer.exe --rest config-rest.json
.\zig-out\bin\GhostServer.exe --ws config-ws.json
```

Без аргументів exe шукає `config-rest.json` / `config-ws.json` поруч із собою, потім у cwd.

Якщо бачиш `AddressInUse` / exit code 255 — уже крутиться інший GhostServer на 8080/8081. Зупини його і запусти знову.

```bash
zig build test
```

## Host (bind)

Bind працює лише на IP інтерфейсу машини:

- `127.0.0.1` — локально
- `0.0.0.0` — усі інтерфейси (клієнт ходить на LAN IP ПК)
- `171.0.0.1` — **ні**, якщо адресу не додано на адаптер

## Конфіги

### REST — `config-rest.json`

| Поле | Тип | Default | Опис |
|------|-----|---------|------|
| `mode` | string | `rest` | має бути `rest` |
| `host` | string | `127.0.0.1` | bind address |
| `port` | number | `8080` | порт |
| `cors` | bool | `true` | CORS + auto OPTIONS |
| `routes` | array | `[]` | REST ендпоінти |

Route: `method`, `path`, `status`, `delay_ms`, `headers`, `body`.

### WebSocket — `config-ws.json`

| Поле | Тип | Default | Опис |
|------|-----|---------|------|
| `mode` | string | — | `ws` |
| `host` | string | `127.0.0.1` | bind address |
| `port` | number | `8081` | порт |
| `path` | string | `/ws` | шлях upgrade |
| `interval_ms` | number | `1000` | інтервал спаму повідомлень |
| `message` | any | — | шаблон повідомлення (з екшенами) |

Приклад WS:

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

Рядкове значення, що починається з `![[ACTION_NAME]]`, обчислюється **на кожен** REST-запит / WS-повідомлення.

| Action | Аргументи | Результат |
|--------|-----------|-----------|
| `RANDOM_INT_IN_RANGE` | `min max` | випадкове ціле (включно) |
| `RANDOM_FLOAT_IN_RANGE` | `min max` | випадковий float у `[min, max)` |
| `RANDOM_BOOL` | — | `true` / `false` |
| `RANDOM_STRING` | `Word1 Word2 ...` | один випадковий токен |
| `TIMESTAMP_MS` | — | unix time у мілісекундах |
| `TIMESTAMP_ISO` | — | `YYYY-MM-DDTHH:MM:SSZ` |

Нові екшени — у `src/actions.zig` (`builtins`).

## Тест з консолі

### REST

У PowerShell використовуйте `curl.exe`:

```powershell
curl.exe http://127.0.0.1:8080/api/health
curl.exe http://127.0.0.1:8080/api/roll
curl.exe -X POST http://127.0.0.1:8080/api/login
```

### WebSocket

Нативного зручного клієнта в PowerShell немає:

```powershell
# websocat (якщо встановлений):
websocat ws://127.0.0.1:8081/ws

# WebSocket (Node 22+)
node -e "const ws=new WebSocket('ws://127.0.0.1:8081/ws'); ws.onmessage=e=>console.log(e.data)"

# або через npx:
npx --yes wscat -c ws://127.0.0.1:8081/ws
```

Сервер раз на `interval_ms` шле JSON з timestamp і payload.

## З веб-проєкту

```js
// REST
const res = await fetch("http://127.0.0.1:8080/api/users");
const data = await res.json();

// WebSocket
const ws = new WebSocket("ws://127.0.0.1:8081/ws");
ws.onmessage = (e) => console.log(JSON.parse(e.data));
```

## Структура

```
config-rest.json   # REST mock
config-ws.json     # WebSocket spam
src/main.zig       # CLI --rest / --ws
src/config.zig     # парсинг конфігів
src/actions.zig    # ![[ACTION]]
src/server.zig     # REST + WS listeners
```
