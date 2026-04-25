#!/usr/bin/env python3
import re, sys, copy, argparse, csv
from pathlib import Path
from collections import defaultdict

COLOR_MAP = {
    "0a0a0f": ("context.xBg",        "XameColors.darkBg",      "bg"),
    "141420": ("context.xSurface",   "XameColors.darkSurface", "surface"),
    "1e1e2e": ("context.xCard",      "XameColors.darkCard",    "card"),
    "00d4ff": ("context.xPrimary",   "XameColors.primary",     "primary"),
    "7b2fff": ("context.xSecondary", "XameColors.secondary",   "secondary"),
    "00ff88": ("context.xAccent",    "XameColors.accent",      "accent"),
    "ff3b5c": ("context.xDanger",    "XameColors.danger",      "danger"),
    "8899a6": ("context.xMuted",     "XameColors.darkSurface", "textSecondary"),
    "1a4a6e": ("context.xBubbleSent","XameColors.darkCard",    "bubbleSent"),
    "070d1a": ("context.xBg",        "XameColors.darkBg",      "bg(midnight)"),
    "0d1b2e": ("context.xSurface",   "XameColors.darkSurface", "surface(midnight)"),
    "111e2e": ("context.xCard",      "XameColors.darkCard",    "card(dark-navy)"),
    "112440": ("context.xCard",      "XameColors.darkCard",    "card(midnight)"),
    "050505": ("context.xBg",        "XameColors.darkBg",      "bg(near-black)"),
    "080c14": ("context.xBg",        "XameColors.darkBg",      "bg(dark-navy)"),
    "0a0a1a": ("context.xBg",        "XameColors.darkBg",      "bg(obsidian-v)"),
    "0d1117": ("context.xBg",        "XameColors.darkBg",      "bg(github-dark)"),
    "0d1520": ("context.xSurface",   "XameColors.darkSurface", "surface(dark-navy)"),
    "0f172a": ("context.xBg",        "XameColors.darkBg",      "bg(slate-900)"),
    "0f2027": ("context.xBg",        "XameColors.darkBg",      "bg(dark-teal)"),
    "111827": ("context.xSurface",   "XameColors.darkSurface", "surface(gray-900)"),
    "161b22": ("context.xSurface",   "XameColors.darkSurface", "surface(github-dark)"),
    "1a1a2e": ("context.xSurface",   "XameColors.darkSurface", "surface(dark-purple)"),
    "1a2332": ("context.xSurface",   "XameColors.darkSurface", "surface(dark-blue)"),
    "1a2340": ("context.xSurface",   "XameColors.darkSurface", "surface(deep-navy)"),
    "1e2533": ("context.xSurface",   "XameColors.darkSurface", "surface(dark)"),
    "1e2d3d": ("context.xSurface",   "XameColors.darkSurface", "surface(dark-blue)"),
    "1f2937": ("context.xSurface",   "XameColors.darkSurface", "surface(gray-800)"),
    "21262d": ("context.xCard",      "XameColors.darkCard",    "card(github-dark)"),
    "203a43": ("context.xSurface",   "XameColors.darkSurface", "surface(dark-teal)"),
    "263238": ("context.xCard",      "XameColors.darkCard",    "card(blue-gray)"),
    "2a2a3e": ("context.xCard",      "XameColors.darkCard",    "card(dark-purple)"),
    "2a3f52": ("context.xCard",      "XameColors.darkCard",    "card(dark-blue)"),
    "2c5364": ("context.xCard",      "XameColors.darkCard",    "card(teal-dark)"),
    "30363d": ("context.xCard",      "XameColors.darkCard",    "card(github-dark)"),
    "333333": ("context.xCard",      "XameColors.darkCard",    "card(neutral-dark)"),
    "37474f": ("context.xCard",      "XameColors.darkCard",    "card(blue-gray)"),
    "3d4450": ("context.xCard",      "XameColors.darkCard",    "card(slate)"),
    "455a64": ("context.xMuted",     "XameColors.darkSurface", "muted(blue-gray)"),
    "7a9bb5": ("context.xMuted",     "XameColors.darkSurface", "muted(steel-blue)"),
    "8b949e": ("context.xMuted",     "XameColors.darkSurface", "muted(github)"),
    "1a4a3a": ("context.xSurface",   "XameColors.darkSurface", "surface(dark-green)"),
    "1e3a2f": ("context.xSurface",   "XameColors.darkSurface", "surface(dark-forest)"),
    "00b0a0": ("context.xAccent",    "XameColors.accent",      "accent(teal)"),
    "00838f": ("context.xAccent",    "XameColors.accent",      "accent(cyan-dark)"),
    "008a7d": ("context.xAccent",    "XameColors.accent",      "accent(teal-dark)"),
    "00d4aa": ("context.xAccent",    "XameColors.accent",      "accent(mint)"),
    "2196f3": ("context.xPrimary",   "XameColors.primary",     "primary(material-blue)"),
    "1565c0": ("context.xPrimary",   "XameColors.primary",     "primary(blue-800)"),
    "4fc3f7": ("context.xPrimary",   "XameColors.primary",     "primary(light-blue)"),
    "9c27b0": ("context.xSecondary", "XameColors.secondary",   "secondary(purple)"),
    "6a1b9a": ("context.xSecondary", "XameColors.secondary",   "secondary(deep-purple)"),
    "4527a0": ("context.xSecondary", "XameColors.secondary",   "secondary(indigo)"),
    "7c4dff": ("context.xSecondary", "XameColors.secondary",   "secondary(purple-accent)"),
    "8b5cf6": ("context.xSecondary", "XameColors.secondary",   "secondary(violet)"),
    "ad1457": ("context.xDanger",    "XameColors.danger",      "danger(pink-dark)"),
    "e53935": ("context.xDanger",    "XameColors.danger",      "danger(red-600)"),
    "d32f2f": ("context.xDanger",    "XameColors.danger",      "danger(red-700)"),
    "ef4444": ("context.xDanger",    "XameColors.danger",      "danger(red-500)"),
    "ff4444": ("context.xDanger",    "XameColors.danger",      "danger(bright-red)"),
    "ff5252": ("context.xDanger",    "XameColors.danger",      "danger(red-accent)"),
    "ff6464": ("context.xDanger",    "XameColors.danger",      "danger(coral-red)"),
    "ff6b6b": ("context.xDanger",    "XameColors.danger",      "danger(salmon-red)"),
    "e88080": ("context.xDanger",    "XameColors.danger",      "danger(soft-red)"),
    "d84315": ("context.xDanger",    "XameColors.danger",      "danger(deep-orange)"),
    "e65100": ("context.xDanger",    "XameColors.danger",      "danger(orange-900)"),
    "ff9800": ("context.xAccent",    "XameColors.accent",      "accent(amber)"),
    "ffb800": ("context.xAccent",    "XameColors.accent",      "accent(yellow-warm)"),
    "ffd700": ("context.xAccent",    "XameColors.accent",      "accent(gold)"),
    "f0a500": ("context.xAccent",    "XameColors.accent",      "accent(amber-dark)"),
    "f9a825": ("context.xAccent",    "XameColors.accent",      "accent(amber-800)"),
    "4caf50": ("context.xAccent",    "XameColors.accent",      "accent(green)"),
    "2e7d32": ("context.xAccent",    "XameColors.accent",      "accent(green-dark)"),
    "558b2f": ("context.xAccent",    "XameColors.accent",      "accent(light-green)"),
}

AMBIGUOUS = {"ffffff", "000000"}

COLOR_RE = re.compile(r'(?:const\s+)?Color\(0x([0-9A-Fa-f]{8})\)', re.IGNORECASE)
WIDGET_RE = re.compile(
    r'BuildContext\s+context|Widget\s+build\s*\('
    r'|extends\s+(?:Stateless|Stateful|Consumer|ConsumerStateful|Hook)Widget'
)
BUILD_RE = re.compile(r'Widget\s+build\s*\(')

def get_package_name():
    try:
        for line in Path('pubspec.yaml').read_text().splitlines():
            if line.startswith('name:'):
                return line.split(':')[1].strip()
    except: pass
    return 'xamepage'

PKG = get_package_name()
IMPORT_LINE = f"import 'package:{PKG}/core/theme/app_theme.dart';"

def is_widget_file(src): return bool(WIDGET_RE.search(src))

def build_scope_lines(src):
    lines = src.splitlines()
    in_build, depth, result = False, 0, set()
    for i, line in enumerate(lines, 1):
        if not in_build:
            if BUILD_RE.search(line):
                in_build = True
                depth = line.count('{') - line.count('}')
                if depth > 0: result.add(i)
        else:
            depth += line.count('{') - line.count('}')
            if depth > 0: result.add(i)
            else:
                result.add(i); in_build = False; depth = 0
    return result

def build_rep(alpha, rgb, ctx, static, is_w, in_build):
    base = ctx if (is_w and in_build) else static
    if alpha == 'ff': return base
    return f"{base}.withValues(alpha: {round(int(alpha,16)/255, 2)})"

def replace_in_file(path, dry_run):
    src = path.read_text(encoding='utf-8')
    is_w = is_widget_file(src)
    build_lines = build_scope_lines(src) if is_w else set()
    lines = src.splitlines(keepends=True)
    new_lines = list(lines)
    records, changed = [], False
    for line_no, line in enumerate(lines, 1):
        new_line = line
        for match in COLOR_RE.finditer(line):
            raw8 = match.group(1)
            alpha, rgb = raw8[:2].lower(), raw8[2:].lower()
            if rgb in AMBIGUOUS:
                records.append({"file":str(path),"line":line_no,"hex":f"0x{raw8.upper()}","replacement":"AMBIGUOUS","old":match.group(0),"role":"","in_build":"","context":line.strip()})
                continue
            if rgb not in COLOR_MAP:
                records.append({"file":str(path),"line":line_no,"hex":f"0x{raw8.upper()}","replacement":"UNKNOWN","old":match.group(0),"role":"","in_build":"","context":line.strip()})
                continue
            ctx_a, static_a, role = COLOR_MAP[rgb]
            in_b = line_no in build_lines
            rep = build_rep(alpha, rgb, ctx_a, static_a, is_w, in_b)
            new_line = new_line.replace(match.group(0), rep, 1)
            changed = True
            records.append({"file":str(path),"line":line_no,"hex":f"0x{raw8.upper()}","role":role,"old":match.group(0),"replacement":rep,"in_build":in_b,"context":line.strip()})
        new_lines[line_no-1] = new_line
    if changed and not dry_run:
        path.write_text(''.join(new_lines), encoding='utf-8')
    return records

def ensure_import(path, dry_run):
    src = path.read_text(encoding='utf-8')
    if 'app_theme.dart' in src: return False
    last = 0
    for m in re.finditer(r"^import\s+.+;", src, re.MULTILINE): last = m.end()
    if not last: return False
    new_src = src[:last] + '\n' + IMPORT_LINE + src[last:]
    if not dry_run: path.write_text(new_src, encoding='utf-8')
    return True

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--report',  action='store_true')
    p.add_argument('--path',    default='lib/')
    args = p.parse_args()
    root = Path(args.path)
    if not root.exists(): print(f"Not found: {root}"); sys.exit(1)
    files = [f for f in root.rglob('*.dart') if 'app_theme.dart' not in f.name]
    print(f"\n{'DRY RUN' if args.dry_run else 'LIVE RUN'} — {len(files)} files  [pkg={PKG}]\n")
    all_rec, files_mod, total_rep, total_skip, imports_added = [], 0, 0, 0, 0
    stats = defaultdict(int)
    for path in sorted(files):
        recs = replace_in_file(path, args.dry_run)
        if not recs: continue
        replaced = [r for r in recs if r['replacement'] not in ('AMBIGUOUS','UNKNOWN')]
        skipped  = [r for r in recs if r['replacement'] in ('AMBIGUOUS','UNKNOWN')]
        if replaced:
            files_mod += 1; total_rep += len(replaced); total_skip += len(skipped)
            for r in replaced: stats[r['hex']] += 1
            if ensure_import(path, args.dry_run): imports_added += 1
            print(f"  {'[DRY]' if args.dry_run else '[MOD]'} {path.relative_to(root)}  ({len(replaced)} replaced, {len(skipped)} skipped)")
        all_rec.extend(recs)
    print(f"\n{'='*46}\n  Package        : {PKG}\n  Files scanned  : {len(files)}\n  Files modified : {files_mod}\n  Colors replaced: {total_rep}\n  Colors skipped : {total_skip}\n  Imports added  : {imports_added}\n{'='*46}")
    print("Top replacements:")
    for h, c in sorted(stats.items(), key=lambda x: -x[1])[:15]:
        print(f"  {h}  x{c:>4}   {COLOR_MAP.get(h[4:].lower(),('','','?'))[2]}")
    unknowns = sorted({r['hex'] for r in all_rec if r['replacement']=='UNKNOWN'})
    if unknowns:
        print(f"\nUNKNOWN ({len(unknowns)}):")
        for h in unknowns: print(f"  {h}")
    if args.report:
        rp = Path('color_report.csv')
        fields = ['file','line','hex','role','old','replacement','in_build','context']
        with open(rp,'w',newline='',encoding='utf-8') as f:
            w = csv.DictWriter(f, fieldnames=fields)
            w.writeheader()
            for r in all_rec: w.writerow({k:r.get(k,'') for k in fields})
        print(f"\nReport → {rp.absolute()}")
    print(f"\n{'Dry run — rerun without --dry-run to apply.' if args.dry_run else 'Done. Run: flutter build apk --release 2>&1 | grep Error'}")

if __name__ == '__main__': main()
