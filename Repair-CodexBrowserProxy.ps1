#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Check','Apply','Restore')][string]$Action = 'Check',
    [string]$ProxyUrl,
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [string]$PluginVersion
)
$ErrorActionPreference = 'Stop'
try {
    if (-not $IsWindows) { throw 'This release supports Windows only.' }
    $module = Import-Module (Join-Path $PSScriptRoot 'src/ProxyFix.psm1') -Force -PassThru
    $launcher = Find-ProxyFixLauncher -CodexHome $CodexHome -PluginVersion $PluginVersion
    if ($Action -eq 'Apply') {
        $normalized = & $module { param($url) ConvertTo-LocalProxy $url } $ProxyUrl
        $uri = [uri]$normalized
        $client = [Net.Sockets.TcpClient]::new()
        try {
            $connect = $client.ConnectAsync([Net.IPAddress]::Parse($uri.Host.Trim('[', ']')), $uri.Port)
            if (-not $connect.Wait(2000) -or -not $client.Connected) { throw 'unreachable' }
        } catch { throw 'The selected local proxy port is not reachable. Start your proxy and confirm its HTTP port. No patch was applied.' }
        finally { $client.Dispose() }
    }
    $result = Invoke-ProxyFix -Action $Action -LauncherPath $launcher -ProxyUrl $ProxyUrl
    $result | Format-List
    if ($result.Status -eq 'Unsupported') {
        Write-Host 'Unsupported file or unrecognized prior patch. Check is read-only; do not force a change.'
        exit 2
    }
    if ($Action -eq 'Check') {
        Write-Host 'This checks local file compatibility only. It does not prove missing process proxy variables or browser recovery.'
    } elseif ($result.Changed) {
        Write-Host 'Restart Codex when your running tasks are finished, then test page open, read, click and back in both browsers.'
    }
} catch {
    # Do not dump configuration, invocation details, credentials or arbitrary input.
    Write-Host ('Error: ' + $_.Exception.Message)
    exit 1
}
