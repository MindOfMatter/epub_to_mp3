# Clear the screen
Clear-Host

# Load setup.json content
$setupJsonPath = Join-Path -Path $Global:currentPath -ChildPath "setup.json"
$setupConfig = Get-Content -Path $setupJsonPath -Raw | ConvertFrom-Json

$Global:currentPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

function ConvertEpubToTxt {
    [CmdletBinding()]
    $ebookName = [System.IO.Path]::GetFileNameWithoutExtension($Global:ebookPath)
    $outputTxtFolderPath = Join-Path -Path $Global:currentPath -ChildPath "extracted_chapters\$ebookName"
    & "python" "$Global:currentPath\epub_to_txt_by_chapter.py" $Global:ebookPath
    Write-Host "`nEpub to txt conversion done. Path: $outputTxtFolderPath"
}

function ConvertEpubToTxtAndEdit {
    [CmdletBinding()]

    $skipConversion = Read-Host "Skip the Epub to txt conversion? (Y/N, default: N)"
    if ($skipConversion -ne 'Y' -and $skipConversion -ne 'y') {
        ConvertEpubToTxt
        Start-Sleep -Seconds 2

        Invoke-Item $outputTxtFolderPath
    } else {
        Write-Host "Epub to txt conversion skipped."
    }
}
