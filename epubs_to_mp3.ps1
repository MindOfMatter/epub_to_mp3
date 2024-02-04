# Clear the screen
Clear-Host

# Load setup.json content
$setupJsonPath = Join-Path -Path $Global:currentPath -ChildPath "setup.json"
$setupConfig = Get-Content -Path $setupJsonPath -Raw | ConvertFrom-Json

$Global:currentPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

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

        # Convert Epub to Txt
        ConvertEpubToTxt -EbookPath $ebookPath
    }

} else {
    Write-Host "Epubs to txt conversion skipped."
}

$skipConversion = Read-Host "Skip the txts to mp3 conversion? (Y/N, default: N)"
if ($skipConversion -ne 'Y' -and $skipConversion -ne 'y') {
    $totalEbooks = $Global:ebookPaths.Count
    $ebookIndex = 1 # Initialize counter for file numbering

    foreach ($ebookPath in $Global:ebookPaths) {
        $Global:ebookPath = $ebookPath

        # Prepare paths for text-to-audio conversion
        $ebookName = [System.IO.Path]::GetFileNameWithoutExtension($ebookPath)
        $inputFolderPath = Join-Path -Path $Global:currentPath -ChildPath "extracted_chapters\$ebookName"
        $outputFolderPath = Join-Path -Path $Global:currentPath -ChildPath "output\$ebookName"

        # Convert text files to audio
        ConvertTxtToMP3 -InputFolderPath $inputFolderPath -OutputFolderPath $outputFolderPath -DesiredVoiceName $Global:voiceName

        $ebookIndex++ # Increment counter after processing each file

        # Skip the wait countdown if this is the last file
        if ($ebookIndex -lt $totalEbooks) {
            if (WaitWithCountdown -Duration $WaitTimeInSeconds) {
                break
            }
        }
    }
} else {
    Write-Host "Txts to mp3 conversion skipped."
}


