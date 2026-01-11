Configuration ScriptPushConfig {
    param(
        [string[]]$NodeName,
        [string]$SourceScriptsPath = "C:\DSC\Scripts"
    )

    Import-DscResource -ModuleName PSDscResources

    Node $NodeName {

        # Ensure destination folder exists on client
        File ScriptFolder {
            Ensure          = "Present"
            Type            = "Directory"
            DestinationPath = "C:\DSC\Scripts"
        }

        # Copy all scripts from server -> client
        File CopyScripts {
            Ensure          = "Present"
            Type            = "Directory"
            SourcePath      = $SourceScriptsPath
            DestinationPath = "C:\DSC\Scripts"
            Recurse         = $true
            DependsOn       = "[File]ScriptFolder"
        }
    }
}

        Script RunInstall {
            DependsOn = "[File]CopyScripts"

            GetScript = {
                $marker = "C:\DSC\Scripts\.install_done"
                @{ Result = (Test-Path $marker) }
            }

            TestScript = {
                Test-Path "C:\DSC\Scripts\.install_done"
            }

            SetScript = {
                $script = "C:\DSC\Scripts\Install-MyThing.ps1"

                # run it
                powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script

                # mark success
                New-Item -ItemType File -Path "C:\DSC\Scripts\.install_done" -Force | Out-Null
            }
        }


Set-Location C:\DSC\Config
. .\ScriptPushConfig.ps1

New-Item -ItemType Directory C:\DSC\Out -Force | Out-Null
ScriptPushConfig -NodeName @("client1","client2") -OutputPath C:\DSC\Out


Start-DscConfiguration -ComputerName client1,client2 -Path C:\DSC\Out -Wait -Verbose -Force
