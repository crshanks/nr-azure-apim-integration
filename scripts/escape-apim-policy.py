#!/usr/bin/env python3
"""
Renders apim-policy.xml.tpl and escapes C# expression syntax for ARM API
compatibility, writing the result to demo/bicep/apim-policy-escaped.xml.

ARM's XML parser rejects unescaped double quotes and angle brackets inside
XML attribute values (e.g. C# generics like GetValueOrDefault<string>() and
string literals like ContainsKey("key")). This script escapes them as &quot;
and &lt;/&gt; within @(...) and @{...} expressions only, leaving the rest of
the XML untouched.

Run from the repo root whenever apim-policy.xml.tpl changes or the logger/
backend names are updated:

    python3 scripts/escape-apim-policy.py

Optional overrides (defaults match the standard deployment):
    python3 scripts/escape-apim-policy.py \\
        --logger-id apim-eventhub-logger \\
        --backend-id mock-backend \\
        --output demo/bicep/apim-policy-escaped.xml
"""

import argparse
import pathlib


def escape_csharp_expressions(xml: str) -> str:
    """Escape double quotes and angle brackets inside C# @(...) and @{...} blocks."""
    result = []
    i = 0
    while i < len(xml):
        if xml[i:i+2] in ('@(', '@{'):
            delim = ')' if xml[i+1] == '(' else '}'
            open_char = xml[i+1]
            result.append(xml[i:i+2])
            i += 2
            depth = 1
            while i < len(xml) and depth > 0:
                c = xml[i]
                if c == open_char:
                    depth += 1
                    result.append(c)
                elif c == delim:
                    depth -= 1
                    result.append(c)
                elif c == '"':
                    result.append('&quot;')
                elif c == '<':
                    result.append('&lt;')
                elif c == '>':
                    result.append('&gt;')
                else:
                    result.append(c)
                i += 1
        else:
            result.append(xml[i])
            i += 1
    return ''.join(result)


def main():
    repo_root = pathlib.Path(__file__).parent.parent

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--logger-id',  default='apim-eventhub-logger')
    parser.add_argument('--backend-id', default='mock-backend')
    parser.add_argument('--output',     default='demo/bicep/apim-policy-escaped.xml')
    args = parser.parse_args()

    template = (repo_root / 'apim-policy.xml.tpl').read_text()
    rendered = template.replace('${logger_id}', args.logger_id)
    rendered = rendered.replace('${backend_id}', args.backend_id)
    escaped  = escape_csharp_expressions(rendered)

    output_path = repo_root / args.output
    output_path.write_text(escaped)
    print(f'Written: {output_path}')


if __name__ == '__main__':
    main()
