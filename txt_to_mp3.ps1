# Load setup.json content
$setupJsonPath = Join-Path -Path $Global:currentPath -ChildPath "setup.json"
$setupConfig = Get-Content -Path $setupJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

$Global:currentPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# Accessing the values
$Global:overwriteExisting = $setupConfig.overwrite_existing
$Global:removeOutputFolder = $setupConfig.remove_output_folder

$Global:voiceName = $setupConfig.voice_name
$Global:VoiceRate = $setupConfig.voice_rate
$Global:VoiceVolume = $setupConfig.voice_volume

$Global:maxConcurrentJobs = $setupConfig.max_concurrent_speech_jobs

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

    # Only remove files if removeOutputFolder is true
    if ($Global:removeOutputFolder -and (Test-Path -Path $outputFolderPath)) {
            try {
        Get-ChildItem -Path $outputFolderPath -File | Remove-Item -Force
        Write-Host "All files in $outputFolderPath have been removed."
        } catch {
            Write-Host "An error occurred while trying to remove files: $_"
        }
        Write-Host "All files in $outputFolderPath have been removed."
    } else {
        Write-Host "Skip clearing output folder : $outputFolderPath"
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

function ConvertTxtToWAV {
    param(
        [string]$inputFolderPath,
        [string]$outputFolderPath,
        [string]$desiredVoiceName,
        [int]$maxConcurrentJobs = 5 # Control the number of concurrent jobs
    )
    CheckFolderPath -Path $inputFolderPath -Type 'input'
    CheckFolderPath -Path $outputFolderPath -Type 'output'

    ClearOutputFolder -outputFolderPath $outputFolderPath

    $overwriteExisting = $Global:overwriteExisting
    $voiceRate = $Global:VoiceRate
    $voiceVolume = $Global:VoiceVolume
    $realIndex = 1

    $files = Get-ChildItem -Path $inputFolderPath -Filter *.txt
    $jobs = @()

    foreach ($file in $files) {
        if ($jobs.Count -ge $maxConcurrentJobs) {
            $completedJobs = Wait-Job -Job $jobs -Any
            Remove-Job -Job $completedJobs -Force
            $jobs = $jobs | Where-Object { $_.State -eq 'Running' }
        }

        $inputFilePath = $file.FullName
        $outputFileName = "{0:D3} - {1}" -f ++$realIndex, [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $outputFilePath = Join-Path -Path $outputFolderPath -ChildPath $outputFileName

        $job = Start-Job -ScriptBlock {
            param($inputFilePath, $outputFilePath, $voiceName, $voiceRate, $voiceVolume)
            
            # Check if output file exists and skip if overwriteExisting is false
            if (-not $overwriteExisting -and (Test-Path -Path $outputFilePath + ".(mp3|wav)")) {
                Write-Host "Output file $OutputFilePath already exists. Skipping..."
                return
            }

            Add-Type -AssemblyName System.Speech
            $synthesizer = New-Object System.Speech.Synthesis.SpeechSynthesizer
            if ($voiceName) {
                $synthesizer.SelectVoice($voiceName)
            }
            $synthesizer.Rate = $voiceRate
            $synthesizer.Volume = $voiceVolume
            try {
                $wavOutputPath = $outputFilePath + ".wav"
                $textContent = Get-Content -Path $inputFilePath -Raw -Encoding Default
                $synthesizer.SetOutputToWaveFile($wavOutputPath)
                $synthesizer.Speak($textContent)
            } catch {
                Write-Output "`nError processing the file: $inputFilePath"
            }
            finally {
                $synthesizer.SetOutputToDefaultAudioDevice()
                $synthesizer.Dispose()
            }
        } -ArgumentList $inputFilePath, $outputFilePath, $desiredVoiceName, $voiceRate, $voiceVolume

        $jobs += $job
        Write-Host "Started processing file: $outputFileName"
    }

    # Wait for any remaining jobs to complete
    Wait-Job -Job $jobs
    Remove-Job -Job $jobs -Force

    Write-Host "All files have been processed."
}

function ConvertTxtToMP3AndEdit {
    param(
        [string]$inputFolderPath,
        [string]$outputFolderPath,
        [string]$desiredVoiceName
    )

    $skipConversion = Read-Host "Skip the txt to mp3 conversion? (Y/N, default: N)"
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

        # Convert Txt to WAV
        ConvertTxtToWAV -InputFolderPath $inputFolderPath -OutputFolderPath $outputFolderPath -DesiredVoiceName $desiredVoiceName -maxConcurrentJobs $Global:maxConcurrentJobs

        # Convert WAV to MP3
        ConvertAllWAVToMP3 -InputFolderPath $outputFolderPath

        CreateOrUpdatePlaylist -OutputFolderPath $outputFolderPath

        Write-Host "`nTxt to mp3 done, these are mp3 results"

        Start-Sleep -Seconds 2

        Invoke-Item "$outputFolderPath"
    } else {
        Write-Host "Txt to mp3 conversion skipped."
    }
}