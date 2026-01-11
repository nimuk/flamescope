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

S C:\Program Files\WindowsPowerShell\Modules\PSDScResources\2.12.0> $base="C:\Program Files\WindowsPowerShell\Modules\PSDscResources\2.12.0"
PS C:\Program Files\WindowsPowerShell\Modules\PSDScResources\2.12.0> "Base exists: $(Test-Path $base)"
Base exists: True
PS C:\Program Files\WindowsPowerShell\Modules\PSDScResources\2.12.0> "Has psd1 at base: $(Test-Path (Join-Path $base 'PSDscResources.psd1'))"
Has psd1 at base: True
PS C:\Program Files\WindowsPowerShell\Modules\PSDScResources\2.12.0> "Has nested folder: $(Test-Path (Join-Path $base 'PSDscResources'))"
Has nested folder: False
PS C:\Program Files\WindowsPowerShell\Modules\PSDScResources\2.12.0> Get-ChildItem $base -Recurse -Filter "PSDscResources.psd1" -ErrorAction SilentlyContinue | Select FullName

FullName
--------
C:\Program Files\WindowsPowerShell\Modules\PSDscResources\2.12.0\PSDscResources.psd1
