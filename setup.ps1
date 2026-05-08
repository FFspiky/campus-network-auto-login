param(
    [string]$ProjectDir = $PSScriptRoot,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Ask-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )

    $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $answer = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }
        switch ($answer.Trim().ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
            default { Write-Host "Please enter y or n." }
        }
    }
}

function Read-Required {
    param([string]$Prompt)

    while ($true) {
        $value = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
        Write-Host "This value is required."
    }
}

function Read-PasswordText {
    param([string]$Prompt)

    while ($true) {
        $secure = Read-Host $Prompt -AsSecureString
        if ($secure.Length -gt 0) {
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try {
                return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            } finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
        Write-Host "This value is required."
    }
}

function Select-ServiceValue {
    $services = @(
        @{ Label = "China Mobile"; Value = "cmcc" },
        @{ Label = "Campus network"; Value = "default" },
        @{ Label = "Campus intranet"; Value = "local" },
        @{ Label = "China Unicom"; Value = "unicom" },
        @{ Label = "China Telecom"; Value = "ctcc" }
    )

    Write-Host ""
    Write-Host "Select service:"
    for ($i = 0; $i -lt $services.Count; $i++) {
        Write-Host ("{0}. {1} ({2})" -f ($i + 1), $services[$i].Label, $services[$i].Value)
    }
    Write-Host "6. Custom"

    while ($true) {
        $choice = Read-Host "Service [1]"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return $services[0].Value
        }
        if ($choice -match '^[1-5]$') {
            return $services[[int]$choice - 1].Value
        }
        if ($choice -eq "6") {
            return Read-Required "Custom service value"
        }
        Write-Host "Please enter 1-6."
    }
}

function Get-PythonCommand {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return $python.Source
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        return $py.Source
    }

    return $null
}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-StartupTaskElevated {
    param(
        [string]$InstallScriptPath,
        [string]$ProjectDir,
        [string]$PythonExe
    )

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy Bypass",
        "-File `"$InstallScriptPath`"",
        "-ProjectDir `"$ProjectDir`"",
        "-PythonExe `"$PythonExe`""
    ) -join " "

    Write-Host "Startup task installation requires Administrator permission."
    Write-Host "A Windows UAC prompt will open. Please approve it to install the scheduled task."

    try {
        $process = Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList $arguments `
            -Verb RunAs `
            -Wait `
            -PassThru
    } catch {
        Write-Host "Could not start elevated PowerShell: $($_.Exception.Message)"
        Write-Host "Open PowerShell as Administrator and run:"
        Write-Host "  Set-ExecutionPolicy -Scope Process Bypass"
        Write-Host "  .\install_task.ps1"
        return $false
    }

    if ($process.ExitCode -ne 0) {
        Write-Host "Elevated startup task installation exited with code $($process.ExitCode)."
        Write-Host "Open PowerShell as Administrator and run:"
        Write-Host "  Set-ExecutionPolicy -Scope Process Bypass"
        Write-Host "  .\install_task.ps1"
        return $false
    }

    Write-Host "Startup task installation finished."
    return $true
}

$configTemplatePath = Join-Path $ProjectDir "config.example.json"
$configPath = Join-Path $ProjectDir "config.json"
$requirementsPath = Join-Path $ProjectDir "requirements.txt"
$loginScriptPath = Join-Path $ProjectDir "campus_login.py"
$installScriptPath = Join-Path $ProjectDir "install_task.ps1"

Write-Host "Campus network auto login setup"
Write-Host "Project directory: $ProjectDir"
Write-Host ""

$pythonExe = Get-PythonCommand
if (-not $pythonExe) {
    throw "Python was not found. Install Python 3 first, then rerun setup.ps1."
}
Write-Host "Python: $pythonExe"

if (Ask-YesNo "Install Python dependencies now?" $true) {
    & $pythonExe -m pip install -r $requirementsPath
    if ($LASTEXITCODE -ne 0) {
        throw "Dependency installation failed."
    }
}

if ((Test-Path $configPath) -and -not $Force) {
    if (-not (Ask-YesNo "config.json already exists. Overwrite it?" $false)) {
        Write-Host "Keeping existing config.json."
    } else {
        Copy-Item $configTemplatePath $configPath -Force
    }
} else {
    Copy-Item $configTemplatePath $configPath -Force
}

$config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$config.username = Read-Required "Campus network username"
$config.password = Read-PasswordText "Campus network password"
$config.service = Select-ServiceValue

$config |
    ConvertTo-Json -Depth 20 |
    Set-Content -Path $configPath -Encoding UTF8

Write-Host ""
Write-Host "config.json updated. Password is stored in plain text locally; do not commit this file."

if (Ask-YesNo "Run a manual login test now?" $true) {
    & $pythonExe $loginScriptPath --config $configPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Manual test failed. Check campus_login.log before installing the startup task."
    }
}

$startupTaskInstalled = $false
if (Ask-YesNo "Install or update the Windows startup task?" $true) {
    if (-not (Test-IsElevated)) {
        $startupTaskInstalled = Install-StartupTaskElevated `
            -InstallScriptPath $installScriptPath `
            -ProjectDir $ProjectDir `
            -PythonExe $pythonExe
    } else {
        & $installScriptPath -ProjectDir $ProjectDir -PythonExe $pythonExe
        if ($LASTEXITCODE -ne 0) {
            throw "Startup task installation failed."
        }
        $startupTaskInstalled = $true
    }
}

Write-Host ""
Write-Host "Setup complete."
if ($startupTaskInstalled) {
    Write-Host "You can check the task with:"
    Write-Host "  .\check_task.ps1"
} else {
    Write-Host "If the startup task was not installed, open PowerShell as Administrator and run:"
    Write-Host "  Set-ExecutionPolicy -Scope Process Bypass"
    Write-Host "  .\install_task.ps1"
}
