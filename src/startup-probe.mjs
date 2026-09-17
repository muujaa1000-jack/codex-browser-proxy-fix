// A bounded MCP startup check. No browser actions, credentials or external requests.
import { spawn, execFile } from 'node:child_process';
import { createInterface } from 'node:readline';
import { dirname, join } from 'node:path';
const launcher = process.argv[2];
const allowed = /^(path|systemroot|windir|temp|tmp|userprofile|localappdata|appdata|homedrive|homepath|programfiles|comspec)$/i;
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => allowed.test(key)));
env.CUA_REPL_NODE_REPL_PATH = join(dirname(process.execPath), 'node_repl.exe');
env.CUA_REPL_ENABLED_SURFACES = 'browser';
let child;
let finished = false;
let initialized = false;
let toolsReceived = false;
function stopFailed(reason = 'protocol') {
  console.error('Verification failed: ' + (typeof reason === 'string' ? reason : 'process error'));
  if (finished) return;
  finished = true;
  if (child?.pid && child.exitCode === null) {
    // Only the isolated probe process tree, never Codex or the user's browser.
    execFile('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true }, () => process.exit(1));
  } else process.exit(1);
}
const timer = setTimeout(stopFailed, 18000);
const syntax = spawn(process.execPath, ['--check', launcher], { env, windowsHide: true, stdio: 'ignore' });
child = syntax;
syntax.on('error', stopFailed);
syntax.on('exit', code => {
  if (finished) return;
  if (code !== 0) return stopFailed('syntax');
  child = spawn(process.execPath, [launcher], { env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  child.on('error', stopFailed);
  child.stdin.on('error', stopFailed);
  child.stderr.resume();
  const send = (method, params, id) => child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params, ...(id === undefined ? {} : { id }) }) + '\n');
  const lines = createInterface({ input: child.stdout });
  lines.on('line', line => {
    if (finished) return;
    try {
      const message = JSON.parse(line);
      if (message.error) return stopFailed('MCP response');
      if (message.id === 1 && message.result) {
        initialized = true;
        send('notifications/initialized', {});
        send('tools/list', {}, 2);
      } else if (message.id === 2 && Array.isArray(message.result?.tools)) {
        toolsReceived = message.result.tools.some(t => t.name === 'js');
        child.stdin.end();
      }
    } catch { stopFailed(); }
  });
  child.on('exit', code => {
    if (finished) return;
    if (code !== 0 || !initialized || !toolsReceived) return stopFailed('exit=' + code + ', initialized=' + initialized + ', tools=' + toolsReceived);
    finished = true;
    clearTimeout(timer);
    console.log(JSON.stringify({ initialized: true, cleanShutdown: true }));
  });
  send('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'proxy-fix-startup-check', version: '1' } }, 1);
});
