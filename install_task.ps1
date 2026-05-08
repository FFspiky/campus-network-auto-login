param(
    [string]$TaskName = "CampusNetworkAutoLogin",
    [string]$ProjectDir = $PSScriptRoot,
    [string]$PythonExe = ""
)

$ErrorActionPreference = "Stop"

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsElevated)) {
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy Bypass",
        "-File `"$PSCommandPath`"",
        "-TaskName `"$TaskName`"",
        "-ProjectDir `"$ProjectDir`""
    )

    if ($PythonExe) {
        $arguments += "-PythonExe `"$PythonExe`""
    }

    Write-Host "Scheduled task installation requires Administrator permission."
    Write-Host "A Windows UAC prompt will open. Please approve it to continue."

    try {
        $process = Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList ($arguments -join " ") `
            -Verb RunAs `
            -Wait `
            -PassThru
    } catch {
        throw "Could not start elevated PowerShell: $($_.Exception.Message)"
    }

    exit $process.ExitCode
}

if (-not $PythonExe) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCommand) {
        $pythonCommand = Get-Command py -ErrorAction SilentlyContinue
    }
    if (-not $pythonCommand) {
        throw "Python was not found. Install Python 3 first, then rerun this script."
    }
    $PythonExe = $pythonCommand.Source
}

$scriptPath = Join-Path $ProjectDir "campus_login.py"
$configPath = Join-Path $ProjectDir "config.json"

if (-not (Test-Path $scriptPath)) {
    throw "campus_login.py not found at $scriptPath"
}

if (-not (Test-Path $configPath)) {
    throw "config.json not found. Copy config.example.json to config.json and fill in your account first."
}

$action = New-ScheduledTaskAction `
    -Execute $PythonExe `
    -Argument "`"$scriptPath`" --config `"$configPath`"" `
    -WorkingDirectory $ProjectDir

$trigger = New-ScheduledTaskTrigger -AtStartup
$principalUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal `
    -UserId $principalUser `
    -LogonType S4U `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Auto-login to the campus network during Windows startup." `
    -Force

Write-Host "Scheduled task '$TaskName' installed."
Write-Host "Security options: run whether the user is logged on or not, do not store password, run with highest privileges."
