import sys
import os
import re
import shutil
import ebooklib
from ebooklib import epub
from bs4 import BeautifulSoup
import json

# Set base directory path and dictionary files
BASE_PATH = os.path.dirname(os.path.abspath(__file__))
setup_file_path = os.path.join(BASE_PATH, 'setup.json')

# Load setup.json content
def load_setup(): # Adjust the path as necessary
    with open(setup_file_path, 'r', encoding='utf-8') as file:
        setup_data = json.load(file)
    return setup_data

# Example usage
setup_data = load_setup()

# Accessing the values
dictionary = setup_data['dictionary']
dictionary_path = os.path.join(BASE_PATH, "dictionaries", dictionary)
default_ebook_path = setup_data['default_ebook_path']

# Constants for cleaning the content
DEST_FOLDER_BASE = "extracted_chapters"
NON_CONTENT_PATTERNS = [
    r'xml version=\'1\.0\' encodage=\'utf\-8\'\?',  # Corrected to match your requirement
    r'@page\s*\{[^\}]*\}',  # @page CSS blocks
    r'body\s*\{[^\}]*\}',  # body CSS blocks
]

# Mapping of unsupported characters
UNSUPPORTED_CHARS_MAP = {
    '\u03c6': 'phi', '\u03c0': 'pi', '\u03bc': 'mu', '\u03b5': 'epsilon',
    '\u2032': "'", '\u2044': '/', '\u03b7': 'eta', '½': '1/2', '⅓': '1/3',
    '⅔': '2/3', '¼': '1/4', '¾': '3/4',
}

def load_dictionary():
    """Loads replacement patterns from the first .dic file found."""
    dic_content = []
    if dictionary_path:
        with open(dictionary_path, 'r', encoding='utf-8') as file:
            for line in file:
                parts = line.strip().split('=', 1)
                if len(parts) == 2:
                    dic_content.append(tuple(map(str.strip, parts)))  
    return dic_content

def sanitize_text(soup, dic_replacements):
    """Sanitizes text by removing unwanted patterns, URLs, and paths, and applying dictionary replacements."""
    text = clean_html_content(soup)
    text = remove_text_in_brackets(text)
    text = remove_urls_and_paths(text)
    text = apply_dictionary_replacements(text, dic_replacements)
    text = clean_unsupported_chars(text, UNSUPPORTED_CHARS_MAP)
    
    # Verify if text contains only special chars or whitespace, if yes, clear text content
    if not re.search(r'[^\s\[\.\]:\n\r]', text):
        text = ""
    return text

def clean_html_content(soup):
    """Cleans HTML content and extracts text."""
    for tag in soup(["script", "style", "head", "title", "meta", "link"]):
        tag.decompose()
    for br in soup.find_all("br"):
        br.replace_with(",\n")
    for p in soup.find_all("p"):
        p.append(":\n")
    text = soup.get_text(separator='\n', strip=True)
    
    for pattern in NON_CONTENT_PATTERNS:
        text = re.sub(pattern, '', text, flags=re.MULTILINE)
    
    return text.strip()

def apply_dictionary_replacements(text, replacements):
    if not text:
        return text
    
    """Applies dictionary replacements to the given text."""
    for pattern, replacement in replacements:
        python_compatible_replacement = replacement.replace("$", "\\")
        text = re.sub(pattern, python_compatible_replacement, text)
    
    return text

def remove_text_in_brackets(text):
    if not text:
        return text
    
    """Removes text within curly and square brackets."""
    return re.sub(r'\{[^}]*\}|\[[^\]]*\]', '', text)

def remove_urls_and_paths(text):
    if not text:
        return text
    
    """Removes URLs and file paths from text."""
    text = re.sub(r'https?://\S+|www\.\S+', '', text)
    text = re.sub(r'[a-zA-Z]:\\[^\s]+', '', text)
    text = re.sub(r'\/[^\s]+', '', text)
    return text

def clean_unsupported_chars(text, chars_map):
    """Replaces unsupported Unicode characters in text."""
    for unicode_char, replacement in chars_map.items():
        text = text.replace(unicode_char, replacement)
    return text

def get_title_suffix(soup):
    body_content = soup.find('body')
    if body_content:
        for child in body_content.descendants:
            if child.name and child.get_text().strip():
                text_content = next(child.stripped_strings, None)
                if text_content:
                    text = text_content[:50]
                    text = text.strip().replace(':', ' -').replace('?', '').replace('/', '-').replace('\\', '-')
                    return " - " + text
    return ""

def process_document(item, dest_folder, real_index, dic_replacements):
    if item.get_type() == ebooklib.ITEM_DOCUMENT:
        soup = BeautifulSoup(item.content, 'html.parser')
        title_suffix = get_title_suffix(soup)
        formatted_filename = f"{real_index:03d}{title_suffix}.txt"
        
        clean_text = sanitize_text(soup, dic_replacements)
        if clean_text:
            text_filename = os.path.join(dest_folder, formatted_filename)
            try:
                with open(text_filename, 'w', encoding='cp1252') as text_file:
                    text_file.write(clean_text)
            except UnicodeEncodeError as e:
                print(f"Encoding error encountered: {e}. Retrying with errors='ignore'.")
                with open(text_filename, 'w', encoding='cp1252', errors='ignore') as text_file:
                    text_file.write(clean_text)
            print(f"Saved text: {text_filename}")
            return 1
    return 0

def extract_and_save_chapters(epub_filepath):
    """Extracts chapters from an EPUB file and saves them as separate text files."""
    book = epub.read_epub(epub_filepath)
    base_name = os.path.splitext(os.path.basename(epub_filepath))[0]
    dest_folder = os.path.join(BASE_PATH, DEST_FOLDER_BASE, base_name)
    if os.path.exists(dest_folder):
        shutil.rmtree(dest_folder)
    os.makedirs(dest_folder)
    
    dic_replacements = load_dictionary()
    real_index = 1
    for item in book.get_items():
        real_index += process_document(item, dest_folder, real_index, dic_replacements)


if __name__ == "__main__":
    epub_filepath = sys.argv[1] if len(sys.argv) > 1 else None
    if default_ebook_path:
        epub_filepath = default_ebook_path
    if epub_filepath:
        extract_and_save_chapters(epub_filepath)
    else:
        print("Usage: python script.py <path_to_epub_file>")
        input("Press Enter to continue...")
