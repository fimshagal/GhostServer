import { useEffect, useRef, useState } from "react";
import { WS_URL, wsConfig } from "../examples";

const MAX_MESSAGES = 8;

type Msg = {
  id: number;
  raw: string;
  pretty: string;
};

export function WsExample() {
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [messages, setMessages] = useState<Msg[]>([]);
  const [flash, setFlash] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);
  const idRef = useRef(0);

  useEffect(() => {
    return () => {
      wsRef.current?.close();
      wsRef.current = null;
    };
  }, []);

  function connect() {
    if (wsRef.current) return;
    setConnecting(true);
    setError(null);

    const ws = new WebSocket(WS_URL);
    wsRef.current = ws;

    ws.onopen = () => {
      setConnected(true);
      setConnecting(false);
    };

    ws.onmessage = (e) => {
      const raw = String(e.data);
      let pretty = raw;
      try {
        pretty = JSON.stringify(JSON.parse(raw), null, 2);
      } catch {
        /* keep raw */
      }
      idRef.current += 1;
      const msg: Msg = { id: idRef.current, raw, pretty };
      setMessages((prev) => [msg, ...prev].slice(0, MAX_MESSAGES));
      setFlash(true);
      window.setTimeout(() => setFlash(false), 350);
    };

    ws.onerror = () => {
      setError("WebSocket error — is GhostServer WS running on :8081?");
      setConnecting(false);
    };

    ws.onclose = () => {
      wsRef.current = null;
      setConnected(false);
      setConnecting(false);
    };
  }

  function disconnect() {
    wsRef.current?.close();
    wsRef.current = null;
    setConnected(false);
  }

  return (
    <section className="example" id="websocket">
      <header className="example__head">
        <p className="example__method">
          <span className="method method--ws">WS</span>
          <code>{WS_URL}</code>
        </p>
        <h2 className="example__title">WebSocket stream</h2>
        <p className="example__desc">
          From config-ws.json — pushes JSON every interval_ms with TIMESTAMP and
          RANDOM actions.
        </p>
      </header>

      <div className="example__panels">
        <div className="panel">
          <div className="panel__label">Config</div>
          <pre className="code">
            <code>{wsConfig}</code>
          </pre>
        </div>

        <div className={`panel panel--result${flash ? " panel--flash" : ""}`}>
          <div className="panel__bar">
            <span className="panel__label">
              Live
              {connected ? (
                <span className="live-dot" aria-label="connected" />
              ) : null}
            </span>
            {connected ? (
              <button type="button" className="btn btn--ghost" onClick={disconnect}>
                Disconnect
              </button>
            ) : (
              <button
                type="button"
                className="btn"
                onClick={connect}
                disabled={connecting}
              >
                {connecting ? "Connecting…" : "Connect"}
              </button>
            )}
          </div>

          {error ? (
            <pre className="code code--error">
              <code>{error}</code>
            </pre>
          ) : messages.length === 0 ? (
            <pre className="code code--muted">
              <code>
                {connected
                  ? "Waiting for messages…"
                  : "Press Connect to open the WebSocket"}
              </code>
            </pre>
          ) : (
            <div className="ws-log">
              {messages.map((m) => (
                <pre key={m.id} className="code code--ws">
                  <code>{m.pretty}</code>
                </pre>
              ))}
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
