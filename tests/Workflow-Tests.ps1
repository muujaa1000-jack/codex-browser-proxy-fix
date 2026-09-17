#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '../src/RepairWorkflow.psm1'
if (-not (Test-Path $modulePath)) { throw 'FAIL: repair workflow is not implemented.' }
$workflow = Import-Module $modulePath -Force -PassThru
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root = Join-Path $tempBase ('proxy-workflow-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
function Assert($condition, $message) { if (-not $condition) { throw "FAIL: $message" } }
function Refuses([scriptblock]$body) { $refused=$false; try { & $body | Out-Null } catch { $refused=$true }; Assert $refused 'Expected refusal.' }
try {
    $fixture = "// Synthetic fixture`ntry {`n  await fixture.launch();`n} catch(e) { throw e; }`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($fixture)
    & $workflow { param($b) & $script:Core { param($b) $script:RuntimeHash = Get-BytesHash $b } $b } $bytes
    $path = Join-Path $root 'cua-repl.mjs'
    [IO.File]::WriteAllBytes($path,$bytes)
    $settings = Join-Path $root 'settings.json'
    Assert ($null -eq (Read-RepairSettings $settings)) 'Missing settings must be unconfirmed.'
    Save-RepairSettings $settings 'http://127.0.0.1:12345'
    Assert ((Read-RepairSettings $settings) -eq 'http://127.0.0.1:12345') 'Settings roundtrip.'
    Refuses { Save-RepairSettings $settings 'http://user:secret@example.com:90' }
    [IO.File]::WriteAllText($settings,'invalid')
    Assert ($null -eq (Read-RepairSettings $settings)) 'Corrupt settings must be unconfirmed.'
    Write-Host 'PASS settings, invalid input, corrupt settings'
    Refuses { Invoke-RepairWorkflow -LauncherPath $path -ProxyUrl 'http://127.0.0.1:1' }
    Assert ([IO.File]::ReadAllText($path) -ceq $fixture) 'Closed port changed launcher.'
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $listener.Start(); $proxy = "http://127.0.0.1:$($listener.LocalEndpoint.Port)"
    try {
        $r = Invoke-RepairWorkflow -LauncherPath $path -ProxyUrl $proxy -Verifier { param($p) throw 'synthetic verification failure' }
        Assert ($r.Status -eq 'RolledBack') 'Failure did not roll back.'
        Assert ([IO.File]::ReadAllText($path) -ceq $fixture) 'Rollback not exact.'
        $r = Invoke-RepairWorkflow -LauncherPath $path -ProxyUrl $proxy -Verifier { param($p) }
        Assert ($r.Status -eq 'Applied') 'Apply failed.'
        $r = Invoke-RepairWorkflow -LauncherPath $path -ProxyUrl $proxy -Verifier { param($p) throw 'existing failure' }
        Assert ($r.Status -eq 'VerificationFailed') 'Existing patch rolled back.'
        Assert ([IO.File]::ReadAllText($path) -cne $fixture) 'Existing patch removed.'
        $r = Invoke-RepairWorkflow -LauncherPath $path -Action Restore
        Assert ($r.Status -eq 'Restored') 'Restore failed.'
        $r = Invoke-RepairWorkflow -LauncherPath $path -ProxyUrl $proxy -Verifier { param($p) [IO.File]::AppendAllText($p,'// later edit'); throw 'failure after edit' }
        Assert ($r.Status -eq 'RollbackRefused') 'Later edits must prevent rollback.'
        Assert ([IO.File]::ReadAllText($path).Contains('// later edit')) 'Later edit lost.'
    } finally { $listener.Stop() }
    Write-Host 'PASS closed port, apply, verification rollback, existing patch protection, restore, concurrent edits'
} finally {
    $resolved = [IO.Path]::GetFullPath($root)
    if (-not $resolved.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'proxy-workflow-tests-*') { throw 'Unsafe cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
