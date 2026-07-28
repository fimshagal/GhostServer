import { useState } from "react";
import { REST_BASE, type RestExampleDef } from "../examples";

type Result = {
  status: number;
  ok: boolean;
  body: string;
};

type Props = {
  example: RestExampleDef;
};

export function RestExample({ example }: Props) {
  const [result, setResult] = useState<Result | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [flash, setFlash] = useState(false);

  async function run() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`${REST_BASE}${example.path}`, {
        method: example.method,
      });
      const text = await res.text();
      let body = text;
      try {
        body = JSON.stringify(JSON.parse(text), null, 2);
      } catch {
        /* keep raw text */
      }
      setResult({ status: res.status, ok: res.ok, body });
      setFlash(true);
      window.setTimeout(() => setFlash(false), 450);
    } catch (err) {
      setResult(null);
      setError(
        err instanceof Error
          ? err.message
          : "Request failed — is GhostServer running on :8080?",
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <section className="example" id={example.id}>
      <header className="example__head">
        <p className="example__method">
          <span className={`method method--${example.method.toLowerCase()}`}>
            {example.method}
          </span>
          <code>{example.path}</code>
        </p>
        <h2 className="example__title">{example.title}</h2>
        <p className="example__desc">{example.description}</p>
      </header>

      <div className="example__panels">
        <div className="panel">
          <div className="panel__label">Config</div>
          <pre className="code">
            <code>{example.config}</code>
          </pre>
        </div>

        <div className={`panel panel--result${flash ? " panel--flash" : ""}`}>
          <div className="panel__bar">
            <span className="panel__label">Result</span>
            <button
              type="button"
              className="btn"
              onClick={run}
              disabled={loading}
            >
              {loading ? "Running…" : "Run"}
            </button>
          </div>
          {error ? (
            <pre className="code code--error">
              <code>{error}</code>
            </pre>
          ) : result ? (
            <>
              <p className="status">
                <span
                  className={
                    result.ok ? "status__badge status__badge--ok" : "status__badge"
                  }
                >
                  {result.status}
                </span>
              </p>
              <pre className="code">
                <code>{result.body}</code>
              </pre>
            </>
          ) : (
            <pre className="code code--muted">
              <code>Press Run to call GhostServer</code>
            </pre>
          )}
        </div>
      </div>
    </section>
  );
}
