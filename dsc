$TempRegPath = "HKLM:\SOFTWARE\Barclays\Windows\Temp"

# Create registry key if it doesn't exist
if (!(Test-Path $TempRegPath)) {
    New-Item -Path "HKLM:\SOFTWARE\Barclays\Windows" -Name "Temp" -Force | Out-Null
}

#$Private:RegPath = Join-path $Private:RegPathRoot -ChildPath 'Windows'
$Global:LogFolder = Join-Path -path $env:systemroot -ChildPath "Platform\Logs"
$Global:LogFile ="$Global:LogFolder\Patching.Log"

Function Logging([String]$Message, [String]$ErrorLevel)
{
    "$(Get-Date) `t $ErrorLevel `t $Message" | Out-File -Append $Global:LogFile
    Write-Host ("$(Get-Date) `t $ErrorLevel `t $Message")
}

Function Get-WsusGroupForOS
{
    ###  Get correct WSUS group for operating system - server only has Unassigned
    return "Unassigned Computers"
    <#
    if ([System.Environment]::OSVersion.Version.Major -eq 10)
	{
		# Windows 2016 server detected
		return "WindowsServer2016"
	}
	else
	{
		# Failback, unknown OS version
		return "Unassigned Computers"
	} #>
}

Function Configure-WUServer {
    ###  Checking local WSUS server
    $WsusServer  = 'http://GBRPSM020006687.intranet.barcapint.com:8530'
    $intwsus = Invoke-WebRequest -Uri $WsusServer -UseBasicParsing | % {$_.StatusCode}
    if ($intwsus -eq 200) {
        Logging "Local WSUS server identified as Intranet" "INFO"
        $WsusServer  = 'http://GBRPSM020006687.intranet.barcapint.com:8530'
    }
    else {
        $etfWsusServer  = 'http://ldtdsm02wsus02.etf.barcapetf.com:8530'
        $etfwsus = Invoke-WebRequest -Uri $etfWsusServer -UseBasicParsing | % {$_.StatusCode}
        if ($etfwsus -eq 200) {
                Logging 'Local WSUS server identified as ETF'
                $WsusServer = $etfWsusServer
        }
    }
	###  Configure WSUS client settings
    If (!(((Get-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue) | Get-ItemProperty -Include "WuSErver" -ErrorAction SilentlyContinue).Wuserver -eq "http://wineng-wsus01:8530")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows" -Name "WindowsUpdate" -ErrorAction SilentlyContinue | out-Null
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "AU" -ErrorAction SilentlyContinue | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -Value $WsusServer
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUStatusServer" -Value $WsusServer
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "TargetGroup" -Value "$(Get-WsusGroupForOS)" | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "TargetGroupEnabled" -Value "1" -Type "Dword" | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value "0" -Type "Dword" | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Value "4" -Type "DWord" | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallDay" -Value "0" -Type "DWord" | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallTime" -Value "0" -Type "DWord" | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AutoInstallMinorUpdates" -Value "1" -Type "DWord" | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "RebootWarningTimeoutEnabled" -Value "1" -Type "DWord" | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "RebootWarningTimeout" -Value "30" -Type "DWord" | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -Value "1" -Type "DWord" | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "DetectionFrequencyEnabled" -Value "1" -Type "DWord" | out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "DetectionFrequency" -Value "1" -Type "DWord" | out-Null

        Logging "Created registry keys and restarting WU service" "INFO"

        Restart-Service wuauserv -Force
    }
}

function Check-WindowsUpdates
{
    Logging 'Checking For Windows Updates'
    $script:UpdateSearcher = $script:UpdateSession.CreateUpdateSearcher()
    $script:SearchResult = $script:UpdateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")      
    if ($SearchResult.Updates.Count -ne 0) {
        $script:SearchResult.Updates | Select-Object -Property Title, Description, SupportUrl, UninstallationNotes, RebootRequired, EulaAccepted | Format-List
        $global:MoreUpdates=1
    } else {
        Logging 'There are no applicable updates'
        $global:RestartRequired=0
        $global:MoreUpdates=0
    }
    return $SearchResult.Updates.Count
}

function Install-WindowsUpdates() {
    $script:Cycles++
    Logging 'Evaluating Available Updates:'
    $UpdatesToDownload = New-Object -ComObject 'Microsoft.Update.UpdateColl'
    foreach ($Update in $SearchResult.Updates) {
        if (($Update -ne $null) -and (!$Update.IsDownloaded)) {
            [bool]$addThisUpdate = $false
            if ($Update.InstallationBehavior.CanRequestUserInput) {
                Logging "Skipping: $($Update.Title) because it requires user input"
            } else {
                if (!($Update.EulaAccepted)) {
                    Logging "Note: $($Update.Title) has a license agreement that must be accepted. Accepting the license."
                    $Update.AcceptEula()
                    [bool]$addThisUpdate = $true
                } else {
                    [bool]$addThisUpdate = $true
                }
            }
        
            if ([bool]$addThisUpdate) {
                Logging "Adding: $($Update.Title)"
                $UpdatesToDownload.Add($Update) | Out-Null
            }
        }
    }
    
    if ($UpdatesToDownload.Count -eq 0) {
        Logging 'No Updates To Download...'
    } else {
        Logging 'Downloading Updates...'
        $Downloader = $UpdateSession.CreateUpdateDownloader()
        $Downloader.Updates = $UpdatesToDownload
        $Downloader.Download()
    }
	
    $UpdatesToInstall = New-Object -ComObject 'Microsoft.Update.UpdateColl'
    [bool]$rebootMayBeRequired = $false
    Logging 'The following updates are downloaded and ready to be installed:'
    foreach ($Update in $SearchResult.Updates) {
        if (($Update.IsDownloaded)) {
            Logging ":: $($Update.Title)"
            $UpdatesToInstall.Add($Update) |Out-Null
              
            if ($Update.InstallationBehavior.RebootBehavior -gt 0){
                [bool]$rebootMayBeRequired = $true
            }
        }
    }
    
    if ($UpdatesToInstall.Count -eq 0) {
        Logging 'No updates available to install...'
        $global:MoreUpdates=0
        $global:RestartRequired=0
        return $true
    }

    if ($rebootMayBeRequired) {
        Logging 'These updates may require a reboot'
        $global:RestartRequired=1
    }
	
    Logging 'Installing updates...'
  
    $Installer = $script:UpdateSession.CreateUpdateInstaller()
    $Installer.Updates = $UpdatesToInstall
    $InstallationResult = $Installer.Install()
  
    Logging "Installation Result: $($InstallationResult.ResultCode)"
    Logging "Reboot Required: $($InstallationResult.RebootRequired)"
    if ($InstallationResult.RebootRequired) {
        $global:RestartRequired=1
    } else {
        $global:RestartRequired=0
    }
    
    for($i=0; $i -lt $UpdatesToInstall.Count; $i++) {
        New-Object -TypeName PSObject -Property @{
            Title = $UpdatesToInstall.Item($i).Title
            Result = $InstallationResult.GetUpdateResult($i).ResultCode
        }
    }
	
    return $true
}

#############################################
# Main script starts here
##############################################

Logging 'Install_wsus_patches Started' 

# Clear patching registry key, used to communicate with packer patch_schedule_wait process

Set-ItemProperty -Path $TempRegPath -Name "Patching" -Value "Waiting" -Force

# Windows Udpate connection
$script:UpdateSession = New-Object -ComObject 'Microsoft.Update.Session'
$script:UpdateSession.ClientApplicationID = 'Packer Windows Update Installer'
$script:UpdateSearcher = $script:UpdateSession.CreateUpdateSearcher()
$script:SearchResult = New-Object -ComObject 'Microsoft.Update.UpdateColl'
$script:Cycles = 0

# Configure WU server
Configure-WUServer

$approved_pending = Check-WindowsUpdates

if ($approved_pending -ne 0)
{
    Logging "$approved_pending pending updates will be installed" "INFO"
    Install-WindowsUpdates
    Logging "All updates have been installed successfully" "INFO"

    if ($global:RestartRequired -eq 1) {
        Logging "Updates require restart. Initiating system restart now." "INFO"
        Set-ItemProperty -Path $TempRegPath -Name "Patching" -Value "Completed" -Force
        Restart-Computer -Force
    } else {
        Logging "Updates completed successfully. No restart required." "INFO"
        Set-ItemProperty -Path $TempRegPath -Name "Patching" -Value "Completed" -Force
    }
    Exit 0
}
else
{
    Logging 'No more approved updates pending'
    Set-ItemProperty -Path $TempRegPath -Name "Patching" -Value "Completed" -Force
    Exit 0
}
