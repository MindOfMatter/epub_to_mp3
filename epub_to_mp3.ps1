# Clear the screen
Clear-Host

# Load setup.json content
$setupJsonPath = Join-Path -Path $Global:currentPath -ChildPath "setup.json"
$setupConfig = Get-Content -Path $setupJsonPath -Raw | ConvertFrom-Json

# Accessing the values
$Global:defaultCoverPath = $setupConfig.default_cover_path
$Global:defaultLibraryPath = $setupConfig.default_library_path
$Global:ebookPath = $setupConfig.default_ebook_path
$Global:voiceName = $setupConfig.voice_name
$Global:VoiceRate = $setupConfig.voice_rate
$Global:VoiceVolume = $setupConfig.voice_volume

$Global:currentPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$Global:ffmpegPath = Join-Path -Path $Global:currentPath -ChildPath "ffmpeg.exe"
$Global:WaitTimeInSeconds = 10

# Helper Functions
function Initialize {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Speech
    Write-Host "`nInitialization Complete."
}

function CheckFolderPath {
    param(
        [string]$Path,
        [string]$Type # 'input' or 'output'
    )
    if (-not (Test-Path $Path)) {
        if ($Type -eq 'input') {
            Write-Host "Error: Folder not found at path: $Path"
            exit
        } elseif ($Type -eq 'output') {
            New-Item -Path $Path -ItemType Directory
            Write-Host "Output folder created at: $Path"
        }
    }
}

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

function WaitWithCountdown {
    param(
        [int]$Duration
    )
    for ($i = $Duration; $i -gt 0; $i--) {
        Write-Host "`rWaiting for $i seconds. Press 'Q' to stop." -NoNewline
        Start-Sleep -Seconds 1
        if ([console]::KeyAvailable) {
            $key = [System.Console]::ReadKey($true)
            if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') {
                Write-Host "`nQ pressed, stopping."
                return $true
            }
        }
    }
    return $false
}

function ClearOutputFolder {
    param(
        [string]$outputFolderPath
    )

    # Check if the output folder exists
    if (Test-Path -Path $outputFolderPath) {
        try {
            # Remove all files within the output folder
            Get-ChildItem -Path $outputFolderPath -File | Remove-Item -Force
            Write-Host "All files in $outputFolderPath have been removed."
        } catch {
            Write-Host "An error occurred while trying to remove files: $_"
        }
    } else {
        Write-Host "Output folder $outputFolderPath does not exist."
    }
}

function DisplayVoicesAndSave {
    Add-Type -AssemblyName System.Speech
    $synthesizer = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $voiceList = @()
    $voices = $synthesizer.GetInstalledVoices()

    foreach ($voice in $voices) {
        $info = $voice.VoiceInfo
        Write-Host "$($info.Name) - $($info.Description)"
        $voiceList += [PSCustomObject]@{
            Name = $info.Name
            Description = $info.Description
            Culture = $info.Culture.Name
            Gender = $info.Gender
            Age = $info.Age
        }
    }

    $voiceList | Export-Csv -Path "InstalledVoices.csv" -NoTypeInformation
    Write-Host "Voices exported to InstalledVoices.csv"
}


function SelectVoice {
    param(
        [string]$DesiredVoiceName
    )
    $synthesizer = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $voice = $synthesizer.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Name -eq $DesiredVoiceName } | Select-Object -First 1
    if ($null -eq $voice) {
        Write-Host "`nVoice '$DesiredVoiceName' not found. Using the default voice."
        return $null
    }
    Write-Host "`nUsing the specified voice: $DesiredVoiceName"
    return $voice.VoiceInfo.Name
}


function ConvertTextToSpeech {
    param(
        [string]$InputFilePath,
        [string]$OutputFilePath,
        [string]$VoiceName
    )
    
    DisplayVoicesAndSave

    # Check if the resolver script exists and then source it
    $resolverScriptPath = "$Global:currentPath\epub_to_mp3_resolver.ps1"
    if (Test-Path -Path $resolverScriptPath) {
        . $resolverScriptPath  # Dot-source the script to import its functions
        UpdateAndRebootForSynthesizerFix  # Now you can call the function directly
    } else {
        Write-Host "Ignore the optional voice resolver part"
    }

    $synthesizer = New-Object System.Speech.Synthesis.SpeechSynthesizer
    if ($VoiceName) {
        $synthesizer.SelectVoice($VoiceName)
    }
    $synthesizer.Rate = $Global:VoiceRate
    $synthesizer.Volume = $Global:VoiceVolume
    try {
        Write-Host "`nConverting txt to wav : $OutputFilePath"
        # Adjusted to explicitly specify the encoding when reading the text file
        $textContent = Get-Content -Path $InputFilePath -Raw -Encoding Default
        $synthesizer.SetOutputToWaveFile($OutputFilePath)
        $synthesizer.Speak($textContent)
        Write-Host "`nWAV file created: $OutputFilePath"
        $synthesizer.SetOutputToDefaultAudioDevice()
    } catch {
        Write-Host "`nError processing the file: $InputFilePath"
    }
}

function GetAlbumName {
    param(
        [string]$inputFilePath
    )
    # Extract the parent folder name as the album name
    $albumName = Split-Path $inputFilePath -Parent | Split-Path -Leaf
    return $albumName
}

function GetTrackName {
    param(
        [string]$inputFilePath
    )
    # Extract the file name without extension
    $inputFileName = [System.IO.Path]::GetFileNameWithoutExtension($inputFilePath)
    return $inputFileName -replace '^[^-]* - ', ''
}

function GetTrackNumber {
    param(
        [string]$inputFilePath
    )
    # Extract the numeric part from the file name
    $inputFileName = [System.IO.Path]::GetFileNameWithoutExtension($inputFilePath)
    if ($inputFileName -match '^\d+') {
        # If the file name starts with numbers, parse them to an integer
        $number = [int]$Matches[0]
        return $number
    } else {
        # Return 0 or another default value if no number is found
        return 0
    }
}

function ConvertWAVToMP3 {
    param(
        [string]$InputWAVFilePath,
        [string]$OutputMP3FilePath
    )
    $albumName = GetAlbumName -inputFilePath $InputWAVFilePath
    Write-Host "`nalbumName: $albumName"
    $trackName = GetTrackName -inputFilePath $InputWAVFilePath
    Write-Host "`ntrackName: $trackName"
    $trackNumber = GetTrackNumber -inputFilePath $InputWAVFilePath
    Write-Host "`ntrackNumber: $trackNumber"

    # Determine the cover image path
    $parentPath = Split-Path -Parent $Global:ebookPath
    $coverPath = Join-Path -Path $parentPath -ChildPath "cover.jpg"

    # Check if custom cover exists; if not, use default
    if (Test-Path -Path $coverPath -PathType Leaf) {
        $coverImagePath = $coverPath
    } else {
        $coverImagePath = $Global:defaultCoverPath
    }

    # Define the command to convert WAV to MP3 and set the cover image
    $commandParts = @(
        $Global:ffmpegPath,
        '-i', "`"$InputWAVFilePath`"",     # Input WAV file
        '-i', "`"$coverImagePath`"",       # Input cover image
        '-map', '0:0',                     # Map audio stream
        '-map', '1:0',                     # Map image stream
        '-codec:a', 'libmp3lame',          # Audio codec
        '-qscale:a', '2',                  # Quality scale for audio
        '-metadata', "title=`'$trackName`'", # Title metadata
        '-metadata', "artist=`'Unknown Artist`'", # Artist metadata
        '-metadata', "album=`'$albumName`'",     # Album metadata
        '-metadata', "track=`'$trackNumber`'",   # Track number
        '-disposition:v:0', 'attached_pic',  # Set image as cover art
        "`"$OutputMP3FilePath`""          # Output MP3 file
    )
    $command = $commandParts -join ' '
    Invoke-Expression $command

    Write-Host "`n$command"
    
    if (Test-Path $OutputMP3FilePath) {
        Write-Host "`nMP3 file created: $OutputMP3FilePath"
        Remove-Item -Path $InputWAVFilePath # Clean up the temporary WAV file
    } else {
        Write-Host "`nFailed to convert WAV to MP3 for: $InputWAVFilePath"
    }
}

function ConvertEpubToTxtAndEdit {
    [CmdletBinding()]

    $skipConversion = Read-Host "Skip the Epub to txt conversion? (Y/N, default: N)"
    #$skipConversion = 'y'
    if ($skipConversion -ne 'Y' -and $skipConversion -ne 'y') {
        $ebookName = [System.IO.Path]::GetFileNameWithoutExtension($Global:ebookPath)
        $outputTxtFolderPath = Join-Path -Path $Global:currentPath -ChildPath "extracted_chapters\$ebookName"
        & "python" "$Global:currentPath\epub_to_txt_by_chapter.py" $Global:ebookPath
        Write-Host "`nEpub to txt conversion done. Path: $outputTxtFolderPath"
        Start-Sleep -Seconds 2

        Invoke-Item $outputTxtFolderPath
    } else {
        Write-Host "Epub to txt conversion skipped."
    }
}

function ConvertTxtToMP3AndEdit {
    param(
        [string]$inputFolderPath,
        [string]$outputFolderPath,
        [string]$desiredVoiceName
    )

    $skipConversion = Read-Host "Skip the txt to mp3 conversion? (Y/N, default: N)"
    #$skipConversion = 'n'
    if ($skipConversion -ne 'Y' -and $skipConversion -ne 'y') {
        # Convert Txt to MP3
        ConvertTxtToMP3 -InputFolderPath $inputFolderPath -OutputFolderPath $outputFolderPath -DesiredVoiceName $desiredVoiceName

        Write-Host "`nTxt to mp3 done, these are mp3 results"

        Start-Sleep -Seconds 2

        Invoke-Item "$outputFolderPath"
    } else {
        Write-Host "Txt to mp3 conversion skipped."
    }
}

function ConvertTxtToMP3 {
    param(
        [string]$inputFolderPath,
        [string]$outputFolderPath,
        [string]$desiredVoiceName
    )
    CheckFolderPath -Path $inputFolderPath -Type 'input'
    CheckFolderPath -Path $outputFolderPath -Type 'output'

    ClearOutputFolder -outputFolderPath $outputFolderPath

    $voiceName = SelectVoice -DesiredVoiceName $desiredVoiceName

    $files = Get-ChildItem -Path $inputFolderPath -Filter *.txt
    $totalFiles = $files.Count
    $realIndex = 1 # Initialize counter for file numbering

    foreach ($file in $files) {
        $inputFilePath = $file.FullName

        # Format the new filename with the zero-padded index
        $formattedIndex = "{0:D3}" -f $realIndex
        $trackName = GetTrackName -inputFilePath $inputFilePath
        $outputFileName = "$formattedIndex - $trackName"

        $wavOutputPath = "$outputFolderPath\$outputFileName.wav"
        ConvertTextToSpeech -InputFilePath $inputFilePath -OutputFilePath $wavOutputPath -VoiceName $voiceName
        $mp3OutputPath = "$outputFolderPath\$outputFileName.mp3"
        ConvertWAVToMP3 -InputWAVFilePath $wavOutputPath -OutputMP3FilePath $mp3OutputPath

        Write-Host "Saved: $mp3OutputPath"

        $percentComplete = ($realIndex / $totalFiles) * 100
        Write-Host "Progress: $($percentComplete.ToString("0.00"))% ($realIndex of $totalFiles)"

        $realIndex++ # Increment counter after processing each file

        CreateOrUpdatePlaylist -OutputFolderPath $outputFolderPath

        # Skip the wait countdown if this is the last file
        if ($realIndex -lt $totalFiles) {
            if (WaitWithCountdown -Duration $WaitTimeInSeconds) {
                break
            }
        }
    }
}

function CreateOrUpdatePlaylist {
    param(
        [string]$OutputFolderPath,
        [string]$PlaylistName = "playlist.m3u"
    )

    # Define the path for the playlist file
    $playlistFilePath = Join-Path -Path $OutputFolderPath -ChildPath $PlaylistName

    # Check if playlist file exists, if not, create it
    if (-not (Test-Path -Path $playlistFilePath)) {
        New-Item -Path $playlistFilePath -ItemType File
        Write-Host "Playlist file created: $PlaylistName"
    } else {
        Write-Host "Updating existing playlist file: $PlaylistName"
    }

    # Get all MP3 files in the output folder
    $mp3Files = Get-ChildItem -Path $OutputFolderPath -Filter "*.mp3"

    # Append MP3 file paths to the playlist file
    foreach ($file in $mp3Files) {
        Add-Content -Path $playlistFilePath -Value $file.FullName
    }

    Write-Host "Playlist updated with all MP3 files in $OutputFolderPath"
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