import re
import os

# Used for Balabolka dictionary conversion

BASE_PATH = os.path.dirname(os.path.abspath(__file__))
# Set input and output file paths
input_file_path = r"any.bxd"
output_file_path = os.path.join(BASE_PATH, f"new.dic")

def extract_delimiter(input_text):
    match = re.search(r'Version=1\nDelimiter=(.)\n', input_text)
    if match:
        return match.group(1)  # Extract the character matched within the parentheses
    else:
        return ""  # or some default value if the delimiter is not found


def read_input_file(input_file_path):
    with open(input_file_path, 'r', encoding='utf-8') as file:
        return file.read()

def write_output_file(output_file_path, content):
    # Ensure the directory exists
    os.makedirs(os.path.dirname(output_file_path), exist_ok=True)
    
    # Write content to the file
    with open(output_file_path, 'w', encoding='utf-8') as file:
        file.write(content)

def transform_data(input_text):
    delimiter = extract_delimiter(input_text)
    
    # Remove the header
    input_text = re.sub(r'Version=1\nDelimiter=.\n..\n', '', input_text, flags=re.MULTILINE)
    
    # Transform each line
    transformed_lines = []
    lines = input_text.split('\n')
    for line in lines:
        parts = line.split(delimiter)
        print("parts:")
        print(parts)
        if len(parts) >= 5:
            # Assuming the transformation logic is to take last 3 parts, ignoring leading empty elements if any
            pattern, replacement = parts[-3], parts[-2] + parts[-1]
            # Remove the delimiter from the start and end if present
            pattern = pattern.strip(delimiter)
            replacement = replacement.strip(delimiter).replace(delimiter, '= ')
            transformed_line = f"{pattern}= {replacement}"
            transformed_lines.append(transformed_line)
    
    return '\n'.join(transformed_lines)
 
# Read the input file
input_text = read_input_file(input_file_path)

# Transform the data
transformed_data = transform_data(input_text)

# Print or save the transformed data
print("transformed_data:")
print(transformed_data)

# Save the transformed data to the output file
write_output_file(output_file_path, transformed_data)

print("Transformation complete.")
