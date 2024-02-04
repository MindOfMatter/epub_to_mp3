<div align=center>
<img src="https://github.com/MindOfMatter/epub_to_mp3/blob/main/epub_to_mp3.ico">
</div>

# ePub to MP3 Converter

## Description

This project provides a comprehensive solution for converting ePub files to MP3 format, utilizing text-to-speech technology. It leverages PowerShell scripts for the conversion process and Python for extracting text from ePub files. Ideal for creating audiobooks from eBooks, enhancing accessibility, and enabling content consumption in an audio format.

## Features

- GUI for selecting ePub files
- Extract the text from epub by chapter
- Sanitize preparation for text to speech
- Dictionary customizations
- Customizable text-to-speech settings
- Support for multiple voices and languages
- Automatic cover image embedding into MP3 files
- Playlist creation with all generated MP3 files

## Prerequisites

- Python 3.x
- ebooklib and BeautifulSoup Python library
- ffmpeg
- (SAPI4 or SAPI5) TTS Synthesis Voice Installed

## Apps recommendations

- Calibre app for ebook browser
- Balabolka to test it (in my side, Balabolka is not the best for mp3 convertion part)

## Installation

1. Clone the repository: `git clone <repository-url>`
2. Install required Python libraries: `pip install ebooklib beautifulsoup4`
3. Download and put the ffmpeg.exe in root repo from https://ffmpeg.org/
4. Choose your dictionary (.dic from dictionaries)
5. Customize settings as needed in `setup.json` 
- (when running, you have InstalledVoices.csv generated : it may help to find installed voice name)

## Usage

- `epub_to_mp3.ps1` : convert only one epub to mp3 files by chapter

1. Run `epub_to_mp3.ps1` with PowerShell.
2. Select an ePub file through the GUI.
3. After asked, if you press N or n to skip step (epub to txts and txts to mp3)
4. The script will process the ePub file, convert it to MP3 (WAV while processing), and save it in the specified output directory.

- `epubs_to_mp3.ps1` : convert multiple epubs to mp3 files by chapter

1. Set in `setup.json` the array string epub file paths into `"ebook_paths"`
2. Run `epub_to_mp3.ps1` with PowerShell.
3. After asked, if you press N or n to skip step (epub to txts and txts to mp3)
4. The script will process the ePub file, convert it to MP3 (WAV while processing), and save it in the specified output directory.

## Customizing Voice Settings

Follow the instructions within `epub_to_mp3_resolver.ps1` to fix synthesizer issues or update voice settings.

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your improvements.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
