param(
    [string]$TaskName = "CampusNetworkAutoLogin",
    [string]$ProjectDir = $PSScriptRoot,
    [string]$PythonExe = ""
)

$ErrorActionPreference = "Stop"

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
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Auto-login to the campus network during Windows startup." `
    -User $env:USERNAME `
    -RunLevel Highest `
    -Force

Write-Host "Scheduled task '$TaskName' installed."
Write-Host "Open Task Scheduler and enable 'Run whether user is logged on or not' if Windows did not prompt for it."
