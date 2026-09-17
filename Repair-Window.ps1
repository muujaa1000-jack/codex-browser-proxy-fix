#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [switch]$SmokeTest
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows is required.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
Import-Module (Join-Path $PSScriptRoot 'src/ProxyFix.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src/RepairWorkflow.psm1') -Force
$script:SettingsPath = Join-Path $env:LOCALAPPDATA 'CodexBrowserProxyFix/settings.json'
$script:SavedProxy = Read-RepairSettings $script:SettingsPath
$script:LastResult = '尚未检查。工具只处理启动器缺少本机代理配置这一类问题。'
$script:Job = $null
$script:Result = $null
$script:HomePath = $CodexHome
$script:CodeRoot = $PSScriptRoot

$form = [Windows.Forms.Form]::new()
$form.Text = 'Codex 浏览器修复工具'
$form.ClientSize = [Drawing.Size]::new(690,480)
$form.MinimumSize = [Drawing.Size]::new(706,519)
$form.StartPosition = 'CenterScreen'
$form.Font = [Drawing.Font]::new('Microsoft YaHei UI',10)
$form.AutoScaleMode = 'Dpi'
$title = [Windows.Forms.Label]::new()
$title.Text = '检查并修复浏览器连接'
$title.Font = [Drawing.Font]::new('Microsoft YaHei UI',16,[Drawing.FontStyle]::Bold)
$title.SetBounds(24,20,640,40)
$hint = [Windows.Forms.Label]::new()
$hint.Text = '首次确认代理地址；保存成功后，下次双击将自动检查修复。'
$hint.SetBounds(24,66,640,28)
$versionLabel = [Windows.Forms.Label]::new(); $versionLabel.Text='插件版本'; $versionLabel.SetBounds(24,112,100,28)
$script:Versions = [Windows.Forms.ComboBox]::new()
$script:Versions.DropDownStyle='DropDownList'; $script:Versions.SetBounds(135,108,510,32)
$proxyLabel = [Windows.Forms.Label]::new(); $proxyLabel.Text='本机 HTTP 代理'; $proxyLabel.SetBounds(24,160,110,28)
$script:Proxy = [Windows.Forms.TextBox]::new(); $script:Proxy.SetBounds(135,156,510,32)
if ($script:SavedProxy) { $script:Proxy.Text=$script:SavedProxy } else {
    $suggestions=@(Get-RepairProxySuggestions)
    if ($suggestions.Count -eq 1) { $script:Proxy.Text=$suggestions[0] }
    $script:Proxy.PlaceholderText='例如 http://127.0.0.1:7890，请核对自己的 HTTP/混合端口'
}
$script:RepairButton=[Windows.Forms.Button]::new(); $script:RepairButton.Text='检查并修复'; $script:RepairButton.SetBounds(24,215,195,42)
$script:RestoreButton=[Windows.Forms.Button]::new(); $script:RestoreButton.Text='恢复原文件'; $script:RestoreButton.SetBounds(237,215,195,42)
$detailsButton=[Windows.Forms.Button]::new(); $detailsButton.Text='查看结果'; $detailsButton.SetBounds(450,215,195,42)
$script:Status=[Windows.Forms.TextBox]::new()
$script:Status.Multiline=$true; $script:Status.ReadOnly=$true; $script:Status.ScrollBars='Vertical'
$script:Status.SetBounds(24,280,621,125); $script:Status.Text=$script:LastResult
$footer=[Windows.Forms.Label]::new(); $footer.Text='不关闭 Codex 或 Chrome。未知文件停止修改；没有上传或遥测。'; $footer.SetBounds(24,426,640,30)
$form.Controls.AddRange(@($title,$hint,$versionLabel,$script:Versions,$proxyLabel,$script:Proxy,$script:RepairButton,$script:RestoreButton,$detailsButton,$script:Status,$footer))
try {
    $candidates=@(Get-ProxyFixVersions $CodexHome)
    foreach ($candidate in $candidates) { $script:Versions.Items.Add($candidate) | Out-Null }
    if ($candidates.Count -eq 1) { $script:Versions.SelectedIndex=0 }
    elseif ($candidates.Count -gt 1) { $script:Status.Text='发现多个缓存版本。请先在 Codex 确认当前版本，再在上方选择；不会自动猜测。' }
    else { $script:Status.Text='没有找到插件配置。请至少打开一次 Codex，再重新打开本工具。' }
} catch { $script:Status.Text='没有找到可用的插件配置。请打开 Codex 后重试。自定义安装请参阅教程。' }

# Kept separate so the background job can be tested without clicking the UI.
$script:Worker = {
    param($root,$homePath,$version,$proxy,$action)
    $ErrorActionPreference='Stop'
    Import-Module (Join-Path $root 'src/ProxyFix.psm1') -Force
    Import-Module (Join-Path $root 'src/RepairWorkflow.psm1') -Force
    $launcher=Find-ProxyFixLauncher -CodexHome $homePath -PluginVersion $version
    Invoke-RepairWorkflow -LauncherPath $launcher -ProxyUrl $proxy -Action $action
}
$script:Timer=[Windows.Forms.Timer]::new(); $script:Timer.Interval=150
function Start-RepairJob([string]$Action) {
    if ($null -ne $script:Job) { return }
    if ($script:Versions.SelectedIndex -lt 0) { $script:Status.Text='请先选择已确认的当前插件版本。'; return }
    $script:PendingProxy=$script:Proxy.Text.Trim()
    $script:PendingAction=$Action
    $script:RepairButton.Enabled=$false; $script:RestoreButton.Enabled=$false
    $script:Versions.Enabled=$false; $script:Proxy.Enabled=$false
    $script:Status.Text='正在检查文件、备份和启动状态，请稍候……'
    $script:Job=[PowerShell]::Create()
    $null=$script:Job.AddScript($script:Worker.ToString()).AddArgument($script:CodeRoot).AddArgument($script:HomePath).AddArgument([string]$script:Versions.SelectedItem).AddArgument($script:PendingProxy).AddArgument($Action)
    $script:Result=$script:Job.BeginInvoke()
    $script:Timer.Start()
}
$script:Timer.Add_Tick({
    if ($null -eq $script:Job -or -not $script:Result.IsCompleted) { return }
    $script:Timer.Stop()
    try {
        $output=$script:Job.EndInvoke($script:Result)
        if ($script:Job.HadErrors) { throw ($script:Job.Streams.Error | Select-Object -First 1) }
        $r=$output | Select-Object -Last 1
        $message=switch ($r.Status) {
            'Applied' { '补丁已应用。完成当前任务后，请完全退出并重启 Codex，再复测网页。' }
            'AlreadyPatched' { '补丁已存在，无需重复修补。如果尚未重启过 Codex，请完成任务后重启，再复测网页。' }
            'Restored' { '已恢复原文件，备份仍保留。请完成当前任务后重启 Codex。' }
            'AlreadyOriginal' { '文件已经是原始状态，无需恢复。' }
            'RolledBack' { '启动验证未通过，已撤回本次修改并恢复原文件。请查看结果，勿反复修补。' }
            'RollbackRefused' { '验证失败，且文件已变化，无法安全恢复。已保留备份，请进一步排查。' }
            'VerificationFailed' { '已有补丁的启动验证失败。为保留原有修正，本次未恢复或修改它。' }
            default { "检查结果：$($r.Status)" }
        }
        if ($r.Status -in @('Applied','AlreadyPatched')) {
            $message += if ($r.Validation -eq 'StartupPassed') { "`r`n工具启动验证通过；尚未验证实际网页操作。" } else { "`r`n仅验证文件状态；旧版启动器仍需重启后手动复测。" }
            try { Save-RepairSettings $script:SettingsPath $script:PendingProxy } catch { $message += "`r`n代理地址未能保存，下次需要重新填写。" }
        }
        $script:LastResult=$message + "`r`n`r`n" + ($r | ConvertTo-Json -Depth 3)
        $script:Status.Text=$message
    } catch {
        $script:LastResult="操作未完成，请核对插件版本、代理端口或文件兼容性。`r`n`r`n" + $_.Exception.Message
        $script:Status.Text=$script:LastResult
    } finally {
        $script:Job.Dispose(); $script:Job=$null; $script:Result=$null
        $script:RepairButton.Enabled=$true; $script:RestoreButton.Enabled=$true
        $script:Versions.Enabled=$true; $script:Proxy.Enabled=$true
    }
})
$script:RepairButton.Add_Click({ Start-RepairJob 'Apply' })
$script:RestoreButton.Add_Click({ Start-RepairJob 'Restore' })
$detailsButton.Add_Click({ [Windows.Forms.MessageBox]::Show($script:LastResult,'本机检查结果') | Out-Null })
$form.Add_FormClosing({ param($sender,$eventArgs) if ($null -ne $script:Job) { $eventArgs.Cancel=$true; $script:Status.Text='检查仍在进行，请等待结束后关闭窗口。' } })
$form.Add_Shown({ if ($script:SavedProxy -and $script:Versions.Items.Count -eq 1) { Start-RepairJob 'Apply' } })
try {
    if ($SmokeTest) {
        # Construction and the same asynchronous worker, read-only; no UI interaction.
        $probe=[PowerShell]::Create()
        try {
            $null=$probe.AddScript($script:Worker.ToString()).AddArgument($script:CodeRoot).AddArgument($script:HomePath).AddArgument([string]$script:Versions.SelectedItem).AddArgument('').AddArgument('Check')
            $pending=$probe.BeginInvoke()
            if (-not $pending.AsyncWaitHandle.WaitOne(10000)) { throw 'Worker smoke check timed out.' }
            $items=$probe.EndInvoke($pending)
            if ($probe.HadErrors) { throw 'Worker smoke check failed.' }
            [pscustomobject]@{Controls=$form.Controls.Count; WorkerStatus=($items | Select-Object -Last 1).Status; Visible=$form.Visible} | ConvertTo-Json
        } finally { $probe.Dispose() }
    } else { [Windows.Forms.Application]::Run($form) }
} finally { $script:Timer.Dispose(); $form.Dispose() }
