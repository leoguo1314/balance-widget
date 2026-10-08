#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$HapPath = '',
    [string]$DeviceId = '',
    [string]$HdcPath = 'D:\HarmonyosDevTools\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [string]$BundleName = 'com.leoguo.balancewidget'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$projectDir = Split-Path -Parent $PSScriptRoot
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$logDir = Join-Path (Join-Path $projectDir 'build-logs') ('device-' + $runStamp)
$null = New-Item -ItemType Directory -Path $logDir -Force
$resultPath = Join-Path $logDir 'result.json'
$rawLayoutPath = Join-Path $logDir '.layout-raw.json'
$layoutPath = Join-Path $logDir 'layout-evidence.json'
$screenPath = Join-Path $logDir 'application.png'
$remoteLayout = '/data/local/tmp/balance-widget-' + $runStamp + '.json'
$remoteScreen = '/data/local/tmp/balance-widget-' + $runStamp + '.png'
$script:result = [ordered]@{
    schemaVersion = 1
    startedAt = [DateTimeOffset]::Now.ToString('o')
    completedAt = $null
    status = 'running'
    bundleName = $BundleName
    toolVersion = $null
    device = [ordered]@{ apiVersion = $null; model = $null; systemVersion = $null }
    hap = $null
    installation = [ordered]@{ requested = [bool]$HapPath; status = 'not_requested'; successTextConfirmed = $false }
    launch = [ordered]@{ status = 'not_run'; successTextConfirmed = $false }
    installedBundleConfirmed = $false
    layout = $null
    screenshot = $null
    checks = @()
    failure = $null
}
$script:currentStep = 'initialization'
$script:selectedDevice = ''
$script:failureKind = 'validation'

function Invoke-Hdc {
    param([string]$Step, [string[]]$CommandArgs, [switch]$OnDevice)
    $script:currentStep = $Step
    $invokeArgs = @()
    if ($OnDevice) { $invokeArgs += @('-t', $script:selectedDevice) }
    $invokeArgs += $CommandArgs
    # Native stderr can become ErrorRecord objects under Windows PowerShell 5.1.
    # Keep all command output in memory; it can contain a device identifier.
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 0
    $outputLines = @(& $HdcPath @invokeArgs 2>&1 | ForEach-Object { $_.ToString() })
    $nativeExit = $global:LASTEXITCODE
    $outputText = $outputLines -join "`n"
    $hasFailure = $outputText -match '(?im)^\s*\[Fail\]|^\s*error\s*:|^\s*failure\s*:|\b(?:install|start)\s+(?:bundle\s+|ability\s+)?failed\b'
    $ok = ($nativeExit -eq 0 -and -not $hasFailure)
    $script:result.checks += [ordered]@{ step = $Step; nativeExitCode = $nativeExit; passed = $ok }
    if (-not $ok) {
        $script:failureKind = if ($nativeExit -ne 0) { 'native_exit' } else { 'device_reported_failure' }
        throw ('Device command failed during {0}; see the sanitized result.json.' -f $Step)
    }
    return $outputText
}

function Assert-SuccessText {
    param([string]$Output, [string]$Pattern, [string]$Step)
    if ($Output -notmatch $Pattern) {
        $script:currentStep = $Step
        $script:failureKind = 'success_text_missing'
        throw ('The device did not confirm success during {0}.' -f $Step)
    }
}

function Get-SafeDeviceValue {
    param([string]$Value, [int]$MaximumLength = 160)
    $clean = $Value.Trim()
    if ($script:selectedDevice) { $clean = $clean.Replace($script:selectedDevice, '[REDACTED]') }
    if (-not $clean -or $clean.Length -gt $MaximumLength -or $clean -notmatch '^[A-Za-z0-9 ._(),/+:\[\]-]+$') {
        throw 'The device returned an unexpected model or software version value.'
    }
    return $clean
}

function Get-LayoutEvidence {
    param([object]$Layout)
    # Preserve geometry and a small set of fixed application labels. Arbitrary
    # text, editable values, account names and credentials are never retained.
    $fixedLabels = @('API 余额', '余额', '历史', '设置', '添加', '全部刷新', '余额汇总 · 人民币', '余额历史', '刷新与折算', '桌面服务卡片', '数据与隐私')
    $nodes = New-Object System.Collections.Generic.List[object]
    $state = @{ TitleVisible = $false; MatchingBundleAttribute = $false; OtherBundleAttribute = $false }
    function Visit-LayoutNode {
        param([object]$Node, [int]$Depth)
        if ($null -eq $Node -or $Depth -gt 64) { return }
        if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string]) -and -not ($Node -is [pscustomobject])) {
            foreach ($item in $Node) { Visit-LayoutNode -Node $item -Depth ($Depth + 1) }
            return
        }
        if ($Node -isnot [pscustomobject]) { return }
        $attributes = $Node.PSObject.Properties['attributes']
        if ($attributes -and $attributes.Value -is [pscustomobject]) {
            $attrs = $attributes.Value
            $textProperty = $attrs.PSObject.Properties['text']
            $text = if ($textProperty) { [string]$textProperty.Value } else { '' }
            $visible = $true
            foreach ($visibleName in @('visibleToUser', 'visible')) {
                $visibleProperty = $attrs.PSObject.Properties[$visibleName]
                if ($visibleProperty -and [string]$visibleProperty.Value -match '^(false|0)$') { $visible = $false }
            }
            foreach ($bundleField in @('bundleName', 'bundle', 'bundle-name')) {
                $bundleProperty = $attrs.PSObject.Properties[$bundleField]
                if ($bundleProperty -and $bundleProperty.Value) {
                    if ([string]$bundleProperty.Value -eq $BundleName) { $state.MatchingBundleAttribute = $true }
                    else { $state.OtherBundleAttribute = $true }
                }
            }
            if ($text -eq 'API 余额' -and $visible) { $state.TitleVisible = $true }
            $typeProperty = $attrs.PSObject.Properties['type']
            $boundsProperty = $attrs.PSObject.Properties['bounds']
            $nodeType = if ($typeProperty -and [string]$typeProperty.Value -match '^[A-Za-z0-9_.:]+$') { [string]$typeProperty.Value } else { 'unknown' }
            $bounds = if ($boundsProperty -and [string]$boundsProperty.Value -match '^[\[\](), 0-9.:-]+$') { [string]$boundsProperty.Value } else { $null }
            $safeText = if ($fixedLabels -contains $text) { $text } elseif ($text) { '[REDACTED]' } else { '' }
            $nodes.Add([ordered]@{ type = $nodeType; bounds = $bounds; visible = $visible; text = $safeText })
        }
        foreach ($property in $Node.PSObject.Properties) {
            if ($property.Name -ne 'attributes') { Visit-LayoutNode -Node $property.Value -Depth ($Depth + 1) }
        }
    }
    Visit-LayoutNode -Node $Layout -Depth 0
    return [ordered]@{
        schemaVersion = 1
        bundleName = $BundleName
        bundleFilterRequested = $true
        matchingBundleAttribute = $state.MatchingBundleAttribute
        otherBundleAttribute = $state.OtherBundleAttribute
        applicationTitleVisible = $state.TitleVisible
        nodeCount = $nodes.Count
        nodes = @($nodes.ToArray())
    }
}

$exitCode = 1
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This script requires Windows.' }
    if ($BundleName -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$') { throw 'Invalid bundle name.' }
    if (-not (Test-Path -LiteralPath $HdcPath -PathType Leaf)) { throw 'hdc was not found at HdcPath.' }
    $HdcPath = (Resolve-Path -LiteralPath $HdcPath).Path
    $versionOutput = Invoke-Hdc -Step 'hdc_version' -CommandArgs @('-v')
    if ($versionOutput -match 'Ver:\s*([A-Za-z0-9.]+)') { $script:result.toolVersion = $matches[1] }
    $targetOutput = Invoke-Hdc -Step 'connected_targets' -CommandArgs @('list', 'targets', '-v')
    $connected = @($targetOutput -split "`r?`n" | ForEach-Object {
        if ($_ -match '^\s*(\S+)\s+(?:USB|TCP)\s+Connected\b') { $matches[1] }
    } | Select-Object -Unique)
    if ($DeviceId) {
        if ($connected -notcontains $DeviceId) { throw 'The specified device is not connected and authorized.' }
        $script:selectedDevice = $DeviceId
    } else {
        if ($connected.Count -ne 1) { throw 'Exactly one connected device is required; otherwise pass DeviceId.' }
        $script:selectedDevice = $connected[0]
    }

    $api = (Invoke-Hdc -Step 'device_api' -OnDevice -CommandArgs @('shell', 'param', 'get', 'const.ohos.apiversion')).Trim()
    $script:result.device.apiVersion = if ($api -match '^\d+(\.\d+)*$') { $api } else { $null }
    if ($api -notmatch '^26(?:\.0\.0)?$') { throw 'The connected device is not API 26.' }
    $model = Invoke-Hdc -Step 'device_model' -OnDevice -CommandArgs @('shell', 'param', 'get', 'const.product.model')
    $systemVersion = Invoke-Hdc -Step 'device_system_version' -OnDevice -CommandArgs @('shell', 'param', 'get', 'const.product.software.version')
    $script:result.device.model = Get-SafeDeviceValue -Value $model -MaximumLength 80
    $script:result.device.systemVersion = Get-SafeDeviceValue -Value $systemVersion

    if ($HapPath) {
        $script:currentStep = 'hap_validation'
        if (-not (Test-Path -LiteralPath $HapPath -PathType Leaf)) { throw 'HapPath does not exist.' }
        $hap = Get-Item -LiteralPath (Resolve-Path -LiteralPath $HapPath).Path
        if ($hap.Extension -ne '.hap' -or $hap.Length -le 0) { throw 'HapPath must be a nonempty .hap file.' }
        $script:result.hap = [ordered]@{ fileName = $hap.Name; bytes = $hap.Length; sha256 = (Get-FileHash -LiteralPath $hap.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
        $script:result.installation.status = 'attempted'
        $installOutput = Invoke-Hdc -Step 'install_hap' -OnDevice -CommandArgs @('install', '-r', $hap.FullName)
        Assert-SuccessText -Output $installOutput -Step 'install_hap' -Pattern '(?im)\binstall\s+bundle\s+successfully\b|\binstall(?:ation)?\s+succeeded\b|\binstall\s+success\b|\bsuccessfully\s+installed\b'
        $script:result.installation.status = 'passed'
        $script:result.installation.successTextConfirmed = $true
    }

    $bundleDump = Invoke-Hdc -Step 'installed_bundle' -OnDevice -CommandArgs @('shell', 'bm', 'dump', '-n', $BundleName)
    $bundlePattern = '"(?:bundleName|name)"\s*:\s*"' + [regex]::Escape($BundleName) + '"'
    if ($bundleDump -notmatch $bundlePattern) { throw 'Bundle Manager did not confirm the installed bundle.' }
    $script:result.installedBundleConfirmed = $true
    $script:result.launch.status = 'attempted'
    $startOutput = Invoke-Hdc -Step 'start_ability' -OnDevice -CommandArgs @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', $BundleName, '-m', 'entry')
    Assert-SuccessText -Output $startOutput -Step 'start_ability' -Pattern '(?im)\bstart\s+ability\s+successfully\b|\bstart\s+(?:ability\s+)?success\b'
    $script:result.launch.status = 'passed'
    $script:result.launch.successTextConfirmed = $true

    $evidence = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        Start-Sleep -Seconds 1
        $null = Invoke-Hdc -Step 'application_layout_dump' -OnDevice -CommandArgs @('shell', 'uitest', 'dumpLayout', '-p', $remoteLayout, '-b', $BundleName)
        $null = Invoke-Hdc -Step 'application_layout_receive' -OnDevice -CommandArgs @('file', 'recv', $remoteLayout, $rawLayoutPath)
        if (-not (Test-Path -LiteralPath $rawLayoutPath -PathType Leaf)) { throw 'The application layout was not received.' }
        $layoutObject = Get-Content -LiteralPath $rawLayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $evidence = Get-LayoutEvidence -Layout $layoutObject
        Remove-Item -LiteralPath $rawLayoutPath -Force
        if ($evidence.applicationTitleVisible -and $evidence.nodeCount -gt 0 -and -not $evidence.otherBundleAttribute) { break }
    }
    $script:currentStep = 'application_visible'
    $evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $layoutPath -Encoding UTF8
    $script:result.layout = [ordered]@{ file = 'layout-evidence.json'; nodeCount = $evidence.nodeCount; titleVisible = $evidence.applicationTitleVisible; bundleFilterRequested = $true; matchingBundleAttribute = $evidence.matchingBundleAttribute; otherBundleAttribute = $evidence.otherBundleAttribute }
    if (-not $evidence.applicationTitleVisible -or $evidence.nodeCount -eq 0 -or $evidence.otherBundleAttribute) {
        $script:failureKind = 'application_not_visible'
        throw 'The application UI is not visible; check device authorization, lock screen, permissions or app startup.'
    }

    $null = Invoke-Hdc -Step 'application_screenshot' -OnDevice -CommandArgs @('shell', 'uitest', 'screenCap', '-p', $remoteScreen)
    $null = Invoke-Hdc -Step 'application_screenshot_receive' -OnDevice -CommandArgs @('file', 'recv', $remoteScreen, $screenPath)
    $script:currentStep = 'screenshot_validation'
    if (-not (Test-Path -LiteralPath $screenPath -PathType Leaf)) { throw 'The application screenshot was not received.' }
    $screen = Get-Item -LiteralPath $screenPath
    $screenBytes = [IO.File]::ReadAllBytes($screenPath)
    if ($screenBytes.Length -le 8 -or [BitConverter]::ToString($screenBytes[0..7]) -ne '89-50-4E-47-0D-0A-1A-0A') { throw 'The received screenshot is not a PNG.' }
    $script:result.screenshot = [ordered]@{ file = 'application.png'; bytes = $screen.Length; sha256 = (Get-FileHash -LiteralPath $screenPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    $script:result.status = 'passed'
    $exitCode = 0
} catch {
    $script:result.status = 'failed'
    if ($script:result.installation.status -eq 'attempted') { $script:result.installation.status = 'failed' }
    if ($script:result.launch.status -eq 'attempted') { $script:result.launch.status = 'failed' }
    # Do not serialize Exception.Message or native output: either may disclose
    # an identifier, a signing path or text from a populated application.
    $script:result.failure = [ordered]@{ step = $script:currentStep; kind = $script:failureKind }
    Write-Host ('Device verification failed at {0} ({1}).' -f $script:currentStep, $script:failureKind)
} finally {
    if (Test-Path -LiteralPath $rawLayoutPath -PathType Leaf) { Remove-Item -LiteralPath $rawLayoutPath -Force }
    $script:result.completedAt = [DateTimeOffset]::Now.ToString('o')
    $script:result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    Write-Host ('Device verification: {0}. Result: {1}' -f $script:result.status, $resultPath)
}
exit $exitCode
