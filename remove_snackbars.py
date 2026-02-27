#!/usr/bin/env python3
"""
Script to remove all snackbar-related code from Dart files.
This removes ScaffoldMessenger calls, SnackBar widgets, and showSnackbar helper calls.
"""

import re
import os
from pathlib import Path

def remove_snackbar_calls(content):
    """Remove ScaffoldMessenger.of(context).showSnackBar(...) blocks"""
    
    # Pattern 1: ScaffoldMessenger.of(context).showSnackBar(const SnackBar(...))
    pattern1 = r'ScaffoldMessenger\.of\s*\(\s*context\s*\)\.showSnackBar\s*\(\s*const\s+SnackBar\s*\(\s*content:\s*Text\s*\([^)]*\)\s*[,\s]*[^)]*\)\s*\);'
    content = re.sub(pattern1, '', content, flags=re.DOTALL)
    
    # Pattern 2: ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))
    pattern2 = r'ScaffoldMessenger\.of\s*\(\s*context\s*\)\.showSnackBar\s*\(\s*SnackBar\s*\([^)]*\)\s*\);'
    content = re.sub(pattern2, '', content, flags=re.DOTALL)
    
    # Pattern 3: Multi-line ScaffoldMessenger calls with SnackBar
    pattern3 = r'ScaffoldMessenger\.of\s*\(\s*context\s*\)\.showSnackBar\s*\(\s*(?:const\s+)?SnackBar\s*\([^}]*?\)\s*\)\s*;'
    content = re.sub(pattern3, '', content, flags=re.DOTALL)
    
    # Pattern 4: hideCurrentSnackBar calls
    pattern4 = r'ScaffoldMessenger\.of\s*\(\s*context\s*\)\.hideCurrentSnackBar\s*\(\s*\)\s*;'
    content = re.sub(pattern4, '', content, flags=re.DOTALL)
    
    return content

def remove_snackbar_helpers(content):
    """Remove showSnackbar and showErrorSnackbar helper calls"""
    
    # Pattern: showSuccessSnackbar(context, ..., role: ...)
    pattern1 = r'showSuccessSnackbar\s*\(\s*context\s*,\s*[^)]+\s*,\s*role:\s*[^)]+\s*\)\s*;'
    content = re.sub(pattern1, '', content, flags=re.DOTALL)
    
    # Pattern: showErrorSnackbar(context, ..., role: ...)
    pattern2 = r'showErrorSnackbar\s*\(\s*context\s*,\s*[^)]+\s*,\s*role:\s*[^)]+\s*\)\s*;'
    content = re.sub(pattern2, '', content, flags=re.DOTALL)
    
    # Pattern: _showErrorSnackBar(...)
    pattern3 = r'_showErrorSnackBar\s*\([^)]+\)\s*;'
    content = re.sub(pattern3, '', content)
    
    return content

def remove_empty_blocks(content):
    """Remove empty catch/if blocks left after snackbar removal"""
    
    # Remove empty catch blocks
    pattern1 = r'catch\s*\([^)]*\)\s*\{\s*\}'
    content = re.sub(pattern1, '', content)
    
    # Remove empty if blocks with just snackbar
    pattern2 = r'if\s*\(\s*mounted\s*\)\s*\{\s*\}'
    content = re.sub(pattern2, '', content)
    
    # Clean up excessive whitespace
    content = re.sub(r'\n\s*\n\s*\n', '\n\n', content)
    
    return content

def remove_snackbar_method_definitions(content):
    """Remove _showErrorSnackBar method definitions"""
    
    # Remove void _showErrorSnackBar(String message) { ... }
    pattern = r'void\s+_showErrorSnackBar\s*\([^)]*\)\s*\{[^}]*showErrorSnackbar[^}]*\}'
    content = re.sub(pattern, '', content, flags=re.DOTALL)
    
    return content

def process_file(filepath):
    """Process a single Dart file to remove snackbars"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        
        # Apply all removal patterns
        content = remove_snackbar_calls(content)
        content = remove_snackbar_helpers(content)
        content = remove_snackbar_method_definitions(content)
        content = remove_empty_blocks(content)
        
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
            print(f"Modified: {filepath.relative_to(lib_path.parent)}")
    
    print(f"\nProcessed: {processed} files")
    print(f"Modified: {modified} files")

if __name__ == '__main__':
    main()
