import { RestExample } from "./components/RestExample";
import { WsExample } from "./components/WsExample";
import { ActionsReference } from "./components/ActionsReference";
import { restExamples } from "./examples";

export default function App() {
  return (
    <div className="page">
      <div className="atmosphere" aria-hidden="true" />

      <header className="hero">
        <p className="hero__brand">GhostServer</p>
        <h1 className="hero__headline">Live mock examples</h1>
        <p className="hero__lede">
          Run Zig on :8080 / :8081, then hit each route and watch{" "}
          <code>!{"{ACTION}"}</code> results update.
        </p>
        <a className="btn btn--hero" href="#examples">
          Scroll to examples
        </a>
      </header>

      <main id="examples" className="examples">
        <WsExample />
        {restExamples.map((example) => (
          <RestExample key={example.id} example={example} />
        ))}
        <ActionsReference />
      </main>

      <footer className="footer">
        <p>
          Start mock: <code>zig build run</code> · Start UI:{" "}
          <code>cd web && npm run dev</code>
        </p>
      </footer>
    </div>
  );
}
