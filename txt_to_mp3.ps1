# Define global settings from setup.json
$Global:currentPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$setupJsonPath = Join-Path -Path $Global:currentPath -ChildPath "setup.json"
$setupConfig = Get-Content -Path $setupJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Assign global variables from setup.json
$Global:overwriteExisting = $setupConfig.overwrite_existing
$Global:removeOutputFolder = $setupConfig.remove_output_folder
$Global:voiceName = $setupConfig.voice_name
$Global:voiceRate = $setupConfig.voice_rate
$Global:voiceVolume = $setupConfig.voice_volume
$Global:maxConcurrentJobs = $setupConfig.max_concurrent_speech_jobs

if ($null -ne $Global:maxConcurrentJobs) {
    $Global:maxConcurrentJobs = 5
}

$Global:estimatedDurationPerCharacter = 30

# Load additional script
$WavToMp3ScriptPath = "$Global:currentPath\wav_to_mp3.ps1"
. $WavToMp3ScriptPath

# Initialize required assemblies
function Initialize {
    Add-Type -AssemblyName System.Windows.Forms, System.Speech
    Write-Host "`nInitialization Complete."
}

# Validate and manage folder paths
function EnsureFolderPath {
    param([string]$Path, [string]$Purpose) # 'input' or 'output'
    if (-not (Test-Path $Path)) {
        switch ($Purpose) {
            'input' { Write-Host "Error: Input folder not found at path: $Path"; exit }
            'output' { New-Item -Path $Path -ItemType Directory; Write-Host "Output folder created at: $Path" }
        }
    }
}

# Function to clear output folder if required
function ClearOutputFolderIfNeeded {
    param([string]$FolderPath)
    if ($Global:removeOutputFolder -and (Test-Path -Path $FolderPath)) {
        Remove-Item -Path "$FolderPath\*" -Force
        Write-Host "Cleared output folder: $FolderPath"
    }
}

# Voice validation
function VerifyVoice {
    param([string]$DesiredVoiceName)
    $synthesizer = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $voice = $synthesizer.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Name -eq $DesiredVoiceName } | Select-Object -First 1
    if ($voice) {
        Write-Host "`nUsing specified voice: $DesiredVoiceName"
        return $voice.VoiceInfo.Name
    } else {
        Write-Host "`nSpecified voice '$DesiredVoiceName' not found. Using default."
        exit
    }
}

function ConvertTxtToWAV {
    param(
        [string]$inputFolderPath,
        [string]$outputFolderPath
    )
    EnsureFolderPath -Path $inputFolderPath -Purpose 'input'
    EnsureFolderPath -Path $outputFolderPath -Purpose 'output'
    ClearOutputFolderIfNeeded -FolderPath $outputFolderPath

    $files = Get-ChildItem -Path $inputFolderPath -Filter *.txt
    $jobs = @()
    $outputFileNames = @()
    
    VerifyVoice -DesiredVoiceName $Global:voiceName
    Write-Host "Starting text to WAV conversion using voice: '$Global:voiceName'"
    
    $realIndex = 1
    foreach ($file in $files) {
        ManageConcurrentJobs -Jobs ([ref]$Jobs)

        # Call FormatOutputFileName to get the output file name
        $OutputFileName = FormatOutputFileName -Index $realIndex -File $file
        $outputFileNames += $OutputFileName
        $outputFilePath = Join-Path -Path $outputFolderPath -ChildPath $OutputFileName
        $logFilePath = "$outputFilePath.log"

        # Clean up after job completion
        Remove-Item -Path $logFilePath -ErrorAction SilentlyContinue 
        
        $job = StartConversionJob `
            -InputFilePath $file.FullName `
            -OutputFilePath $outputFilePath `
            -OutputFileName $OutputFileName `
            -LogFilePath $logFilePath `
            -Jobs ([ref]$Jobs)

        $realIndex++ # Increment counter after processing each file
    }
    
    MonitorJobProgress -Jobs $jobs -outputFileNames $outputFileNames

    WaitForJobsCompletion -Jobs  ([ref]$Jobs)
    Write-Host "Text to WAV conversion complete for all files."
}

function FormatOutputFileName {
    param(
        [int]$Index,
        $file
    )
    # Format the new filename with the zero-padded index
    $inputFilePath = $file.FullName
    $formattedIndex = "{0:D3}" -f $realIndex
    $trackName = GetTrackName -inputFilePath $inputFilePath
    $OutputFileName = "$formattedIndex - $trackName"
    
    return $OutputFileName
}

function ManageConcurrentJobs {
    param(
        [ref]$Jobs
    )
    if ($jobs.Count -ge $Global:maxConcurrentJobs) {
        $completedJobs = Wait-Job -Job $jobs -Any
        Remove-Job -Job $completedJobs -Force
        $jobs = $jobs | Where-Object { $_.State -eq 'Running' }
    }
}

function StartConversionJob {
    param(
        [string]$InputFilePath,
        [string]$OutputFilePath,
        [string]$OutputFileName,
        [string]$LogFilePath,
        [ref]$Jobs
    )

    $ScriptBlock = {
        param(
            $inputFilePath,
            $outputFilePath,
            $outputFileName,
            $voiceName, 
            $voiceRate, 
            $voiceVolume, 
            $overwriteExisting, 
            $logFilePath,
            $estimatedDurationPerCharacter
        )

        # Check if output file exists
        $outputFilePathWAV = "$outputFilePath.wav"
        if (-not $overwriteExisting -and (Test-Path -Path $outputFilePathWAV)) {
            "Output file already exists. Skipping..." | Out-File -Append -FilePath $logFilePath
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
            $textContent = Get-Content -Path $inputFilePath -Raw -Encoding UTF8
            "Start speech synthesis for: $inputFilePath" | Out-File -FilePath $logFilePath -Append
            $synthesizer.SetOutputToWaveFile($outputFilePathWAV)

            
            # Start a stopwatch to estimate progress
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $synthesizer.SpeakAsync($textContent) # Use Speak to wait for completion
            
            $totalTextLength = $TextContent.Length
            "totalTextLength : $totalTextLength" | Out-File -FilePath $logFilePath -Append
            $estimatedTotalDuration = $totalTextLength * $estimatedDurationPerCharacter

            # Ensure estimatedTotalDuration is reasonable to avoid division by zero
            if ($estimatedTotalDuration -le 0) {
                $estimatedTotalDuration = 1 # Set to a minimal positive value to avoid division by zero
            }
            "estimatedTotalDuration : $estimatedTotalDuration" | Out-File -FilePath $logFilePath -Append

            while ($Synthesizer.State -eq [System.Speech.Synthesis.SynthesizerState]::Speaking) {
                Start-Sleep -Seconds 5
                $elapsedMilliseconds = $Stopwatch.Elapsed.TotalMilliseconds
                "elapsedMilliseconds : $elapsedMilliseconds" | Out-File -FilePath $logFilePath -Append
                $estimatedProgress = [math]::Min(100, ($elapsedMilliseconds / $estimatedTotalDuration) * 100)
                $intEstimatedProgress = [math]::Round($estimatedProgress) -as [int]
                "'$OutputFileName' progress: $intEstimatedProgress%" | Out-File -FilePath $logFilePath -Append
            }

            "Text-to-speech conversion completed for: $inputFilePath" | Out-File -FilePath $logFilePath -Append
        } catch {
            $errorDetails = $_ | Out-String
            "Error processing the file: $inputFilePath. Error Details: $errorDetails" | Out-File -FilePath $logFilePath -Append
        } finally {
                # Wait for the synthesizer to complete speaking
                do {
                    Start-Sleep -Milliseconds 100
                } while ($synthesizer.State -eq [System.Speech.Synthesis.SynthesizerState]::Speaking)

                # Ensure the synthesizer is reset to the default audio device and properly disposed
                $synthesizer.SetOutputToDefaultAudioDevice()
                $synthesizer.Dispose()

                # Check if the stopwatch has been initialized and is running before stopping it
                if ($null -ne $stopwatch) {
                    $stopwatch.Stop()
                }

                # Wait until the .wav file is valid (example of checking if writing to the file has likely completed)
                $previousSize = 0
                $currentSize = (Get-Item $wavOutputPath).Length
                do {
                    Start-Sleep -Seconds 2
                    $previousSize = $currentSize
                    $currentSize = (Get-Item $wavOutputPath).Length
                } while ($currentSize -ne $previousSize)

                # Additional validation for .wav file could be performed here, such as using an external tool or library
                "The .wav file at '$wavOutputPath' appears to be complete." | Out-File -FilePath $logFilePath -Append
        }
    }

    # Script block for conversion job omitted for brevity, assuming it follows similar structure to the original
    $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList (
        $InputFilePath, 
        $OutputFilePath,
        $OutputFileName,
        $Global:voiceName, 
        $Global:voiceRate, 
        $Global:voiceVolume, 
        $Global:overwriteExisting, 
        $LogFilePath,
        $Global:estimatedDurationPerCharacter
    )

    $Jobs.Value += $job
    Write-Host "Conversion job started for file: $(Split-Path -Leaf $InputFilePath)"

    return $job
}

function MonitorJobProgress {
    param(
        [System.Management.Automation.Job[]]$Jobs,
        [System.IO.FileInfo[]]$outputFileNames
    )

    $jobStates = @{} # Hashtable to track job completion state
    $jobsCompleted = 0

    # Initialize job state tracking
    foreach ($job in $Jobs) {
        $jobStates[$job.Id] = $false # False indicates job is not yet completed
    }

    # Continuously monitor job progress
    while ($jobsCompleted -lt $Jobs.Count) {
        foreach ($job in $Jobs) {
            # Skip this iteration if job is already completed
            if ($jobStates[$job.Id]) {
                continue
            }

            $index = [Array]::IndexOf($Jobs, $job)

            $outputFileName = $outputFileNames[$index]
            $outputFilePath = Join-Path -Path $OutputFolderPath -ChildPath $outputFileName
            $logFilePath = "$outputFilePath.log"

            # Check if job is completed
            if ($job.JobStateInfo.State -eq 'Completed') {
                Write-Host "Completed processing: $OutputFileName"
                $jobStates[$job.Id] = $true # Mark job as completed
                $jobsCompleted++
            } elseif (Test-Path -Path $logFilePath) {
                $logContent = Get-Content -Path $logFilePath -Tail 10 # Read the last 10 lines for efficiency
                $latestProgress = $logContent | Where-Object { $_ -match " progress: " } | Select-Object -Last 1
                if ($latestProgress) {
                    Write-Host $latestProgress
                }
            }
        }
        Start-Sleep -Seconds 5 # Delay before the next check
    }
}

function WaitForJobsCompletion {
    param([System.Management.Automation.Job[]]$Jobs)
    foreach ($job in $Jobs) {
        $job | Wait-Job
        HandleJobResult -Job $job
        $job | Remove-Job
    }
    Write-Host "All conversion jobs have been processed."
}

function HandleJobResult {
    param([System.Management.Automation.Job]$Job)
    if ($Job.State -eq "Failed") {
        Write-Host "Job $($Job.Id) failed. Error details: $($Job.ChildJobs[0].JobStateInfo.Reason)"
    } else {
        Write-Host "Job $($Job.Id) completed successfully."
    }
}

function ConvertTxtToMP3AndEdit {
    param(
        [string]$inputFolderPath,
        [string]$outputFolderPath
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
        ConvertTxtToWAV -InputFolderPath $inputFolderPath -OutputFolderPath $outputFolderPath
        
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