param (
    [string]$updateFolder,
    [string]$executeFolder,
    [string]$backupFolder,
    [string]$FilePath,
    [string]$ArgumentList = ""
)

function CompareFolders {
    param (
        [string]$folder1,
        [string]$folder2
    )
    # if folder1 is not exist, return false
    if (-not (Test-Path $folder1)) {
        return $false
    }

    $folder1AbsolutePath = (Resolve-Path $folder1).Path
    $folder1Files = Get-ChildItem -Recurse $folder1AbsolutePath
    $folder2AbsolutePath = (Resolve-Path $folder2).Path
    $folder2Files = Get-ChildItem -Recurse $folder2AbsolutePath

    $folder1Hashes = @{}
    $folder2Hashes = @{}

    # if folder1 is empty, return false
    if ($folder1Files.Count -eq 0) {
        return $false
    }

    foreach ($file in $folder1Files) {
        $path = $file.FullName
        $relativePath = $path.Substring($folder1AbsolutePath.Length).TrimStart('\')
        $folder1Hashes[$relativePath] = Get-FileHash $file.FullName
    }

    foreach ($file in $folder2Files) {
        $path = $file.FullName
        $relativePath = $path.Substring($folder2AbsolutePath.Length).TrimStart('\')
        $folder2Hashes[$relativePath] = Get-FileHash $file.FullName
    }

    $diff = Compare-Object -ReferenceObject $folder1Hashes.Keys -DifferenceObject $folder2Hashes.Keys

    if ($diff.Count -gt 0) {
        return $true
    }

    foreach ($key in $folder1Hashes.Keys) {
        if ($folder1Hashes[$key].Hash -ne $folder2Hashes[$key].Hash) {
            return $true
        }
    }

    return $false
}

function OverwriteFolder {
    param (
        [string]$source,
        [string]$destination
    )
    Remove-Item -Path $destination\* -Recurse -Force
    Copy-Item -Path $source\* -Destination $destination -Recurse
}

$global:BACKUP_PATH = ""
function CreateBackup {
    param (
        [string]$source,
        [string]$destination
    )
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupPath = Join-Path -Path $destination -ChildPath ((Split-Path -Leaf $source) + "_" + $timestamp )
    # if backup folder does not exist, create it
    if (-not (Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force
    }
    $backupFilePath = Join-Path -Path $backupPath -ChildPath "archive.zip"
    Compress-Archive -Path $source -DestinationPath $backupFilePath
    $global:BACKUP_PATH = $backupPath
    return $backupPath
}

function RestoreBackup {
    param (
        [string]$source,
        [string]$destination
    )
    Remove-Item -Path $destination\* -Recurse -Force
    $backupFilePath = Join-Path -Path $source -ChildPath "archive.zip"
    # if backup file does not exist, return
    if (-not (Test-Path $backupFilePath)) {
        Write-Host "Backup is empty. Skipping unzip."
        return
    }
    # get destination parent folder as the destination path
    $destination = Split-Path -Parent $destination
    Expand-Archive -Path $backupFilePath -DestinationPath $destination
}

function ExecuteCommand {
    param (
        [string]$FilePath,
        [string]$ArgumentList
    )
    Write-Host "Executing command: $FilePath $ArgumentList"
    $retryCount = 0
    $maxRetries = 2
    $success = $false

    while ($retryCount -le $maxRetries -and -not $success) {
        if ($ArgumentList -eq "") {
            $process = Start-Process -FilePath $FilePath -Wait -PassThru -NoNewWindow
        }
        else {
            $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow
        }
        if ($process.ExitCode -eq 0) {
            $success = $true
        }
        else {
            Write-Host "Command execution failed. Retrying..."
            $retryCount++
        }
    }

    return $success
}

# Check if any parameter is null or empty
if (-not $updateFolder -or -not $executeFolder -or -not $backupFolder -or -not $FilePath) {
    Write-Host "Error: All parameters (updateFolder, executeFolder, backupFolder, FilePath) must be provided and not empty."
    exit 1
}

Write-Host "Command: $FilePath $ArgumentList"

$IS_UPDATED = $false

# Main script logic
if (CompareFolders -folder1 $updateFolder -folder2 $executeFolder) {
    Write-Host "Updates detected"
    Write-Host "Backing up $executeFolder to $backupFolder..."
    CreateBackup -source $executeFolder -destination $backupFolder
    $backupPath = $global:BACKUP_PATH
    Write-Host "Backup created at $backupPath"
    Write-Host "Updating files from $updateFolder to $executeFolder..."
    OverwriteFolder -source $updateFolder -destination $executeFolder
    Write-Host "Files updated"
    $IS_UPDATED = $true
}
else {
    Write-Host "No updates detected. Skipping backup and overwrite."
}


# Execute commandStr
$result = ExecuteCommand -FilePath $FilePath -ArgumentList $ArgumentList

# Output command execution result
Write-Host "Command execution result: $result"

if (-not $result -and $IS_UPDATED) {
    Write-Host "Command execution failed after updates. Restoring..."
    RestoreBackup -source $backupPath -destination $executeFolder
    # Delete backup folder
    Remove-Item -Path $backupPath -Recurse -Force

    # Re-execute command
    $result = ExecuteCommand -FilePath $FilePath -ArgumentList $ArgumentList
    Write-Host "Restore: Command re-execution result: $result"

    if (-not $result) {
        Write-Host "Command re-execution failed. Please check the logs for more information."
    }
}