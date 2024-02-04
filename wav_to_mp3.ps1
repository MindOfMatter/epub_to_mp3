# Load setup.json content
$setupJsonPath = Join-Path -Path $Global:currentPath -ChildPath "setup.json"
$setupConfig = Get-Content -Path $setupJsonPath -Raw | ConvertFrom-Json

$Global:currentPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# Accessing the values
$Global:defaultCoverPath = $setupConfig.default_cover_path
$Global:ffmpegPath = Join-Path -Path $Global:currentPath -ChildPath "ffmpeg.exe"

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
        '-metadata', "title=`"$trackName`"", # Title metadata
        '-metadata', "artist=`"Unknown Artist`"", # Artist metadata
        '-metadata', "album=`"$albumName`"",     # Album metadata
        '-metadata', "track=`"$trackNumber`"",   # Track number
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

function ConvertAllWAVToMP3 {
    param(
        [string]$InputFolderPath
    )
    
    Write-Host "ConvertAllWAVToMP3 InputFolderPath : $InputFolderPath"
    
    # Retrieve all .wav files from the specified folder
    $wavFiles = Get-ChildItem -Path $InputFolderPath -Filter *.wav
    
    foreach ($wavFile in $wavFiles) {
        $inputWAVFilePath = $wavFile.FullName
        $outputMP3FilePath = $inputWAVFilePath -replace '\.wav$', '.mp3'
        
        # Call the ConvertWAVToMP3 function for each file
        ConvertWAVToMP3 -InputWAVFilePath $inputWAVFilePath -OutputMP3FilePath $outputMP3FilePath
    }

    CreateOrUpdatePlaylist -OutputFolderPath $outputFolderPath
}

function CreateOrUpdatePlaylist {
    param(
        [string]$OutputFolderPath,
        [string]$PlaylistName = "playlist.m3u"
    )

    # Define the path for the playlist file
    $playlistFilePath = Join-Path -Path $OutputFolderPath -ChildPath $PlaylistName

    # Check if playlist file exists, if not, create it
    if (Test-Path -Path $playlistFilePath) {
        Remove-Item -Path $playlistFilePath
        Write-Host "Overwritting existing playlist file: $PlaylistName"
    } else {
        Write-Host "Playlist file created: $PlaylistName"
    }
    
    New-Item -Path $playlistFilePath -ItemType File

    # Get all MP3 files in the output folder
    $mp3Files = Get-ChildItem -Path $OutputFolderPath -Filter "*.mp3"

    # Append MP3 file paths to the playlist file
    foreach ($file in $mp3Files) {
        Add-Content -Path $playlistFilePath -Value $file.FullName
    }

    Write-Host "Playlist updated with all MP3 files in $OutputFolderPath"
}