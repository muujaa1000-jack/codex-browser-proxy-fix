# Codex Browser Proxy Fix

[简体中文教程](README.zh-CN.md) · English

An **unofficial, fingerprint-guarded Windows workaround** for one specific failure mode: Codex browser-control processes do not receive the local proxy environment they need.

This is not a universal browser repair tool. Extension connection errors, a closed Chrome instance, authentication failures, website restrictions, and application routing bugs can have different causes. `Check` verifies local file compatibility; it cannot determine the environment of an already-running process or prove the cause of a timeout.

## Double-click repair (local v0.3.0)

Extract the complete folder and double-click **Start-Repair.cmd**. Requires Windows and PowerShell 7. The current window is in Chinese; English CLI instructions remain below.

1. On first use, confirm your local HTTP/mixed proxy address and select **检查并修复** (Check and repair). Suggestions from environment variables are not automatically accepted.
2. After a successful check, only that proxy URL is saved locally. Later launches automatically check/repair when exactly one plugin manifest is present. Multiple cached versions require you to select the active version; it never guesses the newest.
3. **恢复原文件** restores the verified backup; **查看结果** shows the local result. No applications are force-closed.
4. **Applied** means the patch was applied; restart Codex after finishing tasks and perform the browser test below. **AlreadyPatched** means no file rewrite was needed.

Runtime verification starts an isolated local MCP process with proxy environment keys removed. It checks syntax, initialize/tools-list and clean shutdown. It does not operate a browser or prove upstream connectivity. A failed check rolls back only a patch made by that invocation if the file has not changed. An existing patch is retained on verification failure. Legacy launchers receive file validation only.

The GUI keeps its proxy setting at `%LOCALAPPDATA%\CodexBrowserProxyFix\settings.json`; it is not stored in this repository or uploaded. It does not scan ports. Unknown content, edited files and ambiguous targets remain protected. Changing directory/version IDs is supported, but changed launcher code may need a future tool update.

If Windows blocks downloaded scripts, review the files first and unblock the files in this extracted tool only. No execution-policy change is required:

```powershell
'./Start-Repair.cmd','./Repair-Window.ps1','./Repair-CodexBrowserProxy.ps1','./src/ProxyFix.psm1','./src/RepairWorkflow.psm1','./src/startup-probe.mjs' | ForEach-Object { Unblock-File -LiteralPath $_ }
```

Custom Codex home: `pwsh -NoProfile -STA -File ./Repair-Window.ps1 -CodexHome 'YOUR_ABSOLUTE_LOCAL_DIRECTORY'`.

## Support and evidence

| Item | Current support |
| --- | --- |
| OS | Windows |
| Shell | PowerShell 7.0 or later (`pwsh`); implementation tested locally on 7.6.5 |
| Discovery | Legacy 26.903.71938; runtime layouts discovered from numeric plugin versions and 16-character runtime IDs |
| Original launcher SHA256 | `a50b66879f7b72e45ab6fbaad77eff14a87680a946135f410c121b9b166a2597` |
| Proxy | Credential-free **HTTP proxy** on `127.0.0.1` or `[::1]`, explicit port |
| Additional packages | None |

A preceding local experiment on Codex desktop package 26.903.9818.0 restored page opening, content reading, link clicking and back navigation in both Chrome and the in-app browser after a restart. The patch survived that restart. This is single-environment evidence, not a cross-version or long-term reliability claim. The plugin and desktop package version numbers are different identifiers.

The released script adds backup and validation checks around that workaround. It refuses any launcher bytes it does not recognize, including independently edited or manually patched copies. Do not replace the expected fingerprint to make a newer version pass.

### New runtime launcher (v0.2.0)

Plugin **26.908.40834** uses the runtime entry `bin/node_modules/@oai/cua-repl/bin/cua-repl.mjs` under runtime **a708e72b10c27b59**, instead of the old plugin `scripts/launch.mjs`. Its verified original SHA256 is `992174a5e637645aeb444adfdb1bae688e997bb84d7db07532f68e358e60f278`. The table fingerprint above belongs to the older launcher.

Discovery now checks the generated manifest against the local Codex runtime directory and its matching Node executable. Directory IDs can change; unknown launcher contents are still refused. For this entry, fallback environment values are inserted before `launch()` and inherited by the child process.

A local repair on desktop **26.908.4834.0**, using this insertion point, survived a restart and passed open/read/click/back in Chrome and the in-app browser. The released script is separately tested on an unpublished original-file copy for apply/repeat/restore and process environment forwarding. This does not establish reliability on all sites or future upgrades.

If multiple plugin versions are cached, append `-PluginVersion 26.908.40834` to each command only after confirming it is active. A manual patch is intentionally reported as Unsupported: v0.2.0 does not adopt or overwrite it. If your manual repair works, leave it in place.

## 1. Get the tool

Download the source ZIP from this repository's **Code → Download ZIP** or **Releases**, then extract it. Open **PowerShell 7** in the extracted folder. Do not run the script from inside the ZIP.

Check your shell:

```powershell
$PSVersionTable.PSVersion
```

If the major version is 5, open PowerShell 7 instead. If PowerShell blocks a downloaded file, inspect it first. You can then unblock just the two reviewed files, without changing your execution policy:

```powershell
Unblock-File -LiteralPath .\Repair-CodexBrowserProxy.ps1
Unblock-File -LiteralPath .\src\ProxyFix.psm1
```

No administrator session, global execution-policy change, extension reinstall or login change is required by this tool.

## 2. Check compatibility

Open Codex at least once so it generates the plugin manifest. Finish any running tasks before applying the patch; the tool never force-closes applications.

```powershell
pwsh -NoProfile -File .\Repair-CodexBrowserProxy.ps1 -Action Check
```

- **Compatible:** the launcher matches the verified original. This does not prove that you need this fix.
- **Patched:** this tool's exact patch and original backup are recognized.
- **Unsupported:** different bytes, a prior manual edit, or an unrecognized/damaged backup. No files are changed.
- **No unique plugin candidate:** multiple cached versions exist. Check the active version in Codex. If it is the supported version, pass `-PluginVersion` with that exact version on **each** command. Do not guess which version is active.

The default location is `CODEX_HOME` when set, otherwise `$env:USERPROFILE\.codex`. For a custom installation, pass `-CodexHome` with its absolute local directory. Linked/redirected directories, UNC paths and unsupported layouts are refused.

## 3. Choose your own proxy and apply

Find the **HTTP or mixed proxy listening port** in your local proxy application. Do not use a SOCKS-only port. Start that application first.

The following **7890 is an example**, not an automatically detected value. Substitute your actual port:

```powershell
pwsh -NoProfile -File .\Repair-CodexBrowserProxy.ps1 -Action Apply -ProxyUrl 'http://127.0.0.1:7890'
```

For a proxy listening only on IPv6 loopback, use `http://[::1]:YOUR_PORT` with a numeric port. External hosts, usernames, passwords, URL paths, queries, fragments, HTTPS and SOCKS URLs are not supported in this release. Do not enter credentials.

Apply checks that the specified local TCP port accepts a connection. This proves only that a listener exists—not that it speaks HTTP proxy or can reach upstream services. The tool does not make external test requests or reuse account credentials.

Expected result: **Applied**. The original launcher is backed up next to itself as `<launcher filename>.codex-browser-proxy-fix.original.bak` (the filename is `launch.mjs` or `cua-repl.mjs`). Keep that file. Repeating Apply with the same address returns **AlreadyPatched**. To change the address, Restore first.

## 4. Restart and verify actual browser operations

Completely exit and reopen Codex after finishing running tasks. Open Chrome if you want to use Chrome control. Resetting only the JavaScript session does not necessarily restart the tool process.

Ask Codex:

> Retest browser control in Chrome and the in-app browser separately. Open https://example.com, read its heading and text, click Learn more and read the destination page, then go back. Close only the test tabs. Report the result for each browser separately.

Both browsers should open **Example Domain**, follow the link to **IANA Example Domains**, and return. A successful file patch or MCP startup alone is not browser recovery. If navigation still fails, keep the exact error and which browser failed; investigate that separately instead of repeatedly applying the patch.

## 5. Restore

```powershell
pwsh -NoProfile -File .\Repair-CodexBrowserProxy.ps1 -Action Restore
```

Expected result: **Restored**, or **AlreadyOriginal** if no change is needed. Restart Codex again for the restored launcher to take effect. The backup is retained.

Restore requires the original backup fingerprint and the exact recognized current patch. It refuses to overwrite later edits or restore an old file over an unrecognized upgraded launcher. If the backup is missing/corrupt, or you applied a separate manual patch, use your own verified original backup or the application's normal plugin reinstall/update path. Do not copy a launcher from a stranger's computer.

## What it changes

Only the verified launcher is changed to supply four environment defaults to the browser tool process:

- `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`: your supplied local HTTP proxy URL.
- `NO_PROXY`: `localhost,127.0.0.1,::1`.

Existing non-empty uppercase environment values take precedence. The local proxy must remain available while the affected browser tool is used.

The tool does not edit system proxy settings, DNS, registry entries, account/auth settings, browser profiles, permission lists or security checks. It does not start/stop Codex, Chrome, or proxy applications. There is no telemetry or upload. Manifest content is used only to find/validate the launcher; its commands are never executed by this tool.

An ordinary user-level `mcp_servers.cua_repl` override was removed by the observed desktop version during startup. This workaround therefore edits the launch script rather than relying on that override. Application updates, reinstalls or forced plugin refreshes may overwrite the patch. Recheck compatibility after those events; do not set up an automatic re-patching loop.

## Troubleshooting and private issue reports

| Result | Next step |
| --- | --- |
| Local proxy port is unreachable | Start your proxy and verify its HTTP/mixed port. |
| Compatible but no browser failure | Leave the installation unchanged. |
| Chrome is unavailable | Open Chrome and check its Codex extension connection. |
| Patch applied but navigation fails | Run the actual browser test above; this may be a different cause. |
| Unsupported after an update | The content or layout is unknown; stop instead of forcing it. |
| Access denied / linked path refused | Stop and inspect the installation locally; do not broaden permissions just to force it. |

For an issue, share only OS version, PowerShell version, Codex/plugin versions, the status label, and a **redacted** error description. Do not post `config.toml`, `.mcp.json`, full logs, process environments, screenshots with account information, local usernames/paths, tokens, cookies or browsing history. The repository does not need any of them. Review all output before sharing it; operating-system errors can include local paths.

## Development

```powershell
pwsh -NoProfile -File .\tests\Run-Tests.ps1
pwsh -NoProfile -File .\tests\Workflow-Tests.ps1
pwsh -NoProfile -File .\tests\Probe-Tests.ps1
pwsh -NoProfile -File .\tests\Window-Tests.ps1
```

Tests use original synthetic fixture text and temporary directories. They do not include or modify a real Codex installation. The production CLI exposes no fingerprint-bypass option. Integration with the verified vendor launcher is tested locally using an unpublished temporary copy; vendor code and local diagnostics are not distributed here.

MIT applies to this repository's original code and documentation. Codex and its bundled components are not included or relicensed. This project is not affiliated with or endorsed by OpenAI.
