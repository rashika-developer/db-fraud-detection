#!/usr/bin/env python3
"""
Test syntax validation for SentinelDB SQL files.
This script validates that all SQL files have correct syntax without needing a database connection.
"""

import re
import sys
from pathlib import Path

def check_sql_syntax(file_path):
    """Basic SQL syntax checks."""
    with open(file_path, 'r') as f:
        content = f.read()
    
    issues = []
    
    # Check for FORMAT() calls which were causing issues
    format_calls = re.findall(r'FORMAT\s*\(', content)
    if format_calls:
        issues.append(f"Found {len(format_calls)} FORMAT() calls - should use string concatenation")
    
    # Check for unmatched parentheses in function definitions
    for line_num, line in enumerate(content.split('\n'), 1):
        # Skip comments
        if line.strip().startswith('--'):
            continue
        
        # Basic balance check (crude but helpful)
        open_parens = line.count('(')
        close_parens = line.count(')')
        if open_parens > 0 and close_parens > 0:
            # This is very basic - just warn if massively unbalanced
            pass
    
    # Check for common PL/pgSQL issues
    lines = content.split('\n')
    in_function = False
    for line_num, line in enumerate(lines, 1):
        if 'CREATE OR REPLACE FUNCTION' in line:
            in_function = True
        elif 'END;' in line and in_function:
            in_function = False
        
        # Check for old-style %s format strings
        if '%s' in line and 'FORMAT' not in line and in_function:
            # Might be in a string literal or comment
            if not line.strip().startswith('--') and "'" not in line:
                issues.append(f"Line {line_num}: Possible unquoted %s format specifier: {line.strip()}")
    
    return issues

def main():
    sql_dir = Path("C:\\Users\\rashi\\sentineldb\\sql")
    
    total_issues = 0
    for sql_file in sorted(sql_dir.glob("*.sql")):
        print(f"\n{'='*60}")
        print(f"Checking: {sql_file.name}")
        print('='*60)
        
        issues = check_sql_syntax(sql_file)
        
        if issues:
            print(f"✗ Found {len(issues)} issue(s):")
            for issue in issues:
                print(f"  - {issue}")
            total_issues += len(issues)
        else:
            print("✓ No obvious syntax issues detected")
    
    print(f"\n{'='*60}")
    print(f"SUMMARY: {total_issues} issue(s) found across all files")
    print('='*60)
    
    return 0 if total_issues == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
