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


PROJECT_CLASS_RE = re.compile(r'\bclass\s+(\w+)')


def project_classes():
    """Map every project class name to the file that declares it."""
    out = {}
    for f in dart_files():
        if f.endswith('.g.dart'):
            continue
        src = open(f, encoding='utf-8').read()
        for m in PROJECT_CLASS_RE.finditer(src):
            out.setdefault(m.group(1), f)
    return out


def constructor_params(src, cls):
    """Named parameters accepted by any constructor of `cls` (plus inherited)."""
    names = set()
    for m in re.finditer(r'(?:const\s+|factory\s+)?%s\s*(?:\.\w+)?\s*\(' % cls, src):
        i = m.end() - 1
        depth, seg, segs = 0, '', []
        while i < len(src):
            c = src[i]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    segs.append(seg)
                    break
            if depth == 1 and c == ',' and not _in_string(src, i):
                segs.append(seg)
                seg = ''
                i += 1
                continue
            seg += c
            i += 1
        for seg in segs:
            seg = seg.strip()
            for pm in re.finditer(r'(?:required\s+)?(?:this\.|super\.)(\w+)', seg):
                names.add(pm.group(1))
            pm = re.search(
                r'(?:required\s+)?[\w<>,\s\?\.]+?\s(\w+)\s*$', seg)
            if pm and not seg.startswith('this.') and not seg.startswith(
                    'super.'):
                names.add(pm.group(1))
    names.add('key')
    return names


def _in_string(src, idx):
    quote = None
    i = 0
    while i < idx:
        c = src[i]
        if quote:
            if c == '\\':
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in '\'\"':
            quote = c
        i += 1
    return quote is not None


def named_args_at(src, start):
    """Named argument keys of the call whose '(' sits at `start`."""
    i, depth = start, 0
    keys, seg_start = [], start + 1
    out = []
    while i < len(src):
        c = src[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                out.append(src[seg_start:i])
                break
        elif c == ',' and depth == 1 and not _in_string(src, i):
            out.append(src[seg_start:i])
            seg_start = i + 1
        i += 1
    for seg in out:
        m = re.match(r'\s*(\w+)\s*:', seg)
        if m:
            keys.append(m.group(1))
    return keys


def check_widget_params():
    """Every named argument on a project class must be a real parameter."""
    classes = project_classes()
    cache = {}
    errs = []
    for f in dart_files():
        if f.endswith('.g.dart'):
            continue
        src = open(f, encoding='utf-8').read()
        for cls in set(re.findall(r'\b(\w+)\s*\(', src)):
            if cls not in classes:
                continue
            if cls not in cache:
                owner = open(classes[cls], encoding='utf-8').read()
                cache[cls] = constructor_params(owner, cls)
            known = cache[cls]
            for m in re.finditer(r'(?<![\w.])%s\s*\(' % cls, src):
                open_paren = src.index('(', m.end() - 1)
                for arg in named_args_at(src, open_paren):
                    if arg not in known:
                        ln = src[:m.start()].count('\n') + 1
                        errs.append(
                            f'{rel(f)}:{ln}: {cls} has no parameter "{arg}"')
    return errs, f'{len(classes)} project classes checked'


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
            if re.search(r"^import 'dart:typed_data';", line):
                src = open(f, encoding='utf-8').read()
                if "package:flutter/services.dart" in src:
                    errs.append(f'{rel(f)}:{ln}: unnecessary_import — '
                                f'flutter/services already exports dart:typed_data')
    # DropdownButtonFormField takes `value:`, not `initialValue:`
    for f in dart_files():
        src = open(f, encoding='utf-8').read()
        for m in re.finditer(r'DropdownButtonFormField<[^>]*>\((?:[^()]|\([^()]*\))*?'
                             r'\binitialValue\s*:', src):
            ln = src[:m.start()].count('\n') + 1
            errs.append(f'{rel(f)}:{ln}: DropdownButtonFormField uses '
                        f'value:, not initialValue:')
        # A const map cannot have double keys (const_map_key_not_primitive_equality).
        for m in re.finditer(r'\bconst\s*(?:<[^>]*>)?\s*\{', src):
            body = _balanced(src, src.index('{', m.end() - 1))
            if body and re.search(r'(?<![\w.])\d+\.\d*\s*:', body):
                ln = src[:m.start()].count('\n') + 1
                errs.append(f'{rel(f)}:{ln}: const map with a double key is '
                            f'illegal — drop const (const_map_key_not_primitive_equality)')
        # package:intl exports its own TextDirection (LTR/RTL), which shadows
        # dart:ui's (rtl/ltr) and breaks TextDirection.rtl.
        intl = re.search(r"import\s+'package:intl/intl\.dart'([^;]*);", src)
        if intl and 'hide TextDirection' not in intl.group(1):
            for m in re.finditer(r'(?<!pw\.)\bTextDirection\.(rtl|ltr)\b', src):
                ln = src[:m.start()].count('\n') + 1
                errs.append(f'{rel(f)}:{ln}: TextDirection.{m.group(1)} resolves '
                            f'to the intl enum — add "hide TextDirection" to the '
                            f'intl import')
    return errs, 'no known-bad API patterns'


def _balanced(src, start):
    """Text inside the braces opening at `start`, or None if unbalanced."""
    depth, i = 0, start
    while i < len(src):
        c = src[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return src[start + 1:i]
        i += 1
    return None



def main():
    checks = [
        ('brackets', check_brackets),
        ('symbols', check_symbols),
        ('imports', check_imports),
        ('params', check_widget_params),
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
