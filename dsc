$RepoPath = "D:\PSOfflineRepo"

$Dest = "C:\Program Files\WindowsPowerShell\Modules"
New-Item -ItemType Directory -Path $Dest -Force | Out-Null

Get-ChildItem $RepoPath -Directory | ForEach-Object {
    $moduleName = $_.Name
    $latestVersionDir = Get-ChildItem $_.FullName -Directory | Sort-Object Name -Descending | Select-Object -First 1

    Copy-Item -Path $latestVersionDir.FullName -Destination (Join-Path $Dest $moduleName) -Recurse -Force
}
