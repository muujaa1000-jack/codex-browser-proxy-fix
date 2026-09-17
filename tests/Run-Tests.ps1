#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '../src/ProxyFix.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) { throw 'FAIL: the guarded patch module has not been implemented.' }
$module = Import-Module $modulePath -Force -PassThru
$fixture = "// Synthetic fixture; not vendor source.`nenv: {`n      ...process.env,`n      FIXTURE: true`n}`n"
$fixtureBytes = [Text.Encoding]::UTF8.GetBytes($fixture)
$fixtureSha = [Security.Cryptography.SHA256]::Create()
try { $fixtureHash = ([BitConverter]::ToString($fixtureSha.ComputeHash($fixtureBytes))).Replace('-', '').ToLowerInvariant() }
finally { $fixtureSha.Dispose() }
& $module { param($hash) $script:OriginalHash = $hash } $fixtureHash
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempBase ('proxy-fix-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$script:count = 0
function Assert-True($Value, $Message) { if (-not $Value) { throw "FAIL: $Message" } }
function Expect-Failure([scriptblock]$Action) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-True $failed 'Expected refusal, but operation succeeded.'
}
function Test-Case($Name, [scriptblock]$Body) {
    $caseDir = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($caseDir) | Out-Null
    $path = Join-Path $caseDir 'launch.mjs'
    [IO.File]::WriteAllBytes($path, $fixtureBytes)
    & $Body $path $caseDir
    $script:count++
    Write-Host "PASS $Name"
}
try {
    Test-Case 'Check is read-only' {
        param($path, $dir)
        $r = Invoke-ProxyFix -Action Check -LauncherPath $path
        Assert-True ($r.Status -eq 'Compatible' -and -not $r.Changed) 'Expected Compatible.'
        Assert-True (@(Get-ChildItem -LiteralPath $dir).Count -eq 1) 'Check wrote files.'
    }
    Test-Case 'Apply supplies the selected proxy and preserves the original backup' {
        param($path)
        $r = Invoke-ProxyFix -Action Apply -LauncherPath $path -ProxyUrl 'http://127.0.0.1:12345'
        $text = [IO.File]::ReadAllText($path)
        Assert-True ($r.Status -eq 'Applied' -and $r.Changed) 'Expected Applied.'
        Assert-True ($text.Contains('http://127.0.0.1:12345')) 'Proxy absent.'
        Assert-True ($text.Contains('process.env.HTTPS_PROXY ||')) 'Existing proxy not preserved.'
        Assert-True ([IO.File]::ReadAllText("$path.codex-browser-proxy-fix.original.bak") -ceq $fixture) 'Backup changed.'
    }
    Test-Case 'Repeated Apply is a no-op and a different proxy is refused' {
        param($path)
        Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345' | Out-Null
        $before = [IO.File]::ReadAllText($path)
        $r = Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345'
        Assert-True ($r.Status -eq 'AlreadyPatched' -and -not $r.Changed) 'Duplicate patch.'
        Expect-Failure { Invoke-ProxyFix Apply $path 'http://127.0.0.1:12346' }
        Assert-True ([IO.File]::ReadAllText($path) -ceq $before) 'Changed proxy without restore.'
    }
    Test-Case 'Restore recovers exact bytes and can be repeated' {
        param($path)
        Invoke-ProxyFix Apply $path 'http://[::1]:12345' | Out-Null
        Assert-True ((Invoke-ProxyFix Check $path).Status -eq 'Patched') 'Patch not recognized.'
        Assert-True ((Invoke-ProxyFix Restore $path).Status -eq 'Restored') 'Restore failed.'
        Assert-True ([IO.File]::ReadAllText($path) -ceq $fixture) 'Restore differs.'
        Assert-True ((Invoke-ProxyFix Restore $path).Status -eq 'AlreadyOriginal') 'Repeated restore failed.'
        Assert-True ((Invoke-ProxyFix Apply $path 'http://[::1]:12345').Changed) 'Reapply failed.'
    }
    Test-Case 'Unknown bytes are refused without writes' {
        param($path, $dir)
        [IO.File]::AppendAllText($path, '// unknown change')
        $before = [IO.File]::ReadAllText($path)
        Assert-True ((Invoke-ProxyFix Check $path).Status -eq 'Unsupported') 'Unknown file accepted.'
        Expect-Failure { Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345' }
        Expect-Failure { Invoke-ProxyFix Restore $path }
        Assert-True ([IO.File]::ReadAllText($path) -ceq $before) 'Unknown file changed.'
        Assert-True (@(Get-ChildItem -LiteralPath $dir).Count -eq 1) 'Refusal wrote a backup.'
    }
    Test-Case 'Modified patch cannot be restored over' {
        param($path)
        Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345' | Out-Null
        [IO.File]::AppendAllText($path, '// later edit')
        $before = [IO.File]::ReadAllText($path)
        Expect-Failure { Invoke-ProxyFix Restore $path }
        Assert-True ([IO.File]::ReadAllText($path) -ceq $before) 'Later edits overwritten.'
    }
    Test-Case 'Corrupt backup prevents restore and is never overwritten' {
        param($path)
        Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345' | Out-Null
        $backup = "$path.codex-browser-proxy-fix.original.bak"
        [IO.File]::WriteAllText($backup, 'invalid backup')
        Expect-Failure { Invoke-ProxyFix Restore $path }
        Expect-Failure { Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345' }
        Assert-True ([IO.File]::ReadAllText($backup) -ceq 'invalid backup') 'Corrupt backup overwritten.'
    }
    Test-Case 'Interrupted apply with a valid backup can resume' {
        param($path)
        [IO.File]::WriteAllBytes("$path.codex-browser-proxy-fix.original.bak", $fixtureBytes)
        Assert-True ((Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345').Changed) 'Resume failed.'
    }
    Test-Case 'Proxy credentials, external hosts and injection-like input are refused' {
        param($path, $dir)
        foreach ($url in @('', 'http://127.0.0.1', 'http://127.0.0.1:0', 'http://127.0.0.1:65536', 'http://user:pass@127.0.0.1:12345', 'http://example.com:12345', 'https://127.0.0.1:12345', 'socks5://127.0.0.1:12345', 'http://127.0.0.1:12345/path', 'http://127.0.0.1:12345?x=1', 'http://127.0.0.1:12345#x', 'http://127.0.0.1:12345";alert(1)')) {
            Expect-Failure { Invoke-ProxyFix Apply $path $url }
        }
        Assert-True (@(Get-ChildItem -LiteralPath $dir).Count -eq 1) 'Invalid input wrote files.'
    }
    Test-Case 'Discovery uses the exact manifest launcher and refuses ambiguity' {
        param($path, $dir)
        $cache = Join-Path $dir 'plugins/cache/openai-bundled/unified-computer-use'
        $versionDir = Join-Path $cache '26.903.71938'
        $scripts = Join-Path $versionDir 'scripts'
        [IO.Directory]::CreateDirectory($scripts) | Out-Null
        $target = Join-Path $scripts 'launch.mjs'
        [IO.File]::WriteAllBytes($target, $fixtureBytes)
        $manifest = @{mcpServers=@{cua_repl=@{args=@($target);enabled=$true}}} | ConvertTo-Json -Depth 5
        [IO.File]::WriteAllText((Join-Path $versionDir '.mcp.json'), $manifest)
        Assert-True ((Find-ProxyFixLauncher -CodexHome $dir) -eq $target) 'Wrong launcher.'
        $other = Join-Path $cache '99.0.0'
        [IO.Directory]::CreateDirectory($other) | Out-Null
        [IO.File]::WriteAllText((Join-Path $other '.mcp.json'), '{}')
        Expect-Failure { Find-ProxyFixLauncher -CodexHome $dir }
        Assert-True ((Find-ProxyFixLauncher -CodexHome $dir -PluginVersion '26.903.71938') -eq $target) 'Explicit selection failed.'
        Expect-Failure { Find-ProxyFixLauncher -CodexHome $dir -PluginVersion '99.0.0' }
        [IO.File]::WriteAllText((Join-Path $versionDir '.mcp.json'), '{"mcpServers":{"cua_repl":{"args":["different-file.mjs"]}}}')
        Expect-Failure { Find-ProxyFixLauncher -CodexHome $dir -PluginVersion '26.903.71938' }
    }
    Test-Case 'A missing backup prevents restoration' {
        param($path)
        Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345' | Out-Null
        [IO.File]::Delete("$path.codex-browser-proxy-fix.original.bak")
        $before = [IO.File]::ReadAllText($path)
        Expect-Failure { Invoke-ProxyFix Restore $path }
        Assert-True ([IO.File]::ReadAllText($path) -ceq $before) 'Missing backup caused a write.'
    }
    Test-Case 'An invalid pre-existing backup prevents the first Apply' {
        param($path)
        [IO.File]::WriteAllText("$path.codex-browser-proxy-fix.original.bak", 'unrelated data')
        Expect-Failure { Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345' }
        Assert-True ([IO.File]::ReadAllText($path) -ceq $fixture) 'Overwrote the original.'
    }
    Test-Case 'An intervening file change prevents atomic replacement' {
        param($path)
        $before = [IO.File]::ReadAllText($path)
        Expect-Failure { & $module { param($p) Write-AtomicLauncher $p ([Text.Encoding]::UTF8.GetBytes('replacement')) ('0' * 64) } $path }
        Assert-True ([IO.File]::ReadAllText($path) -ceq $before) 'Intervening change was ignored.'
    }
    if ($IsWindows) {
        Test-Case 'Directory junctions are refused without changing the target' {
            param($path, $dir)
            $actual = Join-Path $dir 'actual'
            [IO.Directory]::CreateDirectory($actual) | Out-Null
            [IO.File]::WriteAllBytes((Join-Path $actual 'launch.mjs'), $fixtureBytes)
            $link = Join-Path $dir 'linked'
            New-Item -ItemType Junction -Path $link -Target $actual | Out-Null
            Expect-Failure { Invoke-ProxyFix Apply (Join-Path $link 'launch.mjs') 'http://127.0.0.1:12345' }
            Assert-True ([IO.File]::ReadAllText((Join-Path $actual 'launch.mjs')) -ceq $fixture) 'Junction target changed.'
        }
    }
    Test-Case 'Runtime launcher supports apply, repeat, exact restore and tamper refusal' {
        param($path)
        $runtimeText = "// Synthetic runtime fixture; not vendor source.`ntry {`n  await fixture.launch();`n} catch (error) { throw error; }`n"
        $runtimeBytes = [Text.Encoding]::UTF8.GetBytes($runtimeText)
        & $module { param($b) $script:RuntimeHash = Get-BytesHash $b } $runtimeBytes
        [IO.File]::WriteAllBytes($path, $runtimeBytes)
        Assert-True ((Invoke-ProxyFix Check $path).Status -eq 'Compatible') 'Runtime original not recognized.'
        Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345' | Out-Null
        $patched = [IO.File]::ReadAllText($path)
        Assert-True ($patched.Contains('process.env.HTTP_PROXY ||= "http://127.0.0.1:12345";')) 'Runtime proxy missing.'
        Assert-True ($patched.IndexOf('process.env.HTTP_PROXY') -lt $patched.IndexOf('try {')) 'Defaults must precede launch.'
        Assert-True ((Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345').Status -eq 'AlreadyPatched') 'Runtime patch not idempotent.'
        Expect-Failure { Invoke-ProxyFix Apply $path 'http://127.0.0.1:12346' }
        Assert-True ((Invoke-ProxyFix Restore $path).Status -eq 'Restored') 'Runtime restore failed.'
        Assert-True ([IO.File]::ReadAllText($path) -ceq $runtimeText) 'Runtime bytes changed after restore.'
        Invoke-ProxyFix Apply $path 'http://127.0.0.1:12345' | Out-Null
        [IO.File]::AppendAllText($path, '// later edit')
        Expect-Failure { Invoke-ProxyFix Restore $path }
    }
    Test-Case 'Dynamic runtime discovery verifies new versions, command and boundary' {
        param($path, $dir)
        $versionDir = Join-Path $dir 'plugins/cache/openai-bundled/unified-computer-use/88.123.45678'
        $runtimeRoot = Join-Path $dir 'runtimes/cua_node'
        $bin = Join-Path $runtimeRoot '0123456789abcdef/bin'
        $target = Join-Path $bin 'node_modules/@oai/cua-repl/bin/cua-repl.mjs'
        [IO.Directory]::CreateDirectory($versionDir) | Out-Null
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        [IO.File]::WriteAllText($target, '// fixture')
        $manifestPath = Join-Path $versionDir '.mcp.json'
        $server = @{command=(Join-Path $bin 'node.exe');args=@($target)}
        [IO.File]::WriteAllText($manifestPath, (@{mcpServers=@{cua_repl=$server}} | ConvertTo-Json -Depth 5))
        Assert-True ((Find-ProxyFixLauncher -CodexHome $dir -RuntimeRoot $runtimeRoot) -eq $target) 'Runtime discovery failed.'
        $server.command = Join-Path $dir 'other/node.exe'
        [IO.File]::WriteAllText($manifestPath, (@{mcpServers=@{cua_repl=$server}} | ConvertTo-Json -Depth 5))
        Expect-Failure { Find-ProxyFixLauncher -CodexHome $dir -RuntimeRoot $runtimeRoot }
        $server.command = Join-Path $bin 'node.exe'
        $server.args = @($path)
        [IO.File]::WriteAllText($manifestPath, (@{mcpServers=@{cua_repl=$server}} | ConvertTo-Json -Depth 5))
        Expect-Failure { Find-ProxyFixLauncher -CodexHome $dir -RuntimeRoot $runtimeRoot }
    }
    Write-Host "$script:count tests passed. No real installation was modified."
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'proxy-fix-tests-*') { throw 'Refusing unsafe test cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
