#!/usr/bin/env python3
"""
Script to wrap all unguarded debugPrint calls with kDebugMode guards.
Usage: python wrap_debug_prints.py <file_path>
"""

import sys
import re

def wrap_debug_prints(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    lines = content.split('\n')
    modified_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        
        # Check if this line starts a debugPrint call
        # Match lines like: "      debugPrint('[TAG] message');"
        # or multi-line: "      debugPrint("
        indent_match = re.match(r'^(\s*)debugPrint\(', line)
        
        if indent_match:
            indent = indent_match.group(1)
            
            # Check if already wrapped (look at previous lines)
            already_wrapped = False
            if i > 0:
                prev_line = lines[i-1].strip()
                if prev_line.startswith('if (kDebugMode)') or prev_line.startswith('assert('):
                    already_wrapped = True
            
            if already_wrapped:
                modified_lines.append(line)
                i += 1
                continue
            
            # Find the complete debugPrint call (could be multi-line)
            debugprint_lines = [line]
            paren_count = line.count('(') - line.count(')')
            j = i + 1
            
            while paren_count > 0 and j < len(lines):
                debugprint_lines.append(lines[j])
                paren_count += lines[j].count('(') - lines[j].count(')')
                j += 1
            
            # Wrap with kDebugMode
            modified_lines.append(f"{indent}if (kDebugMode) {{")
            for dp_line in debugprint_lines:
                modified_lines.append(f"  {dp_line}")
            modified_lines.append(f"{indent}}}")
            
            i = j  # Skip the lines we just processed
        else:
            modified_lines.append(line)
            i += 1
    
    # Write back
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(modified_lines))
    
    print(f"✅ Wrapped debugPrint calls in {file_path}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python wrap_debug_prints.py <file_path>")
        sys.exit(1)
    
    wrap_debug_prints(sys.argv[1])
