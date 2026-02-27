#!/usr/bin/env python3
"""
Advanced script to remove ALL snackbar-related code from Dart files.
Uses proper bracket matching to handle multi-line structures.
"""

import re
import os
from pathlib import Path

def find_matching_bracket(text, start_pos, open_bracket='(', close_bracket=')'):
    """Find the position of the closing bracket"""
    count = 1
    i = start_pos + 1
    while i < len(text) and count > 0:
        if text[i] == open_bracket:
            count += 1
        elif text[i] == close_bracket:
            count -= 1
        i += 1
    return i - 1 if count == 0 else -1

def remove_snackbar_with_bracket_matching(content):
    """Remove ScaffoldMessenger snackbar calls using proper bracket matching"""
    
    while True:
        # Find ScaffoldMessenger.of(context).showSnackBar(
        match = re.search(r'ScaffoldMessenger\.of\s*\(\s*context\s*\)\.showSnackBar\s*\(', content)
        if not match:
            break
        
        # Find the starting position of the opening parenthesis
        start = match.end() - 1  # Position of opening paren after showSnackBar
        
        # Find matching closing parenthesis
        end = find_matching_bracket(content, start, '(', ')')
        if end == -1:
            break
        
        # Remove the entire statement (including trailing semicolon if present)
        removal_end = end + 1
        if removal_end < len(content) and content[removal_end] == ';':
            removal_end += 1
        
        # Also remove leading whitespace/newlines before the statement
        removal_start = match.start()
        while removal_start > 0 and content[removal_start - 1] in ' \t':
            removal_start -= 1
        
        # Remove trailing newline if present
        if removal_end < len(content) and content[removal_end] == '\n':
            removal_end += 1
        
        content = content[:removal_start] + content[removal_end:]
    
    return content

def remove_snackbar_hideCurrentSnackBar(content):
    """Remove hideCurrentSnackBar calls"""
    pattern = r'\s*ScaffoldMessenger\.of\s*\(\s*context\s*\)\.hideCurrentSnackBar\s*\(\s*\)\s*;\n?'
    content = re.sub(pattern, '', content)
    return content

def remove_snackbar_helper_calls(content):
    """Remove show*Snackbar helper calls"""
    
    patterns = [
        # showSuccessSnackbar(context, message, role: ...)
        r'\s*showSuccessSnackbar\s*\(\s*context\s*,[^)]+,[^)]*\)\s*;\n?',
        # showErrorSnackbar(context, message, role: ...)
        r'\s*showErrorSnackbar\s*\(\s*context\s*,[^)]+,[^)]*\)\s*;\n?',
        # _showErrorSnackBar(message)
        r'\s*_showErrorSnackBar\s*\([^)]*\)\s*;\n?',
    ]
    
    for pattern in patterns:
        content = re.sub(pattern, '', content, flags=re.DOTALL)
    
    return content

def remove_snackbar_method_definitions(content):
    """Remove snackbar method definitions"""
    
    # void _showErrorSnackBar(String message) { ... }
    pattern = r'\n\s*void\s+_showErrorSnackBar\s*\(\s*String\s+message\s*\)\s*\{[^}]*\}\n?'
    content = re.sub(pattern, '\n', content, flags=re.DOTALL)
    
    return content

def cleanup_empty_structures(content):
    """Clean up empty blocks and excessive whitespace left after removal"""
    
    # Remove catch blocks that are now empty or only have closing braces
    pattern = r'catch\s*\([^)]*\)\s*\{\s*\}'
    content = re.sub(pattern, '', content)
    
    # Remove if (mounted) { } blocks that are now empty
    pattern = r'if\s*\(\s*mounted\s*\)\s*\{\s*\}'
    content = re.sub(pattern, '', content)
    
    # Excessive newlines
    content = re.sub(r'\n\s*\n\s*\n+', '\n\n', content)
    
    # Trailing whitespace on lines
    lines = content.split('\n')
    lines = [line.rstrip() for line in lines]
    content = '\n'.join(lines)
    
    return content

def process_file(filepath):
    """Process a single Dart file to remove snackbars"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        
        # Apply all removal patterns
        content = remove_snackbar_with_bracket_matching(content)
        content = remove_snackbar_hideCurrentSnackBar(content)
        content = remove_snackbar_helper_calls(content)
        content = remove_snackbar_method_definitions(content)
        content = cleanup_empty_structures(content)
        
        # Only write if changes were made
        if content != original_content:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(content)
            return True
        
        return False
    
    except Exception as e:
        print(f"Error processing {filepath}: {e}")
        return False

def main():
    """Main function to process all Dart files"""
    
    lib_path = Path('/home/manoj/Desktop/new_reward/lib')
    dart_files = list(lib_path.rglob('*.dart'))
    
    print(f"Found {len(dart_files)} Dart files")
    
    processed = 0
    modified = 0
    
    for filepath in dart_files:
        processed += 1
        if process_file(filepath):
            modified += 1
            rel_path = filepath.relative_to(lib_path.parent)
            print(f"✓ {rel_path}")
    
    print(f"\nProcessed: {processed} files")
    print(f"Modified: {modified} files")

if __name__ == '__main__':
    main()
