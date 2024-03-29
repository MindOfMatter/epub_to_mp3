﻿# Clear the screen
Clear-Host

$Global:currentPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# Load setup.json content
$setupJsonPath = Join-Path -Path $Global:currentPath -ChildPath "setup.json"
$setupConfig = Get-Content -Path $setupJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Accessing the values
$Global:defaultLibraryPath = $setupConfig.default_library_path
$Global:ebookPath = $setupConfig.default_ebook_path

$TxtToMp3ScriptPath = "$Global:currentPath\txt_to_mp3.ps1"
. $TxtToMp3ScriptPath

$outputFolderPath = ""

ConvertAllWAVToMP3 -InputFolderPath $outputFolderPath
