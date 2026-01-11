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

PS C:\Users\mukherjeen_eng\Desktop> Get-Module -ListAvailable PSDscResources | Format-List Name,Version,ModuleBase


Name       : PSDscResources
Version    : 2.12.0.0
ModuleBase : C:\Program Files\WindowsPowerShell\Modules\PSDscResources\2.12.0.0




PS C:\Users\mukherjeen_eng\Desktop> Import-Module PSDscResources
