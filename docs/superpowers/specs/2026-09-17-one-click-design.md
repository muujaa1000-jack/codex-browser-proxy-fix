# One-click repair design

The approved design is a Windows PowerShell 7 repair core with a double-click launcher and a small Chinese window. No new packages, administrator privileges, scheduled jobs, account changes or application termination are required.

Discovery reads generated plugin manifests, accepts numeric plugin versions and runtime IDs dynamically, and confines runtime targets to the local Codex runtime tree. Multiple manifests require explicit selection. File contents must still match an existing original or exact backed-up patch fingerprint; unknown content is refused.

The window offers Check and repair, Restore original, and View result. First use requires a local HTTP proxy address; environment-derived suggestions are unconfirmed. A successful selection is saved locally. Later launches automatically repair only when a saved proxy and one candidate exist. Changing versions does not require selecting a new directory manually.

Operations run off the UI thread. A loopback TCP check precedes Apply. Runtime launchers are checked with Node syntax validation and a bounded MCP initialize/tools-list startup probe, with parent proxy keys removed to test launcher defaults. The tool reports startup validation separately from browser recovery. A verification failure rolls back only a patch made by that invocation and only if its bytes remain unchanged. Existing patches and later edits are never rolled back automatically.

The window never closes Codex or Chrome. Success tells the user to restart Codex and perform browser tests. Local settings store only the proxy address; no telemetry, logs, process environments or personal paths are published. Delivery is a local source folder and ZIP; GitHub publication is a separate action.

Validation covers dynamic discovery, refusal boundaries, settings, closed proxy ports, idempotency, rollback, UI construction and background result handling. Synthetic tests do not alter a real installation. A read-only check of the current patched installation and a private-copy startup probe complement the tests. Native UI interaction may be unavailable and must not be claimed if untested.
