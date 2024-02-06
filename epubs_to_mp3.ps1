# Clear the screen
Clear-Host

# Load setup.json content
$setupJsonPath = Join-Path -Path $Global:currentPath -ChildPath "setup.json"
$setupConfig = Get-Content -Path $setupJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

$Global:currentPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

$Global:maxConcurrentJobs = $setupConfig.max_concurrent_speech_jobs

# Accessing the values
$Global:defaultLibraryPath = $setupConfig.default_library_path
$Global:ebookPaths = $setupConfig.ebook_paths

$EpubToTxtScriptPath = "$Global:currentPath\epub_to_txt.ps1"
. $EpubToTxtScriptPath

$TxtToMp3ScriptPath = "$Global:currentPath\txt_to_mp3.ps1"
. $TxtToMp3ScriptPath

# Main Script Execution
Initialize

# Verify and process each ebookPath
if ($Global:ebookPaths -eq $null -or $Global:ebookPaths.Count -eq 0) {
    Write-Host "No ebook paths provided. Exiting script."
    exit
}

$skipConversion = Read-Host "Skip the Epubs to txt conversion? (Y/N, default: N)"
if ($skipConversion -ne 'Y' -and $skipConversion -ne 'y') {
    foreach ($ebookPath in $Global:ebookPaths) {
        $Global:ebookPath = $ebookPath
        Write-Host "`nebookPath : $ebookPath"

        # Convert Epub to Txt
        ConvertEpubToTxtAndEdit
    }

} else {
    Write-Host "Epubs to txt conversion skipped."
}

$skipConversion = Read-Host "Skip the txts to mp3 conversion? (Y/N, default: N)"
if ($skipConversion -ne 'Y' -and $skipConversion -ne 'y') {

    DisplayVoicesAndSave

    # Check if the resolver script exists and then source it
    $resolverScriptPath = "$Global:currentPath\epub_to_mp3_resolver.ps1"
    if (Test-Path -Path $resolverScriptPath) {
        . $resolverScriptPath  # Dot-source the script to import its functions
        UpdateAndRebootForSynthesizerFix  # Now you can call the function directly
    } else {
        Write-Host "Ignore the optional voice resolver part"
    }

    $totalEbooks = $Global:ebookPaths.Count
    $ebookIndex = 1 # Initialize counter for file numbering

    foreach ($ebookPath in $Global:ebookPaths) {
        $Global:ebookPath = $ebookPath
        Write-Host "`nebookPath : $ebookPath"

        # Prepare paths for text-to-audio conversion
        $ebookName = [System.IO.Path]::GetFileNameWithoutExtension($ebookPath)
        $inputFolderPath = Join-Path -Path $Global:currentPath -ChildPath "extracted_chapters\$ebookName"
        $outputFolderPath = Join-Path -Path $Global:currentPath -ChildPath "output\$ebookName"

        # Convert text files to audio
        ConvertTxtToWAV -InputFolderPath $inputFolderPath -OutputFolderPath $outputFolderPath -DesiredVoiceName $Global:voiceName -maxConcurrentJobs $Global:maxConcurrentJobs

        $ebookIndex++ # Increment counter after processing each file

        # Skip the wait countdown if this is the last file
        if ($ebookIndex -lt $totalEbooks) {
            if (WaitWithCountdown -Duration $WaitTimeInSeconds) {
                break
            }
        }

        ConvertAllWAVToMP3 -InputFolderPath $outputFolderPath

        CreateOrUpdatePlaylist -OutputFolderPath $outputFolderPath
    }
} else {
    Write-Host "Txts to mp3 conversion skipped."
}


