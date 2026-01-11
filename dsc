New-Item -ItemType Directory C:\DSC\Demo -Force | Out-Null
Set-Location C:\DSC\Demo

. .\DemoConfig.ps1
DemoConfig -NodeName @("client1","client2") -OutputPath .\DemoConfig

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

Start-DscConfiguration -ComputerName client1,client2 -Path .\DemoConfig -Verbose -Wait -Force

. .\LCMConfig.ps1
LCMConfig -NodeName @("client1","client2") -OutputPath .\LCMConfig


