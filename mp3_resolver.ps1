# Clear the screen
Clear-Host

$Global:currentPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# Load setup.json content
$setupJsonPath = Join-Path -Path $Global:currentPath -ChildPath "setup.json"
$setupConfig = Get-Content -Path $setupJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

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

ConvertAllWAVToMP3 -InputFolderPath $outputFolderPath

CreateOrUpdatePlaylist -OutputFolderPath $outputFolderPath