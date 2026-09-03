#!/usr/bin/env python3
"""Structural checks for the tima_one Dart sources.

This sandbox cannot install the Flutter SDK, so `flutter analyze` is
unavailable here. These checks are a partial substitute: they validate
bracket/string balance, reference resolution against the design-system
classes, and import completeness.

They do NOT type-check and do NOT know real Flutter APIs, so they cannot
catch things like a wrong named parameter on a framework widget. Always
run `flutter analyze` on a machine with the SDK before shipping.

Usage:  python3 tool/checks/check.py
"""
import os
import re
import sys
import glob

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIB = os.path.join(ROOT, 'lib')


def dart_files():
    return sorted(glob.glob(os.path.join(LIB, '**', '*.dart'), recursive=True))


def rel(p):
    return os.path.relpath(p, ROOT)


def strip_code(src):
    """Yield (char, line) for code positions only, skipping comments/strings."""
    out = []
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
            i += 1
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
                if src[i] == '\n':
                    line += 1
                i += 1
            i += 2
            continue
        if c == 'r' and i + 1 < n and src[i + 1] in '\'"':
            i += 1
            continue
        if src[i:i + 3] in ("'''", '"""'):
            tq = src[i:i + 3]
            i += 3
            while i < n and src[i:i + 3] != tq:
                if src[i] == '\n':
                    line += 1
                if src[i] == '\\':
                    i += 1
                i += 1
            i += 3
            continue
        if c in '\'"':
            q = c
            i += 1
            depth = 0
            while i < n:
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] == '$' and i + 1 < n and src[i + 1] == '{':
                    depth += 1
                    i += 2
                    continue
                if depth and src[i] == '}':
                    depth -= 1
                    i += 1
                    continue
                if depth:
                    out.append((src[i], line))
                    i += 1
                    continue
                if src[i] == q:
                    break
                if src[i] == '\n':
                    line += 1
                    break
                i += 1
            i += 1
            continue
        out.append((c, line))
        i += 1
    return out


def check_brackets():
    pairs = {')': '(', ']': '[', '}': '{'}
    errs = []
    for f in dart_files():
        src = open(f, encoding='utf-8').read()
        stack = []
        for c, line in strip_code(src):
            if c in '([{':
                stack.append((c, line))
            elif c in ')]}':
                if not stack:
                    errs.append(f'{rel(f)}:{line}: stray {c}')
                elif stack[-1][0] != pairs[c]:
                    o, ol = stack.pop()
                    errs.append(f'{rel(f)}:{line}: {c} closes {o} from line {ol}')
                else:
                    stack.pop()
        for o, ol in stack:
            errs.append(f'{rel(f)}:{ol}: unclosed {o}')
    return errs, f'{len(dart_files())} files structurally valid'


DESIGN_CLASSES = {
    'AppColors': 'lib/core/theme/app_colors.dart',
    'AppDims': 'lib/core/theme/app_theme.dart',
    'AppTheme': 'lib/core/theme/app_theme.dart',
    'AppUi': 'lib/presentation/widgets/app_ui.dart',
}


def members_of(cls, path):
    src = open(os.path.join(ROOT, path), encoding='utf-8').read()
    m = re.search(r'(?:abstract\s+)?class %s\b' % cls, src)
    if not m:
        return set()
    body = src[m.end():]
    nxt = re.search(r'\n(?:abstract\s+)?class ', body)
    if nxt:
        body = body[:nxt.start()]
    names = set(re.findall(
        r'static\s+(?:const\s+|final\s+)?[\w<>,\s\?\[\]]+?\s+(\w+)\s*[=(;]', body))
    names |= set(re.findall(r'static\s+\w[\w<>,\s\?\[\]]*\s+(\w+)\s*\(', body))
    return names


def check_symbols():
    defs = {c: members_of(c, p) for c, p in DESIGN_CLASSES.items()}
    errs = []
    for f in dart_files():
        if f.endswith('.g.dart'):
            continue
        for ln, line in enumerate(open(f, encoding='utf-8'), 1):
            code = re.sub(r'//.*', '', line)
            for cls, known in defs.items():
                for mem in re.findall(r'\b%s\.(\w+)' % cls, code):
                    if mem.startswith('_'):
                        continue
                    if mem not in known:
                        errs.append(f'{rel(f)}:{ln}: unknown {cls}.{mem}')
    total = sum(len(v) for v in defs.values())
    return errs, f'all references resolve ({total} members known)'


def imports_of(f):
    src = open(f, encoding='utf-8').read()
    out = set()
    for m in re.findall(r"import\s+'([^']+)'", src):
        if m.startswith('dart:') or m.startswith('package:flutter'):
            continue
        if m.startswith('package:tima_one/'):
            out.add(os.path.join(ROOT, 'lib', m[len('package:tima_one/'):]))
        elif not m.startswith('package:'):
            out.add(os.path.normpath(os.path.join(os.path.dirname(f), m)))
    for m in re.findall(r"part\s+'([^']+)'", src):
        out.add(os.path.normpath(os.path.join(os.path.dirname(f), m)))
    return out


def closure(f, seen=None):
    if seen is None:
        seen = set()
    for d in imports_of(f):
        if d in seen or not os.path.exists(d):
            continue
        seen.add(d)
        closure(d, seen)
    return seen


def check_imports():
    errs = []
    for f in dart_files():
        if f.endswith('.g.dart'):
            continue
        src = open(f, encoding='utf-8').read()
        reach = closure(f) | {f}
        po = re.search(r"part of\s+'([^']+)'", src)
        if po:
            parent = os.path.normpath(os.path.join(os.path.dirname(f), po.group(1)))
            reach |= closure(parent) | {parent}
        for cls, path in DESIGN_CLASSES.items():
            full = os.path.join(ROOT, path)
            if re.search(r'\b%s\.' % cls, src) and full not in reach:
                errs.append(f'{rel(f)}: uses {cls} but does not import {path}')
    return errs, f'imports satisfy all {len(dart_files())} files'


def check_conventions():
    """Guard the specific mistakes that broke the Windows build before."""
    errs = []
    for f in dart_files():
        for ln, line in enumerate(open(f, encoding='utf-8'), 1):
            if 'PdfAppColors' in line:
                errs.append(f'{rel(f)}:{ln}: PdfAppColors is not a real class '
                            f'(pdf package uses PdfColors)')
            if re.search(r'\bwithOpacity\(', line):
                errs.append(f'{rel(f)}:{ln}: withOpacity is deprecated, '
                            f'use withValues(alpha:)')
    # DropdownButtonFormField takes `value:`, not `initialValue:`
    for f in dart_files():
        src = open(f, encoding='utf-8').read()
        for m in re.finditer(r'DropdownButtonFormField<[^>]*>\((?:[^()]|\([^()]*\))*?'
                             r'\binitialValue\s*:', src):
            ln = src[:m.start()].count('\n') + 1
            errs.append(f'{rel(f)}:{ln}: DropdownButtonFormField uses '
                        f'value:, not initialValue:')
    return errs, 'no known-bad API patterns'


def main():
    checks = [
        ('brackets', check_brackets),
        ('symbols', check_symbols),
        ('imports', check_imports),
        ('conventions', check_conventions),
    ]
    failed = False
    for name, fn in checks:
        errs, ok = fn()
        if errs:
            failed = True
            print(f'FAIL [{name}]')
            for e in errs:
                print(f'  {e}')
        else:
            print(f'OK   [{name}] {ok}')
    if failed:
        sys.exit(1)
    print('\nReminder: this is not a compiler. Run `flutter analyze` before shipping.')


if __name__ == '__main__':
    main()
