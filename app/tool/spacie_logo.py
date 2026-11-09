import re, sys
svg = open(sys.argv[1]).read()
paths = re.findall(r'<path d="([^"]*)" fill="(#[0-9a-fA-F]{6})"/>', svg)
assert len(paths) == 2, len(paths)
view = re.search(r'viewBox="0 0 ([0-9.]+) ([0-9.]+)"', svg)
out = []
for d, fill in paths:
    assert re.fullmatch(r'[MLZ0-9. \-]+', d), 'unexpected path data'
    out.append((d, fill))
w, h = view.group(1), view.group(2)
lines = []
lines.append("// Generated from https://spacie.net/spacie-mark.svg (two filled paths).")
lines.append("// Regenerate: python3 tool/spacie_logo.py <svg> > lib/ui/widgets/spacie_logo_data.dart")
lines.append("")
lines.append("/// (fill ARGB, path data with M/L/Z commands only), back to front.")
lines.append("const spaciePaths = <(int, String)>[")
for d, fill in out:
    lines.append(f"  (0xFF{fill[1:].upper()}, '{d}'),")
lines.append("];")
print("\n".join(lines))
