#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$StudioHome = 'D:\HarmonyosDevTools\DevEco Studio',
    [string]$CommandLineHome = 'D:\HarmonyosDevTools\command-line-tools',
    [string]$SdkHome = '',
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$projectDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $projectDir 'build-logs'
$null = New-Item -ItemType Directory -Path $logDir -Force
$logFile = Join-Path $logDir ('compile-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))

function Write-BuildLine {
    param([string]$Line)
    Write-Host $Line
    Add-Content -LiteralPath $logFile -Value $Line -Encoding UTF8
}

function Find-Tool {
    param([string[]]$Candidates, [string[]]$CommandNames)
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    foreach ($name in $CommandNames) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    return $null
}

function Invoke-BuildTool {
    param([string]$Name, [string]$Executable, [string[]]$ToolArgs)
    Write-BuildLine ("`n== {0} ==" -f $Name)
    # Windows PowerShell treats redirected native stderr as ErrorRecord objects.
    # Let the tool finish, then use its real exit code, including in a pipeline.
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 0
    & $Executable @ToolArgs 2>&1 | ForEach-Object { Write-BuildLine $_.ToString() }
    $toolExit = $global:LASTEXITCODE
    if ($toolExit -ne 0) { throw ("{0} failed with exit code {1}." -f $Name, $toolExit) }
}

$exitCode = 0
Push-Location -LiteralPath $projectDir
try {
    Write-BuildLine ('Project: ' + $projectDir)
    Write-BuildLine ('Log: ' + $logFile)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'Use this script on Windows; use build-hap.sh on Linux/macOS.'
    }

    $node = Find-Tool -Candidates @(
        (Join-Path $CommandLineHome 'tool\node\node.exe'),
        (Join-Path $CommandLineHome 'tools\node\node.exe'),
        (Join-Path $CommandLineHome 'node\node.exe'),
        (Join-Path $StudioHome 'tools\node\node.exe'),
        (Join-Path $StudioHome 'tools\node\bin\node.exe')
    ) -CommandNames @('node.exe')
    $hvigor = Find-Tool -Candidates @(
        $env:HVIGORW,
        (Join-Path $CommandLineHome 'bin\hvigorw.bat'),
        (Join-Path $CommandLineHome 'bin\hvigorw.cmd'),
        (Join-Path $StudioHome 'tools\hvigor\bin\hvigorw.bat'),
        (Join-Path $StudioHome 'tools\hvigor\bin\hvigorw.js')
    ) -CommandNames @('hvigorw.bat', 'hvigorw.cmd')
    $ohpm = Find-Tool -Candidates @(
        (Join-Path $CommandLineHome 'bin\ohpm.bat'),
        (Join-Path $CommandLineHome 'bin\ohpm.cmd'),
        (Join-Path $CommandLineHome 'ohpm\bin\ohpm.bat'),
        (Join-Path $StudioHome 'tools\ohpm\bin\ohpm.bat')
    ) -CommandNames @('ohpm.bat', 'ohpm.cmd')
    $java = Find-Tool -Candidates @(
        (Join-Path $StudioHome 'jbr\bin\java.exe'),
        (Join-Path $CommandLineHome 'tool\jdk\bin\java.exe'),
        (Join-Path $CommandLineHome 'tools\jdk\bin\java.exe'),
        (Join-Path $CommandLineHome 'jdk\bin\java.exe')
    ) -CommandNames @('java.exe')
    foreach ($tool in @(@('Node.js', $node), @('Hvigor', $hvigor), @('ohpm', $ohpm), @('Java', $java))) {
        if (-not $tool[1]) { throw ('Missing {0}. Check StudioHome/CommandLineHome or PATH.' -f $tool[0]) }
        Write-BuildLine ('{0}: {1}' -f $tool[0], $tool[1])
    }

    if (-not $SdkHome) { $SdkHome = $env:DEVECO_SDK_HOME }
    if (-not $SdkHome) {
        foreach ($candidate in @((Join-Path $CommandLineHome 'sdk'), (Join-Path $StudioHome 'sdk'))) {
            if (Test-Path -LiteralPath $candidate -PathType Container) { $SdkHome = $candidate; break }
        }
    }
    if (-not $SdkHome -or -not (Test-Path -LiteralPath $SdkHome -PathType Container)) {
        throw 'Missing HarmonyOS SDK. Pass -SdkHome with the SDK root from DevEco Studio settings.'
    }
    $env:DEVECO_SDK_HOME = (Resolve-Path -LiteralPath $SdkHome).Path
    $env:NODE_HOME = Split-Path -Parent $node
    $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $java)
    $env:DEVECO_COMMANDLINE_HOME = $CommandLineHome
    $env:PATH = (@((Split-Path -Parent $node), (Split-Path -Parent $java), (Split-Path -Parent $ohpm), (Split-Path -Parent $hvigor)) -join ';') + ';' + $env:PATH
    Write-BuildLine ('SDK: ' + $env:DEVECO_SDK_HOME)
    $nodeVersion = & $node --version
    if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v24\.') {
        throw ('HarmonyOS 26.0.0 requires its matching Node.js 24 toolchain; detected: ' + $nodeVersion)
    }
    Write-BuildLine ('Node version: ' + $nodeVersion)
    foreach ($relative in @('default\openharmony\ets\oh-uni-package.json', '26\ets\oh-uni-package.json', '26.0.0\ets\oh-uni-package.json')) {
        $metadata = Join-Path $env:DEVECO_SDK_HOME $relative
        if (Test-Path -LiteralPath $metadata -PathType Leaf) {
            $sdkPackage = Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json
            Write-BuildLine ('SDK ETS package: apiVersion={0}, version={1}' -f $sdkPackage.apiVersion, $sdkPackage.version)
            if ($sdkPackage.apiVersion -and [string]$sdkPackage.apiVersion -ne '26') {
                throw 'Detected SDK is not API 26. Select a HarmonyOS 26.0.0 SDK with -SdkHome.'
            }
            break
        }
    }

    $hvigorExe = $hvigor
    $hvigorPrefix = @()
    if ([IO.Path]::GetExtension($hvigor) -eq '.js') { $hvigorExe = $node; $hvigorPrefix = @($hvigor) }
    Invoke-BuildTool -Name 'Java version' -Executable $java -ToolArgs @('-version')
    Invoke-BuildTool -Name 'ohpm version' -Executable $ohpm -ToolArgs @('--version')
    Invoke-BuildTool -Name 'Hvigor version' -Executable $hvigorExe -ToolArgs ($hvigorPrefix + @('--version'))
    if ($CheckOnly) {
        Write-BuildLine 'Tool discovery finished. No SDK compilation was performed; Hvigor must still validate API 26.'
    } else {
        Invoke-BuildTool -Name 'Project references (unsigned source)' -Executable $node -ToolArgs @('tools/check-project.mjs')
        $testFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectDir 'tests') -Filter '*.test.mjs' -File | ForEach-Object { $_.FullName })
        Invoke-BuildTool -Name 'Business logic tests' -Executable $node -ToolArgs (@('--test') + $testFiles)
        Invoke-BuildTool -Name 'Install project dependencies' -Executable $ohpm -ToolArgs @('install')
        $buildStarted = [DateTime]::UtcNow
        Invoke-BuildTool -Name 'Native SDK assembleHap' -Executable $hvigorExe -ToolArgs ($hvigorPrefix + @('--mode', 'module', '-p', 'product=default', '-p', 'module=entry@default', '-p', 'buildMode=debug', 'assembleHap', '--no-daemon'))
        $outputDir = Join-Path $projectDir 'entry\build\default\outputs\default'
        $haps = @(Get-ChildItem -LiteralPath $outputDir -Filter '*.hap' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -ge $buildStarted.AddSeconds(-2) })
        if ($haps.Count -eq 0) { throw 'Hvigor returned success but no new HAP was found in entry/build/default/outputs/default.' }
        foreach ($hap in $haps) { Write-BuildLine ('Generated HAP: ' + $hap.FullName) }
        Write-BuildLine 'Native compilation completed. Device installation still requires matching debug signing and device validation.'
    }
} catch {
    $exitCode = 1
    Write-BuildLine ('BUILD FAILED: ' + $_.Exception.Message)
} finally {
    Pop-Location
    Write-BuildLine ('Build log: ' + $logFile)
}
exit $exitCode
