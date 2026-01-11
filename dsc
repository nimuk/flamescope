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

$env:PSModulePath -split ';'
C:\Users\mukherjeen_eng\Documents\WindowsPowerShell\Modules
C:\Program Files\WindowsPowerShell\Modules
C:\Windows\system32\WindowsPowerShell\v1.0\Modules
PS C:\Program Files\WindowsPowerShell\Modules\PSDScResources\2.12.0>
PS C:\Program Files\WindowsPowerShell\Modules\PSDScResources\2.12.0> Get-ChildItem "C:\Program Files\WindowsPowerShell\Modules\PSDscResources" -ErrorAction SilentlyContinue | Select-Object FullName

FullName
--------
C:\Program Files\WindowsPowerShell\Modules\PSDscResources\2.12.0


PS C:\Program Files\WindowsPowerShell\Modules\PSDScResources\2.12.0>
PS C:\Program Files\WindowsPowerShell\Modules\PSDScResources\2.12.0> Get-Module -ListAvailable PSDscResources | Format-List Name,Version,ModuleBase
PS C:\Program Files\WindowsPowerShell\Modules\PSDScResources\2.12.0>

