#!/usr/bin/env python3
"""Report Russian localization coverage for GuesliApp UI string literals.

Extracts keys from SwiftUI literals (Text, Button, Label, Toggle, Picker, Section,
TextField, .help, .navigationTitle, alert titles) and String(localized: "...") calls,
converts interpolation to format specifiers, and compares them with the keys in
native/Guesli/Localization/ru/*.strings.

Usage: scripts/l10n_coverage.py [--missing] [--exclude File.swift ...]
"""
import argparse
import itertools
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "native/Guesli/Sources/GuesliApp"
FRAGMENTS = ROOT / "native/Guesli/Localization/ru"

# A call whose first unlabeled argument (or `localized:`) is a localizable literal.
CALL = re.compile(
    r'(?:(?<![\w.])(?:Text|Button|Label|Toggle|Picker|Section|TextField|SecureField|Menu|LabeledContent)\('
    r'|\.(?:help|navigationTitle|alert|confirmationDialog|accessibilityLabel|accessibilityHint)\('
    r'|String\(\s*localized:)'
    r'\s*"'
)
# House helpers that render their String parameter through Text(LocalizedStringKey(...)).
HELPER_FIRST_ARG = re.compile(
    r'(?<![\w.])(?:settingsSection|settingsRow|settingsDescription|screenContextRow|permissionStatusRow|actionButton'
    r'|sectionHeader|aboutRow|diagnosticSummaryRow|onboardingButton|providerTab|noResultsForTab)\(\s*"'
)
HELPER_LABELED = re.compile(
    r'(?<![\w.])(?:settingsRow|markdownToolbarButton|iconButton|folderPopoverRow|sourceBadge|sidebarItem|StatCard'
    r'|templateMenuItem|useCaseCard|permissionRow|DictionaryIconButton)\('
)
LABELED_ARG = re.compile(r'\b(?:label|title|subtitle|description):\s*"')
# `Text(flag ? "A" : "B")`: both literals resolve to LocalizedStringKey.
TERNARY_CALL = re.compile(
    r'(?:(?<![\w.])(?:Text|Button|Toggle|onboardingButton|actionButton|settingsRow)|\.help)\((?=[^")])'
)
TERNARY = re.compile(r'\?\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"')
# Product names stay as they are in every language.
VERBATIM = {"ChatGPT", "OpenAI", "Ollama", "OpenRouter", "CUA"}
# AppKit strings must go through String(localized:); a bare literal here is never translated.
APPKIT_LITERAL = re.compile(
    r'(?:withTitle|NSMenuItem\(title|messageText|informativeText|placeholderString|toolTip|\.title|\.subtitle|\.body)'
    r'\s*[:=]\s*"[^"\n]*[A-Za-z]'
)
INT_EXPR = re.compile(r'(\.count|Count|Index|Number|Seconds|Minutes|Hours|Ms|MS)$|^Int\(|^\w+\.count\b|[^/]/\s*\d|%\s*\d')
DOUBLE_EXPR = re.compile(r'^Double\(')


def read_literal(text, start):
    """Parse a single-line Swift string literal starting after the opening quote.

    Returns (parts, end) where parts alternate literal text and ("interp", expr).
    """
    parts, buf, i = [], [], start
    escapes = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0", "r": "\r"}
    while i < len(text):
        ch = text[i]
        if ch == '"':
            parts.append("".join(buf))
            return parts, i + 1
        if ch == "\n":
            return None, i
        if ch == "\\":
            nxt = text[i + 1]
            if nxt == "(":
                depth, j = 1, i + 2
                while j < len(text) and depth:
                    if text[j] == "(":
                        depth += 1
                    elif text[j] == ")":
                        depth -= 1
                    elif text[j] == '"':  # nested literal inside interpolation
                        _, j = read_literal(text, j + 1)
                        continue
                    j += 1
                parts.append("".join(buf))
                buf = []
                parts.append(("interp", text[i + 2 : j - 1].strip()))
                i = j
                continue
            if nxt == "u" and text[i + 2] == "{":
                close = text.index("}", i)
                buf.append(chr(int(text[i + 3 : close], 16)))
                i = close + 1
                continue
            buf.append(escapes.get(nxt, nxt))
            i += 2
            continue
        buf.append(ch)
        i += 1
    return None, i


def specifier(expr):
    if DOUBLE_EXPR.search(expr):
        return "%lf"
    if INT_EXPR.search(expr):
        return "%lld"
    return "%@"


def keys_for(parts):
    """Best-guess key plus all specifier variants (types are only guessed)."""
    interps = [p[1] for p in parts if isinstance(p, tuple)]
    if not interps:
        return parts[0], {parts[0]}

    def build(specs):
        it = iter(specs)
        return "".join(p.replace("%", "%%") if isinstance(p, str) else next(it) for p in parts)

    best = build([specifier(e) for e in interps])
    variants = {best}
    if len(interps) <= 4:
        for combo in itertools.product(["%@", "%lld", "%lf"], repeat=len(interps)):
            variants.add(build(combo))
    return best, variants


def is_visible(key):
    if key in VERBATIM:
        return False
    return bool(re.search(r"[A-Za-z]", key.replace("%lld", "").replace("%@", "").replace("%lf", "")))


def call_span(text, open_paren):
    """Index just past the parenthesis that closes the call opened at open_paren."""
    depth, i = 0, open_paren
    while i < len(text):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        elif text[i] == '"':
            _, i = read_literal(text, i + 1)
            continue
        i += 1
    return len(text)


def literal_starts(text, helpers):
    """Positions just after the opening quote of each localizable literal."""
    for match in CALL.finditer(text):
        yield match.start(), match.end(), "swiftui"
    for match in TERNARY_CALL.finditer(text):
        first_arg = text[match.end() : call_span(text, match.end() - 1)]
        first_arg = first_arg.split(",")[0] if "," in first_arg else first_arg
        hit = TERNARY.search(first_arg)
        if hit and "\\(" not in hit.group(0):
            kind = "swiftui" if text[match.start()] in "T.B" else "helper"
            yield match.start(), match.end() + hit.start(1), kind
            yield match.start(), match.end() + hit.start(2), kind
    if not helpers:
        return
    for match in HELPER_FIRST_ARG.finditer(text):
        yield match.start(), match.end(), "helper"
    for match in HELPER_LABELED.finditer(text):
        end = call_span(text, match.end() - 1)
        for arg in LABELED_ARG.finditer(text, match.end(), end):
            yield arg.start(), arg.end(), "helper"


def extract(path, helpers):
    text = path.read_text(encoding="utf-8")
    found, seen = [], set()
    for at, start, kind in literal_starts(text, helpers):
        if start in seen or text[start - 3 : start] == '"""':
            continue
        seen.add(start)
        parts, _ = read_literal(text, start)
        if parts is None:
            continue
        best, variants = keys_for(parts)
        if is_visible(best):
            line = text.count("\n", 0, at) + 1
            found.append((best, variants, line, kind))
    return found


def unescape_strings(s):
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def fragment_keys():
    keys = {}
    pattern = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)
    for path in sorted(FRAGMENTS.glob("*.strings")):
        for m in pattern.finditer(path.read_text(encoding="utf-8")):
            keys[unescape_strings(m.group(1))] = path.name
    plurals = FRAGMENTS / "Localizable.stringsdict"
    if plurals.exists():
        with plurals.open("rb") as handle:
            keys.update(dict.fromkeys(plistlib.load(handle), plurals.name))
    return keys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--missing", action="store_true", help="list missing keys with file:line")
    parser.add_argument("--exclude", nargs="*", default=[], help="Swift files to leave out of the missing list")
    parser.add_argument("--no-helpers", action="store_true", help="only SwiftUI literals and String(localized:)")
    args = parser.parse_args()

    translated = fragment_keys()
    sources = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        for best, variants, line, kind in extract(path, helpers=not args.no_helpers):
            entry = sources.setdefault(best, {"variants": set(), "where": [], "kinds": set()})
            entry["variants"] |= variants
            entry["where"].append(f"{path.name}:{line}")
            entry["kinds"].add(kind)

    def report(label, keys):
        covered = {k for k in keys if sources[k]["variants"] & translated.keys()}
        print(f"{label}: {len(covered)}/{len(keys)} keys translated, {100 * len(covered) / max(len(keys), 1):.1f}%")
        return covered

    report("SwiftUI + String(localized:)", [k for k, e in sources.items() if "swiftui" in e["kinds"]])
    covered = report("all incl. house helpers", list(sources))

    excluded = set(args.exclude)
    appkit = []
    for path in sorted(SOURCES.rglob("*.swift")):
        if path.name in excluded:
            continue
        text = path.read_text(encoding="utf-8")
        for m in APPKIT_LITERAL.finditer(text):
            appkit.append(f"{path.name}:{text.count(chr(10), 0, m.start()) + 1}")
    print(f"unwrapped AppKit literals: {len(appkit)}")

    if args.missing:
        for where in appkit:
            print(f"appkit\t{where}")
        for key in sorted(set(sources) - covered):
            where = [w for w in sources[key]["where"] if w.split(":")[0] not in excluded]
            if where:
                print(f"{key!r}\t{', '.join(where)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
