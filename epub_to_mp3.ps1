# Clear the screen
Clear-Host

# Load setup.json content
$setupJsonPath = Join-Path -Path $Global:currentPath -ChildPath "setup.json"
$setupConfig = Get-Content -Path $setupJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

$Global:currentPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# Accessing the values
$Global:defaultLibraryPath = $setupConfig.default_library_path
$Global:ebookPath = $setupConfig.default_ebook_path

$EpubToTxtScriptPath = "$Global:currentPath\epub_to_txt.ps1"
. $EpubToTxtScriptPath

$TxtToMp3ScriptPath = "$Global:currentPath\txt_to_mp3.ps1"
. $TxtToMp3ScriptPath

function GetEbookPath {
    [CmdletBinding()]
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.InitialDirectory = $Global:defaultLibraryPath
    $dialog.Filter = "ePub files (*.epub)|*.epub"
    $result = $dialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    Write-Warning "No eBook selected. Exiting script."
    exit
}

# Main Script Execution
Initialize

# Setup and User Prompts
if (-not $Global:ebookPath) {
    $Global:ebookPath = GetEbookPath
}

# Convert Epub to Txt and allow user to edit
ConvertEpubToTxtAndEdit

# Prepare paths for text-to-audio conversion
$ebookName = [System.IO.Path]::GetFileNameWithoutExtension($Global:ebookPath)
$inputFolderPath = Join-Path -Path $Global:currentPath -ChildPath "extracted_chapters\$ebookName"
$outputFolderPath = Join-Path -Path $Global:currentPath -ChildPath "output\$ebookName"


# Convert text files to audio
ConvertTxtToMP3AndEdit -InputFolderPath $inputFolderPath -OutputFolderPath $outputFolderPath -DesiredVoiceName $Global:voiceName

# Uncomment if remaning .wav
#ConvertAllWAVToMP3 -InputFolderPath $outputFolderPath