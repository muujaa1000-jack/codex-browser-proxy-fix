# Changelog

## v0.3.0

- Field report (2026-09-18): a user confirmed the tool worked after a further Codex update; future-version compatibility is not guaranteed.

- Add a Chinese double-click repair window with saved local proxy preferences and background validation.
- Discover changing runtime/version directories from the manifest while retaining exact file fingerprints and path boundaries.
- Add bounded MCP startup verification and rollback of newly applied, unchanged patches on failure.
- Keep existing patches on verification failure and never close Codex or Chrome.
- Add workflow and startup-probe tests. Browser recovery still requires restart and actual page verification.

## v0.2.0

- Support unified-computer-use 26.908.40834 and verified runtime a708e72b10c27b59; retain 26.903.71938 support.
- Validate the runtime launcher and Node command against the generated manifest.
- Preserve exact fingerprint, backup, idempotency and restore guards.
- Add runtime regression tests and update English/Chinese instructions.
- Manually edited files and unknown runtimes remain unsupported. Updates may replace the patch.

## v0.1.0

- Initial guarded Windows proxy workaround for plugin 26.903.71938.
