<# 
Purpose:
- Configure WSUS policy (choosing reachable WSUS URL)
- Search / download / install Windows Updates (software, not hidden, not installed)
- ALWAYS reboot at the end if any updates were installed (invariable reboot requirement)
- Write progress + results to a log file
- Update HKLM:\SOFTWARE\Barclays\Windows\Temp\Patching for external coordination

Notes:
- Run elevated (admin).
- Uses Windows Update COM objects (Microsoft.Update.Session).
#>

$ErrorActionPreference = "Stop"

# -----------------------------
# Registry key used by packer / orchestration
# -----------------------------
$TempRegPath = "HKLM:\SOFTWARE\Barclays\Windows\Temp"

# Ensure base registry path exists
if (!(Test-Path $TempRegPath)) {
    New-Item -Path "HKLM:\SOFTWARE\Barclays\Windows" -Name "Temp" -Force | Out-Null
}

# -----------------------------
# Logging
# -----------------------------
$Global:LogFolder = Join-Path -Path $env:SystemRoot -ChildPath "Platform\Logs"
$Global:LogFile   = Join-Path -Path $Global:LogFolder -ChildPath "Patching.log"

if (!(Test-Path $Global:LogFolder)) {
    New-Item -Path $Global:LogFolder -ItemType Directory -Force | Out-Null
}

Function Logging {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$ErrorLevel = "INFO"
    )

    $line = "$(Get-Date) `t $ErrorLevel `t $Message"
    $line | Out-File -Append -FilePath $Global:LogFile -Encoding UTF8
    Write-Host $line
}

# -----------------------------
# Helper: WSUS Group
# -----------------------------
Function Get-WsusGroupForOS {
    # Server only has Unassigned
    return "Unassigned Computers"
}

# -----------------------------
# Configure Windows Update to point to reachable WSUS
# -----------------------------
Function Configure-WUServer {
    Logging "Configuring WSUS policy..." "INFO"

    $candidateWsus = @(
        "http://GBRPSM020006687.intranet.barcapint.com:8530",
        "http://ldtdsm02wsus02.etf.barcapetf.com:8530"
    )

    $WsusServer = $null

    foreach ($u in $candidateWsus) {
        try {
            $resp = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            if ($resp.StatusCode -eq 200) {
                $WsusServer = $u
                Logging "WSUS reachable: $u (HTTP 200)" "INFO"
                break
            } else {
                Logging "WSUS not healthy: $u (HTTP $($resp.StatusCode))" "WARN"
            }
        } catch {
            Logging "WSUS unreachable: $u :: $($_.Exception.Message)" "WARN"
        }
    }

    if (-not $WsusServer) {
        # Keep script behavior explicit: if no WSUS is reachable, log and proceed (may fall back to existing policy).
        Logging "No WSUS endpoint reachable. Proceeding without changing WSUS policy." "WARN"
        return
    }

    $wuKey  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $auKey  = Join-Path $wuKey "AU"

    $current = $null
    try {
        $current = (Get-ItemProperty -Path $wuKey -ErrorAction SilentlyContinue).WUServer
    } catch { }

    if ($current -eq $WsusServer) {
        Logging "WSUS policy already set to $WsusServer" "INFO"
        return
    }

    # Create keys
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows" -Name "WindowsUpdate" -ErrorAction SilentlyContinue | Out-Null
    New-Item -Path $wuKey -Name "AU" -ErrorAction SilentlyContinue | Out-Null

    # Set WSUS policy
    Set-ItemProperty -Path $wuKey -Name "WUServer"            -Value $WsusServer
    Set-ItemProperty -Path $wuKey -Name "WUStatusServer"      -Value $WsusServer
    Set-ItemProperty -Path $wuKey -Name "TargetGroup"         -Value (Get-WsusGroupForOS) | Out-Null
    Set-ItemProperty -Path $wuKey -Name "TargetGroupEnabled"  -Value 1 -Type DWord | Out-Null

    # AU policy
    Set-ItemProperty -Path $auKey -Name "NoAutoUpdate"                 -Value 0  -Type DWord | Out-Null
    Set-ItemProperty -Path $auKey -Name "AUOptions"                    -Value 4  -Type DWord | Out-Null
    Set-ItemProperty -Path $auKey -Name "ScheduledInstallDay"          -Value 0  -Type DWord | Out-Null
    Set-ItemProperty -Path $auKey -Name "ScheduledInstallTime"         -Value 0  -Type DWord | Out-Null
    Set-ItemProperty -Path $auKey -Name "AutoInstallMinorUpdates"      -Value 1  -Type DWord | Out-Null
    Set-ItemProperty -Path $auKey -Name "RebootWarningTimeoutEnabled"  -Value 1  -Type DWord | Out-Null
    Set-ItemProperty -Path $auKey -Name "RebootWarningTimeout"         -Value 30 -Type DWord | Out-Null
    Set-ItemProperty -Path $auKey -Name "UseWUServer"                  -Value 1  -Type DWord | Out-Null
    Set-ItemProperty -Path $auKey -Name "DetectionFrequencyEnabled"    -Value 1  -Type DWord | Out-Null
    Set-ItemProperty -Path $auKey -Name "DetectionFrequency"           -Value 1  -Type DWord | Out-Null

    Logging "WSUS policy updated to $WsusServer. Restarting Windows Update service (wuauserv)..." "INFO"
    Restart-Service wuauserv -Force -ErrorAction Stop
}

# -----------------------------
# Search for updates
# -----------------------------
function Check-WindowsUpdates {
    Logging "Checking for Windows Updates..." "INFO"

    $script:UpdateSearcher = $script:UpdateSession.CreateUpdateSearcher()
    $script:SearchResult   = $script:UpdateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

    $count = $script:SearchResult.Updates.Count
    if ($count -ne 0) {
        Logging "Applicable updates found: $count" "INFO"
        $global:MoreUpdates = 1
    } else {
        Logging "No applicable updates found." "INFO"
        $global:MoreUpdates      = 0
        $global:RestartRequired  = 0
    }

    return $count
}

# -----------------------------
# Download and install updates
# -----------------------------
function Install-WindowsUpdates {
    $script:Cycles++
    Logging "Evaluating available updates (cycle $($script:Cycles))..." "INFO"

    # Collect updates to download
    $UpdatesToDownload = New-Object -ComObject "Microsoft.Update.UpdateColl"

    foreach ($Update in $script:SearchResult.Updates) {
        if (($Update -ne $null) -and (!$Update.IsDownloaded)) {
            $addThisUpdate = $false

            if ($Update.InstallationBehavior.CanRequestUserInput) {
                Logging "Skipping (requires user input): $($Update.Title)" "WARN"
            } else {
                if (-not $Update.EulaAccepted) {
                    Logging "Accepting EULA: $($Update.Title)" "INFO"
                    $Update.AcceptEula()
                }
                $addThisUpdate = $true
            }

            if ($addThisUpdate) {
                Logging "Adding for download: $($Update.Title)" "INFO"
                [void]$UpdatesToDownload.Add($Update)
            }
        }
    }

    # Download
    if ($UpdatesToDownload.Count -gt 0) {
        Logging "Downloading updates ($($UpdatesToDownload.Count))..." "INFO"
        $Downloader = $script:UpdateSession.CreateUpdateDownloader()
        $Downloader.Updates = $UpdatesToDownload
        [void]$Downloader.Download()
    } else {
        Logging "No updates needed to download." "INFO"
    }

    # Collect updates to install
    $UpdatesToInstall = New-Object -ComObject "Microsoft.Update.UpdateColl"
    $rebootMayBeRequired = $false

    Logging "Updates downloaded and ready to install:" "INFO"
    foreach ($Update in $script:SearchResult.Updates) {
        if ($Update.IsDownloaded) {
            Logging "  :: $($Update.Title)" "INFO"
            [void]$UpdatesToInstall.Add($Update)

            if ($Update.InstallationBehavior.RebootBehavior -gt 0) {
                $rebootMayBeRequired = $true
            }
        }
    }

    if ($UpdatesToInstall.Count -eq 0) {
        Logging "No updates available to install." "INFO"
        $global:MoreUpdates     = 0
        $global:RestartRequired = 0
        return $false
    }

    if ($rebootMayBeRequired) {
        Logging "One or more updates indicate a reboot may be required." "INFO"
    }

    # Install
    Logging "Installing updates ($($UpdatesToInstall.Count))..." "INFO"
    $Installer = $script:UpdateSession.CreateUpdateInstaller()
    $Installer.Updates = $UpdatesToInstall
    $InstallationResult = $Installer.Install()

    Logging "Installation ResultCode: $($InstallationResult.ResultCode)" "INFO"
    Logging "Windows Update says RebootRequired: $($InstallationResult.RebootRequired)" "INFO"

    # Record whether WU says reboot required (we will reboot anyway if any updates installed)
    $global:RestartRequired = [int]$InstallationResult.RebootRequired

    # Log per-update results
    for ($i = 0; $i -lt $UpdatesToInstall.Count; $i++) {
        $title  = $UpdatesToInstall.Item($i).Title
        $rcode  = $InstallationResult.GetUpdateResult($i).ResultCode
        Logging "Update result: [$rcode] $title" "INFO"
    }

    return $true
}

# -----------------------------
# Main
# -----------------------------
try {
    Logging "Install_wsus_patches Started" "INFO"

    # Clear/Set patching registry key for orchestration
    Set-ItemProperty -Path $TempRegPath -Name "Patching" -Value "Waiting" -Force

    # Create WU session
    $script:UpdateSession = New-Object -ComObject "Microsoft.Update.Session"
    $script:UpdateSession.ClientApplicationID = "Packer Windows Update Installer"
    $script:UpdateSearcher = $script:UpdateSession.CreateUpdateSearcher()
    $script:SearchResult  = New-Object -ComObject "Microsoft.Update.UpdateColl"
    $script:Cycles        = 0

    # Configure WU server
    Configure-WUServer

    $approved_pending = Check-WindowsUpdates

    if ($approved_pending -ne 0) {
        Logging "$approved_pending pending update(s) will be installed." "INFO"

        $installed = Install-WindowsUpdates
        if ($installed) {
            Logging "All discovered updates have been processed." "INFO"
        } else {
            Logging "No updates were installed (nothing eligible after evaluation)." "INFO"
        }

        # Mark complete for orchestration *before* reboot
        Set-ItemProperty -Path $TempRegPath -Name "Patching" -Value "Completed" -Force

        # REQUIRED BY YOU: always reboot if any updates were pending (i.e., we attempted installation)
        Logging "Rebooting now (invariable reboot policy after update run)." "INFO"
        Restart-Computer -Force

        # If Restart-Computer returns (rare), exit anyway
        exit 0
    }
    else {
        Logging "No more approved updates pending." "INFO"

        # Mark complete
        Set-ItemProperty -Path $TempRegPath -Name "Patching" -Value "Completed" -Force

        # REQUIRED BY YOU: reboot invariably in the end (even if no updates)
        Logging "Rebooting now (invariable reboot policy, even with no updates)." "INFO"
        Restart-Computer -Force

        exit 0
    }
}
catch {
    Logging "ERROR: $($_.Exception.Message)" "ERROR"
    try {
        Set-ItemProperty -Path $TempRegPath -Name "Patching" -Value "Failed" -Force | Out-Null
    } catch { }

    # If something failed, still reboot (you asked for invariable reboot)
    Logging "Rebooting now (invariable reboot policy, even on error)." "WARN"
    try { Restart-Computer -Force } catch { }

    exit 1
}
