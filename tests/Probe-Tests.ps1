#requires -Version 7.0
param([string]$NodePath = 'node')
$ErrorActionPreference='Stop'
$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root=Join-Path $tempBase ('proxy-probe-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$probe=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../src/startup-probe.mjs'))
function Run-Probe([string]$file) {
    $info=[Diagnostics.ProcessStartInfo]::new($NodePath)
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $info.Environment['HTTP_PROXY']='http://127.0.0.1:12345'
    $info.ArgumentList.Add($probe); $info.ArgumentList.Add($file)
    $p=[Diagnostics.Process]::new(); $p.StartInfo=$info
    try {
        $null=$p.Start(); $out=$p.StandardOutput.ReadToEndAsync(); $err=$p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(24000)) { $p.Kill($true); throw 'Probe did not honor timeout.' }
        return @{Code=$p.ExitCode; Output=$out.GetAwaiter().GetResult()}
    } finally { $p.Dispose() }
}
try {
    $fixture=Join-Path $root 'fixture.mjs'
    $source=@'
import {createInterface} from 'node:readline';
import {isAbsolute} from 'node:path';
if (process.env.HTTP_PROXY || !isAbsolute(process.env.CUA_REPL_NODE_REPL_PATH ?? '')) process.exit(4);
const lines=createInterface({input:process.stdin});
lines.on('line',line=>{
 const m=JSON.parse(line);
 if(m.id===1) console.log(JSON.stringify({jsonrpc:'2.0',id:1,result:{}}));
 if(m.id===2) console.log(JSON.stringify({jsonrpc:'2.0',id:2,result:{tools:[{name:'js'}]}}));
});
'@
    [IO.File]::WriteAllText($fixture,$source)
    $r=Run-Probe $fixture
    if ($r.Code -ne 0 -or -not ($r.Output | ConvertFrom-Json).cleanShutdown) { throw 'Valid probe failed.' }
    Write-Host 'PASS MCP startup, isolated environment and clean shutdown'
    [IO.File]::WriteAllText($fixture,$source.Replace("name:'js'","name:'unexpected'"))
    if ((Run-Probe $fixture).Code -eq 0) { throw 'Missing tool was accepted.' }
    Write-Host 'PASS missing tool refusal'
    [IO.File]::WriteAllText($fixture,'invalid !!! javascript')
    if ((Run-Probe $fixture).Code -eq 0) { throw 'Invalid syntax was accepted.' }
    Write-Host 'PASS syntax failure'
    [IO.File]::WriteAllText($fixture,'setInterval(()=>{},1000);')
    if ((Run-Probe $fixture).Code -eq 0) { throw 'Hung startup was accepted.' }
    Write-Host 'PASS bounded hung-process cleanup'
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    if (-not $resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'proxy-probe-tests-*') { throw 'Unsafe cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
