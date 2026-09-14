#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:OriginalHash = 'a50b66879f7b72e45ab6fbaad77eff14a87680a946135f410c121b9b166a2597'
$script:SupportedVersion = '26.903.71938'
$script:RuntimeVersion = '26.908.40834'
$script:RuntimeHash = '992174a5e637645aeb444adfdb1bae688e997bb84d7db07532f68e358e60f278'
$script:BackupSuffix = '.codex-browser-proxy-fix.original.bak'

function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-LocalRegularPath([string]$Path) {
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw 'An absolute local path is required.' }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('\\')) { throw 'Network and device paths are not supported.' }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked or redirected paths are not supported.' }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}

function ConvertTo-LocalProxy([string]$ProxyUrl) {
    # Restrict to literal loopback addresses; never resolve an external hostname.
    if ($ProxyUrl -cnotmatch '^http://(127\.0\.0\.1|\[::1\]):([0-9]{1,5})/?$') {
        throw 'Use an HTTP proxy on 127.0.0.1 or [::1], with an explicit port and no credentials or extra URL components.'
    }
    $port = [int]$Matches[2]
    if ($port -lt 1 -or $port -gt 65535) { throw 'Proxy port must be between 1 and 65535.' }
    return "http://$($Matches[1]):$port"
}

function New-PatchedBytes([byte[]]$Original, [string]$Proxy) {
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    $text = $encoding.GetString($Original)
    if ((Get-BytesHash $Original) -eq $script:RuntimeHash) {
        $anchor = 'try {'
        if ([regex]::Matches($text, [regex]::Escape($anchor)).Count -ne 1) { throw 'The runtime launch anchor is not unique.' }
        $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
        $literal = ConvertTo-Json -InputObject $Proxy -Compress
        $lines = @(
            '// codex-browser-proxy-fix:v2 start'
            "process.env.HTTP_PROXY ||= $literal;"
            "process.env.HTTPS_PROXY ||= $literal;"
            "process.env.ALL_PROXY ||= $literal;"
            'process.env.NO_PROXY ||= "localhost,127.0.0.1,::1";'
            '// codex-browser-proxy-fix:v2 end'
            ''
            $anchor
        )
        return ,$encoding.GetBytes($text.Replace($anchor, ($lines -join $newline)))
    }
    $anchor = '      ...process.env,'
    if ([regex]::Matches($text, [regex]::Escape($anchor)).Count -ne 1) { throw 'The supported environment anchor is not unique.' }
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $literal = ConvertTo-Json -InputObject $Proxy -Compress
    $lines = @(
        $anchor
        '      // codex-browser-proxy-fix:v1 start'
        "      HTTP_PROXY: process.env.HTTP_PROXY || $literal,"
        "      HTTPS_PROXY: process.env.HTTPS_PROXY || $literal,"
        "      ALL_PROXY: process.env.ALL_PROXY || $literal,"
        '      NO_PROXY: process.env.NO_PROXY || "localhost,127.0.0.1,::1",'
        '      // codex-browser-proxy-fix:v1 end'
    )
    return ,$encoding.GetBytes($text.Replace($anchor, ($lines -join $newline)))
}

function Read-Launcher([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { throw 'The launcher file is missing.' }
    if ((Get-Item -LiteralPath $Path).Length -gt 1MB) { throw 'Unexpected launcher size; refusing to read it.' }
    return ,[IO.File]::ReadAllBytes($Path)
}

function Get-LauncherState([string]$Path) {
    $bytes = Read-Launcher $Path
    $hash = Get-BytesHash $bytes
    if ($hash -in @($script:OriginalHash, $script:RuntimeHash)) {
        return @{Status='Compatible'; Bytes=$bytes; Hash=$hash; Proxy=$null}
    }
    $backup = "$Path$script:BackupSuffix"
    if ([IO.File]::Exists($backup)) {
        Assert-LocalRegularPath $backup | Out-Null
        $original = Read-Launcher $backup
        if ((Get-BytesHash $original) -in @($script:OriginalHash, $script:RuntimeHash)) {
            $text = [Text.Encoding]::UTF8.GetString($bytes)
            $pattern = 'HTTP_PROXY: process\.env\.HTTP_PROXY \|\| "(http://(?:127\.0\.0\.1|\[::1\]):[0-9]{1,5})",'
            if ((Get-BytesHash $original) -eq $script:RuntimeHash) { $pattern = 'process\.env\.HTTP_PROXY \|\|= "(http://(?:127\.0\.0\.1|\[::1\]):[0-9]{1,5})";' }
            $match = [regex]::Match($text, $pattern)
            if ($match.Success) {
                $proxy = ConvertTo-LocalProxy $match.Groups[1].Value
                if ((Get-BytesHash (New-PatchedBytes $original $proxy)) -eq $hash) {
                    return @{Status='Patched'; Bytes=$bytes; Hash=$hash; Proxy=$proxy}
                }
            }
        }
    }
    return @{Status='Unsupported'; Bytes=$bytes; Hash=$hash; Proxy=$null}
}

function Write-ExclusiveBytes([string]$Path, [byte[]]$Bytes) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}

function Write-AtomicLauncher([string]$Path, [byte[]]$Bytes, [string]$ExpectedCurrentHash) {
    $temporary = "$Path.proxy-fix-$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Write-ExclusiveBytes $temporary $Bytes
        Assert-LocalRegularPath $Path | Out-Null
        if ((Get-BytesHash (Read-Launcher $Path)) -ne $ExpectedCurrentHash) { throw 'Launcher changed during the operation. Nothing was replaced.' }
        [IO.File]::Replace($temporary, $Path, [NullString]::Value)
        if ((Get-BytesHash (Read-Launcher $Path)) -ne (Get-BytesHash $Bytes)) { throw 'Post-write verification failed. Preserve the backup and inspect locally.' }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Invoke-ProxyFix {
    param(
        [ValidateSet('Check','Apply','Restore')][string]$Action = 'Check',
        [Parameter(Mandatory)][string]$LauncherPath,
        [string]$ProxyUrl
    )
    $path = Assert-LocalRegularPath $LauncherPath
    $state = Get-LauncherState $path
    if ($Action -eq 'Check') {
        return [pscustomobject]@{Status=$state.Status; Changed=$false; SHA256=$state.Hash}
    }
    if ($state.Status -eq 'Unsupported') { throw 'Unsupported or edited launcher/backup. No changes made. Do not force a patch.' }
    $backup = Assert-LocalRegularPath "$path$script:BackupSuffix"
    if ($Action -eq 'Apply') {
        $proxy = ConvertTo-LocalProxy $ProxyUrl
        if ($state.Status -eq 'Patched') {
            if ($proxy -ne $state.Proxy) { throw 'A different proxy is already patched. Restore first, then apply the new address.' }
            return [pscustomobject]@{Status='AlreadyPatched'; Changed=$false}
        }
        # Compute before creating the backup, so transformation errors cause no writes.
        $patched = New-PatchedBytes $state.Bytes $proxy
        if ([IO.File]::Exists($backup)) {
            if ((Get-BytesHash (Read-Launcher $backup)) -ne $state.Hash) { throw 'Existing backup does not match the verified original. It was not overwritten.' }
        } else {
            Write-ExclusiveBytes $backup $state.Bytes
        }
        Write-AtomicLauncher $path $patched $state.Hash
        return [pscustomobject]@{Status='Applied'; Changed=$true}
    }
    if ($state.Status -eq 'Compatible') { return [pscustomobject]@{Status='AlreadyOriginal'; Changed=$false} }
    $original = Read-Launcher $backup
    if ((Get-BytesHash $original) -notin @($script:OriginalHash, $script:RuntimeHash)) { throw 'Backup changed. Restore refused.' }
    Write-AtomicLauncher $path $original $state.Hash
    return [pscustomobject]@{Status='Restored'; Changed=$true}
}

function Find-ProxyFixLauncher {
    param([Parameter(Mandatory)][string]$CodexHome, [string]$PluginVersion,
        [string]$RuntimeRoot = (Join-Path $env:LOCALAPPDATA 'OpenAI/Codex/runtimes/cua_node'))
    $homePath = Assert-LocalRegularPath $CodexHome
    $cache = Assert-LocalRegularPath (Join-Path $homePath 'plugins/cache/openai-bundled/unified-computer-use')
    if (-not [IO.Directory]::Exists($cache)) { throw 'The unified-computer-use plugin cache was not found in this Codex home.' }
    if ($PluginVersion) {
        if ($PluginVersion -notin @($script:SupportedVersion, $script:RuntimeVersion)) { throw 'This plugin version is unsupported.' }
        $versions = @(Get-Item -LiteralPath (Join-Path $cache $PluginVersion) -ErrorAction Stop)
    } else {
        $versions = @(Get-ChildItem -LiteralPath $cache -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.mcp.json') })
        if ($versions.Count -ne 1) { throw 'No unique plugin candidate. Confirm the active version in Codex, then use -PluginVersion explicitly.' }
    }
    if ($versions[0].Name -notin @($script:SupportedVersion, $script:RuntimeVersion)) { throw 'The installed plugin version is unsupported; no files changed.' }
    $base = $versions[0].FullName
    $isRuntime = $versions[0].Name -eq $script:RuntimeVersion
    $launcher = if ($isRuntime) {
        Assert-LocalRegularPath (Join-Path $RuntimeRoot 'a708e72b10c27b59/bin/node_modules/@oai/cua-repl/bin/cua-repl.mjs')
    } else { Assert-LocalRegularPath (Join-Path $base 'scripts/launch.mjs') }
    $manifestPath = Assert-LocalRegularPath (Join-Path $base '.mcp.json')
    try {
        $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -AsHashtable
        $server = $manifest['mcpServers']['cua_repl']
        $arguments = @($server['args'])
        if ($arguments.Count -ne 1 -or -not [IO.Path]::IsPathFullyQualified($arguments[0]) -or [IO.Path]::GetFullPath($arguments[0]) -ne $launcher) { throw 'mismatch' }
        if ($isRuntime) {
            $expectedNode = Assert-LocalRegularPath (Join-Path $RuntimeRoot 'a708e72b10c27b59/bin/node.exe')
            if (-not $server.ContainsKey('command') -or -not [IO.Path]::IsPathFullyQualified($server['command']) -or [IO.Path]::GetFullPath($server['command']) -ne $expectedNode) { throw 'runtime command mismatch' }
        }
        if ($server.ContainsKey('enabled') -and $server['enabled'] -eq $false) { throw 'disabled' }
    } catch { throw 'The generated MCP manifest is missing, disabled, or does not reference this launcher. Open Codex once to regenerate it, then check again.' }
    return $launcher
}

Export-ModuleMember -Function Invoke-ProxyFix, Find-ProxyFixLauncher
