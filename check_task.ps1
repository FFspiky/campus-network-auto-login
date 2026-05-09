param(
    [string]$TaskName = "CampusNetworkAutoLogin",
    [string]$ProjectDir = $PSScriptRoot,
    [int]$LogTail = 30
)

$ErrorActionPreference = "Stop"

function Write-Field {
    param(
        [string]$Name,
        [object]$Value
    )
    Write-Host ("{0,-24} {1}" -f ($Name + ":"), $Value)
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "Task '$TaskName' was not found."
    Write-Host "Run install_task.ps1 from an elevated PowerShell first."
    exit 1
}

$taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
$startupTrigger = $task.Triggers | Where-Object { $_.CimClass.CimClassName -eq "MSFT_TaskBootTrigger" }
$eventTriggers = @($task.Triggers | Where-Object { $_.CimClass.CimClassName -eq "MSFT_TaskEventTrigger" })
$unlockTrigger = $task.Triggers | Where-Object { $_.CimClass.CimClassName -eq "MSFT_TaskSessionStateChangeTrigger" }
$wlanEventTrigger = $eventTriggers | Where-Object { $_.Subscription -like "*Microsoft-Windows-WLAN-AutoConfig/Operational*" }
$wakeEventTrigger = $eventTriggers | Where-Object { $_.Subscription -like "*Microsoft-Windows-Power-Troubleshooter*" }
$action = $task.Actions | Select-Object -First 1
$logPath = Join-Path $ProjectDir "campus_login.log"

Write-Host "Scheduled task"
Write-Host "--------------"
Write-Field "Name" $task.TaskName
Write-Field "State" $task.State
Write-Field "Startup trigger" ($(if ($startupTrigger) { "Yes" } else { "No" }))
Write-Field "WLAN event trigger" ($(if ($wlanEventTrigger) { "Yes" } else { "No" }))
Write-Field "Wake event trigger" ($(if ($wakeEventTrigger) { "Yes" } else { "No" }))
Write-Field "Unlock trigger" ($(if ($unlockTrigger) { "Yes" } else { "No" }))
Write-Field "Run as" $task.Principal.UserId
Write-Field "Logon type" $task.Principal.LogonType
Write-Field "Run level" $task.Principal.RunLevel
Write-Field "Execute" $action.Execute
Write-Field "Arguments" $action.Arguments
Write-Field "Working directory" $action.WorkingDirectory

Write-Host ""
Write-Host "Last run"
Write-Host "--------"
Write-Field "Last run time" $taskInfo.LastRunTime
Write-Field "Last task result" $taskInfo.LastTaskResult
Write-Field "Next run time" $taskInfo.NextRunTime
Write-Field "Missed runs" $taskInfo.NumberOfMissedRuns

Write-Host ""
Write-Host "Expected security options"
Write-Host "-------------------------"
Write-Field "Run whether logged on" ($(if ($task.Principal.LogonType -eq "S4U") { "Yes" } else { "No" }))
Write-Field "Do not store password" ($(if ($task.Principal.LogonType -eq "S4U") { "Yes" } else { "No" }))
Write-Field "Highest privileges" ($(if ($task.Principal.RunLevel -eq "Highest") { "Yes" } else { "No" }))

Write-Host ""
Write-Host "Project files"
Write-Host "-------------"
Write-Field "Project directory" $ProjectDir
Write-Field "run_on_wifi.py" (Test-Path (Join-Path $ProjectDir "run_on_wifi.py"))
Write-Field "campus_login.py" (Test-Path (Join-Path $ProjectDir "campus_login.py"))
Write-Field "config.json" (Test-Path (Join-Path $ProjectDir "config.json"))
Write-Field "Log file" (Test-Path $logPath)

if (Test-Path $logPath) {
    Write-Host ""
    Write-Host "Log tail"
    Write-Host "--------"
    Get-Content $logPath -Tail $LogTail
}
