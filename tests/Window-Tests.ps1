#requires -Version 7.0
$ErrorActionPreference='Stop'
$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root=Join-Path $tempBase ('proxy-window-tests-' + [guid]::NewGuid().ToString('N'))
try {
    $version=Join-Path $root 'plugins/cache/openai-bundled/unified-computer-use/26.903.71938'
    [IO.Directory]::CreateDirectory((Join-Path $version 'scripts')) | Out-Null
    $launcher=Join-Path $version 'scripts/launch.mjs'
    [IO.File]::WriteAllText($launcher,'// Unknown synthetic fixture, never patched.')
    [IO.File]::WriteAllText((Join-Path $version '.mcp.json'),(@{mcpServers=@{cua_repl=@{args=@($launcher)}}} | ConvertTo-Json -Depth 5))
    $window=Join-Path $PSScriptRoot '../Repair-Window.ps1'
    $result = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -STA -File $window -SmokeTest -CodexHome $root
    if ($LASTEXITCODE -ne 0) { throw 'Window smoke check failed.' }
    $data=$result | ConvertFrom-Json
    if ($data.Controls -ne 11 -or $data.Visible -or $data.WorkerStatus -ne 'Unsupported') { throw 'Unexpected window/worker state.' }
    if ([IO.File]::ReadAllText($launcher) -cne '// Unknown synthetic fixture, never patched.') { throw 'Read-only smoke check changed fixture.' }
    Write-Host 'PASS window construction and asynchronous read-only worker (no visible UI interaction)'
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    if (-not $resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'proxy-window-tests-*') { throw 'Unsafe cleanup.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
