Configuration DemoConfig {
    param(
        [string[]]$NodeName = "localhost"
    )

    Import-DscResource -ModuleName PSDscResources

    Node $NodeName {

        # Example: ensure a file exists
        File DemoFile {
            Ensure          = "Present"
            Type            = "File"
            DestinationPath = "C:\DSC\hello.txt"
            Contents        = "Hello from DSC push mode. $(Get-Date)"
        }

        # Example: ensure a Windows feature (Server only)
        # WindowsFeature TelnetClient {
        #     Name   = "Telnet-Client"
        #     Ensure = "Present"
        # }
    }
}

[DSCLocalConfigurationManager()]
Configuration LCMConfig {
    param(
        [string[]]$NodeName
    )

    Node $NodeName {
        Settings {
            RefreshMode                    = "Push"
            ConfigurationMode             = "ApplyAndAutoCorrect"  # or ApplyAndMonitor
            ConfigurationModeFrequencyMins = 30
            RefreshFrequencyMins          = 60
            RebootNodeIfNeeded            = $true
            ActionAfterReboot             = "ContinueConfiguration"
            StatusRetentionTimeInDays     = 7
        }
    }
}

$nupkg = "D:\PSOfflineRepo\PSDscResources.2.12.0.nupkg"
$dest  = "C:\Program Files\WindowsPowerShell\Modules\PSDscResources\2.12.0"

Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $dest -Force | Out-Null

Expand-Archive -Path $nupkg -DestinationPath $dest -Force

Get-ChildItem $dest | Select Name,Length
Test-ModuleManifest -Path (Join-Path $dest "PSDscResources.psd1") -Verbose
Get-Module -ListAvailable PSDscResources | Format-List Name,Version,ModuleBase
