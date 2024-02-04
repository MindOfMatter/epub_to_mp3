# Load setup.json content
$setupJsonPath = Join-Path -Path $Global:currentPath -ChildPath "setup.json"
$setupConfig = Get-Content -Path $setupJsonPath -Raw | ConvertFrom-Json

$Global:currentPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# Accessing the values
$Global:voiceName = $setupConfig.voice_name
$Global:VoiceRate = $setupConfig.voice_rate
$Global:VoiceVolume = $setupConfig.voice_volume
$Global:WaitTimeInSeconds = 10

$WavToMp3ScriptPath = "$Global:currentPath\wav_to_mp3.ps1"
. $WavToMp3ScriptPath

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

function ConvertTxtToMP3AndEdit {
    param(
        [string]$inputFolderPath,
        [string]$outputFolderPath,
        [string]$desiredVoiceName
    )

    $skipConversion = Read-Host "Skip the txt to mp3 conversion? (Y/N, default: N)"
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