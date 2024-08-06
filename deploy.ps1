param (
    [string]$updateFolder,
    [string]$executeFolder,
    [string]$backupFolder,
    [string[]]$commands
)

function BackupFolder {
    param (
        [string]$source,
        [string]$destination
    )
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupPath = Join-Path -Path $destination -ChildPath ((Split-Path -Leaf $source) + "_" + $timestamp )
    Copy-Item -Path $source -Destination $backupPath -Recurse
    return $backupPath
}

function CompareFolders {
    param (
        [string]$folder1,
        [string]$folder2
    )
    $diff = Compare-Object -ReferenceObject (Get-ChildItem -Recurse $folder1) -DifferenceObject (Get-ChildItem -Recurse $folder2)
    return $diff.Count -gt 0
}

function OverwriteFolder {
    param (
        [string]$source,
        [string]$destination
    )
    Remove-Item -Path $destination\* -Recurse -Force
    Copy-Item -Path $source\* -Destination $destination -Recurse
}

function ExecuteCommands {
    param (
        [string[]]$commands
    )
    $retryCount = 0
    $maxRetries = 2
    $success = $false

    while ($retryCount -le $maxRetries -and -not $success) {
        try {
            & $commands
            $success = $true
        }
        catch {
            Write-Host "Command execution failed. Retrying..."
            $retryCount++
        }
    }

    return $success
}

# Main script logic
if (CompareFolders -folder1 $updateFolder -folder2 $executeFolder) {
    $backupPath = BackupFolder -source $executeFolder -destination $backupFolder
    OverwriteFolder -source $updateFolder -destination $executeFolder

    # Execute commands
    $result = ExecuteCommands -commands $commands

    # Output command execution result
    Write-Host "Command execution result: $result"

    if (-not $result) {
        Write-Host "Command execution failed after retries. Restoring backup..."
        Remove-Item -Path "$executeFolder\*" -Recurse -Force
        Copy-Item -Path "$backupPath\*" -Destination $executeFolder -Recurse

        # Re-execute commands
        $result = ExecuteCommands -commands $commands
        Write-Host "Restore: Command re-execution result: $result"

        if (-not $result) {
            Write-Host "Command re-execution failed. Please check the logs for more information."
        }
    }
}
else {
    Write-Host "No updates detected. Skipping backup and overwrite."
}