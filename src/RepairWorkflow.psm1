#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Core = Import-Module (Join-Path $PSScriptRoot 'ProxyFix.psm1') -PassThru

function Read-RepairSettings([string]$Path) {
    try {
        $safe = & $script:Core { param($p) Assert-LocalRegularPath $p } $Path
        if (-not [IO.File]::Exists($safe)) { return $null }
        if ((Get-Item -LiteralPath $safe).Length -gt 4096) { return $null }
        $data = [IO.File]::ReadAllText($safe) | ConvertFrom-Json
        return & $script:Core { param($s) ConvertTo-LocalProxy $s } $data.ProxyUrl
    } catch { return $null }
}

function Save-RepairSettings([string]$Path, [string]$ProxyUrl) {
    $proxy = & $script:Core { param($s) ConvertTo-LocalProxy $s } $ProxyUrl
    $safe = & $script:Core { param($p) Assert-LocalRegularPath $p } $Path
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($safe)) | Out-Null
    [IO.File]::WriteAllText($safe, (@{ProxyUrl=$proxy} | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}

function Get-RepairProxySuggestions {
    # Suggestions only: no scanning ports or reading proxy-account configuration.
    $values = @($env:HTTP_PROXY,$env:HTTPS_PROXY,$env:ALL_PROXY)
    $valid = foreach ($v in $values) {
        try { & $script:Core { param($s) ConvertTo-LocalProxy $s } $v } catch { }
    }
    $valid | Select-Object -Unique
}

function Test-RepairProxy([string]$ProxyUrl) {
    $proxy = & $script:Core { param($s) ConvertTo-LocalProxy $s } $ProxyUrl
    $uri = [uri]$proxy
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync([Net.IPAddress]::Parse($uri.Host.Trim('[',']')),$uri.Port)
        if (-not $task.Wait(2000) -or -not $client.Connected) { throw 'closed' }
    } catch { throw 'Local proxy port is unavailable. Start the proxy and confirm its HTTP/mixed port.' }
    finally { $client.Dispose() }
    return $proxy
}

function Test-RepairStartup([string]$LauncherPath) {
    if ((Split-Path $LauncherPath -Leaf) -ne 'cua-repl.mjs') { return 'LegacyFileOnly' }
    $bin = [IO.Path]::GetFullPath((Join-Path (Split-Path $LauncherPath -Parent) '../../../..'))
    $node = & $script:Core { param($p) Assert-LocalRegularPath $p } (Join-Path $bin 'node.exe')
    if (-not [IO.File]::Exists($node)) { throw 'Runtime Node executable is missing.' }
    $runtime = & $script:Core { param($p) Assert-LocalRegularPath $p } (Join-Path $bin 'node_repl.exe')
    if (-not [IO.File]::Exists($runtime)) { throw 'Browser tool executable is missing.' }
    # Probe starts only this verified local launcher; it does not operate browsers.
    $info = [Diagnostics.ProcessStartInfo]::new($node)
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $info.ArgumentList.Add((Join-Path $PSScriptRoot 'startup-probe.mjs'))
    $info.ArgumentList.Add($LauncherPath)
    $process = [Diagnostics.Process]::new(); $process.StartInfo=$info
    try {
        if (-not $process.Start()) { throw 'Could not start verification.' }
        $output=$process.StandardOutput.ReadToEndAsync(); $errors=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(25000)) { $process.Kill($true); throw 'Startup verification timed out.' }
        if ($process.ExitCode -ne 0) { throw 'Startup verification failed. No browser recovery is claimed.' }
        $result=$output.GetAwaiter().GetResult() | ConvertFrom-Json
        if (-not $result.initialized -or -not $result.cleanShutdown) { throw 'Incomplete startup verification.' }
        return 'StartupPassed'
    } finally { $process.Dispose() }
}

function Invoke-RepairWorkflow {
    param([Parameter(Mandatory)][string]$LauncherPath,
        [ValidateSet('Apply','Restore','Check')][string]$Action='Apply', [string]$ProxyUrl,
        [scriptblock]$Verifier = { param($p) Test-RepairStartup $p })
    if ($Action -ne 'Apply') { return Invoke-ProxyFix $Action $LauncherPath }
    $state = Invoke-ProxyFix Check $LauncherPath
    if ($state.Status -eq 'Unsupported') { throw 'Unknown or edited launcher/backup. No changes made.' }
    $proxy = Test-RepairProxy $ProxyUrl
    $result = Invoke-ProxyFix Apply $LauncherPath $proxy
    $appliedHash = (Get-FileHash -LiteralPath $LauncherPath -Algorithm SHA256).Hash
    try {
        $validation = & $Verifier $LauncherPath
        return [pscustomobject]@{Status=$result.Status; Changed=$result.Changed; Validation=$validation; RestartRequired=$true}
    } catch {
        if (-not $result.Changed) { return [pscustomobject]@{Status='VerificationFailed'; Changed=$false} }
        try {
            if ((Get-FileHash -LiteralPath $LauncherPath -Algorithm SHA256).Hash -ne $appliedHash) { throw 'File changed after Apply.' }
            Invoke-ProxyFix Restore $LauncherPath | Out-Null
            return [pscustomobject]@{Status='RolledBack'; Changed=$false}
        } catch { return [pscustomobject]@{Status='RollbackRefused'; Changed=$true} }
    }
}

Export-ModuleMember -Function Read-RepairSettings, Save-RepairSettings, Get-RepairProxySuggestions, Invoke-RepairWorkflow
