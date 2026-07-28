import { actionDocs } from "../examples";

export function ActionsReference() {
  return (
    <section className="actions-ref" id="actions">
      <header className="example__head">
        <h2 className="example__title">Actions reference</h2>
        <p className="example__desc">
          A string that starts with <code>!{"{ACTION_NAME}"}</code> is evaluated
          on every REST request / WS message. Identical{" "}
          <code>SEQUENCE_*</code> markers share one counter for the process
          lifetime.
        </p>
      </header>

      <div className="actions-table-wrap">
        <table className="actions-table">
          <thead>
            <tr>
              <th>Action</th>
              <th>Arguments</th>
              <th>Result</th>
            </tr>
          </thead>
          <tbody>
            {actionDocs.map((action) => (
              <tr key={action.name}>
                <td>
                  <code>{action.name}</code>
                </td>
                <td>
                  <code>{action.args}</code>
                </td>
                <td>{action.result}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
