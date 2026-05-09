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

$scriptPath = Join-Path $ProjectDir "run_on_wifi.py"
$configPath = Join-Path $ProjectDir "config.json"

if (-not (Test-Path $scriptPath)) {
    throw "run_on_wifi.py not found at $scriptPath"
}

if (-not (Test-Path $configPath)) {
    throw "config.json not found. Copy config.example.json to config.json and fill in your account first."
}

$principalUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$escapedUser = [Security.SecurityElement]::Escape($principalUser)
$escapedPythonExe = [Security.SecurityElement]::Escape($PythonExe)
$escapedArguments = [Security.SecurityElement]::Escape("`"$scriptPath`" --config `"$configPath`"")
$escapedProjectDir = [Security.SecurityElement]::Escape($ProjectDir)
$wlanSubscription = @"
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-WLAN-AutoConfig/Operational">
    <Select Path="Microsoft-Windows-WLAN-AutoConfig/Operational">*[System[(EventID=8001)]]</Select>
  </Query>
</QueryList>
"@
$wakeSubscription = @"
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and (EventID=1)]]</Select>
  </Query>
</QueryList>
"@
$escapedWlanSubscription = [Security.SecurityElement]::Escape($wlanSubscription)
$escapedWakeSubscription = [Security.SecurityElement]::Escape($wakeSubscription)

$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Auto-login to the campus network on Windows startup, Wi-Fi connection, wake, and unlock events.</Description>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>$escapedWlanSubscription</Subscription>
    </EventTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>$escapedWakeSubscription</Subscription>
    </EventTrigger>
    <SessionStateChangeTrigger>
      <Enabled>true</Enabled>
      <StateChange>SessionUnlock</StateChange>
      <UserId>$escapedUser</UserId>
    </SessionStateChangeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$escapedUser</UserId>
      <LogonType>S4U</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$escapedPythonExe</Command>
      <Arguments>$escapedArguments</Arguments>
      <WorkingDirectory>$escapedProjectDir</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

wevtutil sl Microsoft-Windows-WLAN-AutoConfig/Operational /e:true
Register-ScheduledTask -TaskName $TaskName -Xml $taskXml -Force

Write-Host "Scheduled task '$TaskName' installed."
Write-Host "Triggers: Windows startup, WLAN connection, wake from sleep, and session unlock."
Write-Host "The task runs run_on_wifi.py, which only submits login when the current SSID matches config.json target_ssids."
Write-Host "Security options: run whether the user is logged on or not, do not store password, run with highest available privileges."
