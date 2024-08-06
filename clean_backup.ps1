param (
    [string]$backupFolder,
    [int]$daysThreshold = 60,
    [int]$maxBackups = 10
)

function CleanOldBackups {
    param (
        [string]$backupFolder,
        [int]$daysThreshold,
        [int]$maxBackups
    )

    # Get all backup folders
    $backups = Get-ChildItem -Path $backupFolder -Directory

    # 1. Delete backups older than the specified number of days
    $now = Get-Date
    foreach ($backup in $backups) {
        $backupDate = [datetime]::ParseExact($backup.Name.Split('_')[-1], "yyyyMMddHHmmss", $null)
        if (($now - $backupDate).Days -gt $daysThreshold) {
            Remove-Item -Path $backup.FullName -Recurse -Force
        }
    }

    # Get all backup folders again
    $backups = Get-ChildItem -Path $backupFolder -Directory | Sort-Object { [datetime]::ParseExact($_.Name.Split('_')[-1], "yyyyMMddHHmmss", $null) }

    # 2. Delete backups exceeding the maximum number
    while ($backups.Count -gt $maxBackups) {
        Remove-Item -Path $backups[0].FullName -Recurse -Force
        $backups = $backups[1..$backups.Count]
    }
}

# Main script execution
CleanOldBackups -backupFolder $backupFolder -daysThreshold $daysThreshold -maxBackups $maxBackups