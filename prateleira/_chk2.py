import subprocess
import urllib.request
from pathlib import Path

root = Path(r"C:\Users\PIMENTPA\Projects\Artes\clone-github")
out = Path(__file__).resolve().parent / "_chk2_out.txt"
lines = []

subprocess.run(["git", "fetch", "origin", "pages"], cwd=root, capture_output=True)
r = subprocess.run(["git", "log", "origin/pages", "-8", "--oneline"], cwd=root, capture_output=True, text=True)
lines.append("log:\n" + r.stdout)

for path in ["prateleira/_build.py", "prateleira/index.html"]:
    r = subprocess.run(["git", "show", f"origin/pages:{path}"], cwd=root, capture_output=True, text=True, encoding="utf-8", errors="replace")
    text = r.stdout or ""
    lines.append(f"\n== {path} len={len(text)} ==")
    for needle in ["Source Serif 4", "hero-kicker", "Selecione o ativo", "Toque para ver", "Segoe UI", "Material da semana", "Material PDF"]:
        lines.append(f"  {needle!r}: {needle in text}")

# live
html = urllib.request.urlopen(
    urllib.request.Request(
        "https://btg-pactual.github.io/btg-distribuicao-rv/prateleira/index.html",
        headers={"User-Agent": "x", "Cache-Control": "no-cache"},
    ),
    timeout=60,
).read().decode("utf-8", errors="replace")
lines.append(f"\n== live len={len(html)} ==")
for needle in ["Source Serif 4", "hero-kicker", "Selecione o ativo", "Toque para ver", "Segoe UI", "Material da semana"]:
    lines.append(f"  {needle!r}: {needle in html}")

# raw
html2 = urllib.request.urlopen(
    urllib.request.Request(
        "https://raw.githubusercontent.com/btg-pactual/btg-distribuicao-rv/pages/prateleira/index.html",
        headers={"User-Agent": "x"},
    ),
    timeout=60,
).read().decode("utf-8", errors="replace")
lines.append(f"\n== raw len={len(html2)} ==")
for needle in ["Source Serif 4", "hero-kicker", "Selecione o ativo", "Toque para ver"]:
    lines.append(f"  {needle!r}: {needle in html2}")

out.write_text("\n".join(lines), encoding="utf-8")
print("\n".join(lines))
