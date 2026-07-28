export const REST_BASE = "http://127.0.0.1:8080";
export const WS_URL = "ws://127.0.0.1:8081/ws";

export type RestExampleDef = {
  id: string;
  title: string;
  description: string;
  method: "GET" | "POST";
  path: string;
  /** Route fragment as it appears in config-rest.json */
  config: string;
};

export type ActionDef = {
  name: string;
  args: string;
  result: string;
};

export const restExamples: RestExampleDef[] = [
  {
    id: "health",
    title: "Health check",
    description: "Static JSON — no actions.",
    method: "GET",
    path: "/api/health",
    config: `{
  "method": "GET",
  "path": "/api/health",
  "status": 200,
  "body": { "status": "ok" }
}`,
  },
  {
    id: "roll",
    title: "Random dice",
    description: "RANDOM_INT_IN_RANGE — fresh roll every request.",
    method: "GET",
    path: "/api/roll",
    config: `{
  "method": "GET",
  "path": "/api/roll",
  "body": {
    "dice": "!{RANDOM_INT_IN_RANGE} 1 6"
  }
}`,
  },
  {
    id: "scenario",
    title: "Sequence scenario",
    description: "SEQUENCE_* — advances round-robin across requests.",
    method: "GET",
    path: "/api/scenario",
    config: `{
  "method": "GET",
  "path": "/api/scenario",
  "body": {
    "step": "!{SEQUENCE_INT} 1 2 3",
    "label": "!{SEQUENCE_STRING} start mid end",
    "ready": "!{SEQUENCE_BOOL} false false true",
    "factor": "!{SEQUENCE_FLOAT} 0.5 1.0 1.5"
  }
}`,
  },
  {
    id: "lorem",
    title: "Lorem text",
    description: "LOREM — n words of classic lorem ipsum.",
    method: "GET",
    path: "/api/lorem",
    config: `{
  "method": "GET",
  "path": "/api/lorem",
  "body": {
    "text": "!{LOREM} 25"
  }
}`,
  },
  {
    id: "media",
    title: "Base64 + nullable",
    description: "BASE64 png/jpg plus NULLABLE_RANDOM_* (value or null).",
    method: "GET",
    path: "/api/media",
    config: `{
  "method": "GET",
  "path": "/api/media",
  "body": {
    "png": "!{BASE64} png",
    "jpg": "!{BASE64} jpg",
    "maybePng": "!{NULLABLE_BASE64} png",
    "score": "!{NULLABLE_RANDOM_INT} 1 2 3",
    "ratio": "!{NULLABLE_RANDOM_FLOAT} 1.1 2.1 3.1",
    "flag": "!{NULLABLE_RANDOM_BOOL}",
    "tag": "!{NULLABLE_RANDOM_STRING} a b c"
  }
}`,
  },
  {
    id: "spin",
    title: "Slot spin",
    description: "UUID + RANDOM_INT_MATRIX (5×3 reels).",
    method: "GET",
    path: "/api/spinMachine",
    config: `{
  "method": "GET",
  "path": "/api/spinMachine",
  "status": 200,
  "delay_ms": 100,
  "body": {
    "spinId": "!{UUID}",
    "reels": "!{RANDOM_INT_MATRIX} 5 3 0 7"
  }
}`,
  },
  {
    id: "users",
    title: "Users list",
    description: "RANDOM_STRING names for each user.",
    method: "GET",
    path: "/api/users",
    config: `{
  "method": "GET",
  "path": "/api/users",
  "status": 200,
  "headers": {
    "X-Mock": "ghost-server"
  },
  "body": {
    "users": [
      { "id": 1, "name": "!{RANDOM_STRING} Alice Alla" },
      { "id": 2, "name": "!{RANDOM_STRING} Bob Nob Rob" }
    ]
  }
}`,
  },
  {
    id: "user",
    title: "User by id",
    description: "ID, UUID, float score, bool, random name.",
    method: "GET",
    path: "/api/users/42",
    config: `{
  "method": "GET",
  "path": "/api/users/:id",
  "status": 200,
  "body": {
    "id": "!{ID}",
    "uuid": "!{UUID}",
    "score": "!{RANDOM_FLOAT_IN_RANGE} 0.0 100.0",
    "active": "!{RANDOM_BOOL}",
    "name": "!{RANDOM_STRING} Alpha Beta Gama"
  }
}`,
  },
  {
    id: "login",
    title: "Login failure",
    description: "POST returns 401 with delay_ms.",
    method: "POST",
    path: "/api/login",
    config: `{
  "method": "POST",
  "path": "/api/login",
  "status": 401,
  "delay_ms": 200,
  "body": { "error": "invalid_credentials" }
}`,
  },
];

export const wsConfig = `{
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
}`;

export const actionDocs: ActionDef[] = [
  {
    name: "RANDOM_INT_IN_RANGE",
    args: "min max",
    result: "Random integer inclusive of min and max",
  },
  {
    name: "RANDOM_INT",
    args: "n1 n2 …",
    result: "One random integer from the list",
  },
  {
    name: "RANDOM_INT_MATRIX",
    args: "outer inner min max",
    result: "2D int array (e.g. slot reels), each cell in [min, max]",
  },
  {
    name: "RANDOM_FLOAT_IN_RANGE",
    args: "min max",
    result: "Random float in [min, max)",
  },
  {
    name: "RANDOM_FLOAT",
    args: "f1 f2 …",
    result: "One random float from the list",
  },
  {
    name: "RANDOM_FLOAT_MATRIX",
    args: "outer inner min max",
    result: "2D float array, each cell in [min, max)",
  },
  {
    name: "RANDOM_BOOL",
    args: "—",
    result: "Random true or false",
  },
  {
    name: "RANDOM_STRING",
    args: "Word1 Word2 …",
    result: "One random token from the list",
  },
  {
    name: "NULLABLE_RANDOM_INT",
    args: "n1 n2 …",
    result: "One listed integer, or null (equal chance)",
  },
  {
    name: "NULLABLE_RANDOM_FLOAT",
    args: "f1 f2 …",
    result: "One listed float, or null (equal chance)",
  },
  {
    name: "NULLABLE_RANDOM_BOOL",
    args: "—",
    result: "true, false, or null (equal chance)",
  },
  {
    name: "NULLABLE_RANDOM_STRING",
    args: "Word1 Word2 …",
    result: "One listed token, or null (equal chance)",
  },
  {
    name: "SEQUENCE_INT",
    args: "n1 n2 …",
    result: "Round-robin through listed integers (1 → 2 → 3 → 1 …)",
  },
  {
    name: "SEQUENCE_FLOAT",
    args: "f1 f2 …",
    result: "Round-robin through listed floats",
  },
  {
    name: "SEQUENCE_BOOL",
    args: "b1 b2 …",
    result: "Round-robin through listed bools (true / false)",
  },
  {
    name: "SEQUENCE_STRING",
    args: "Word1 Word2 …",
    result: "Round-robin through listed tokens",
  },
  {
    name: "LOREM",
    args: "n",
    result: "n words of classic lorem ipsum (cycles if n is longer than the pool)",
  },
  {
    name: "BASE64",
    args: "png | jpg",
    result: "Fake image bytes (magic header + random) as base64; jpeg aliases jpg",
  },
  {
    name: "NULLABLE_BASE64",
    args: "png | jpg",
    result: "Same as BASE64, or null (50/50)",
  },
  {
    name: "TIMESTAMP_MS",
    args: "—",
    result: "Unix time in milliseconds",
  },
  {
    name: "TIMESTAMP_ISO",
    args: "—",
    result: "UTC timestamp YYYY-MM-DDTHH:MM:SSZ",
  },
  {
    name: "ID",
    args: "—",
    result: "Random 8-digit integer (10000000…99999999)",
  },
  {
    name: "UUID",
    args: "—",
    result: "Random UUID v4 string",
  },
];
