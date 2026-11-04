import json
import subprocess
import urllib.request
from pathlib import Path

root = Path(r"C:\Users\PIMENTPA\Projects\Artes\clone-github")
out = Path(__file__).resolve().parent / "_check_live.txt"
token = ""
p = subprocess.run(
    ["git", "credential", "fill"],
    input="protocol=https\nhost=github.com\n\n",
    cwd=str(root),
    capture_output=True,
    text=True,
    timeout=10,
)
for line in (p.stdout or "").splitlines():
    if line.startswith("password="):
        token = line.split("=", 1)[1].strip()

lines = []
# tip of pages
r = subprocess.run(
    ["git", "ls-remote", "origin", "pages"],
    cwd=str(root),
    capture_output=True,
    text=True,
)
lines.append("ls-remote pages: " + (r.stdout or r.stderr).strip())
r2 = subprocess.run(
    ["git", "log", "origin/pages", "-1", "--oneline"],
    cwd=str(root),
    capture_output=True,
    text=True,
)
lines.append("origin/pages tip: " + (r2.stdout or "").strip())

# raw github file snippet
url = "https://raw.githubusercontent.com/btg-pactual/btg-distribuicao-rv/pages/prateleira/index.html"
req = urllib.request.Request(url, headers={"User-Agent": "prateleira-check"})
with urllib.request.urlopen(req, timeout=60) as resp:
    html = resp.read().decode("utf-8", errors="replace")
lines.append(f"raw status ok, len={len(html)}")
for needle in ["Source Serif 4", "hero-kicker", "BTG Pactual", "logo-btg", "Segoe UI"]:
    lines.append(f"  raw has {needle!r}: {needle in html}")

# pages live
live = "https://btg-pactual.github.io/btg-distribuicao-rv/prateleira/index.html"
req2 = urllib.request.Request(live, headers={"User-Agent": "prateleira-check", "Cache-Control": "no-cache"})
with urllib.request.urlopen(req2, timeout=60) as resp:
    live_html = resp.read().decode("utf-8", errors="replace")
    lines.append(f"live status ok, len={len(live_html)}, cache={resp.headers.get('Cache-Control')}, age={resp.headers.get('Age')}")
for needle in ["Source Serif 4", "hero-kicker", "BTG Pactual", "Segoe UI"]:
    lines.append(f"  live has {needle!r}: {needle in live_html}")

# recent pages deploy
api = "https://api.github.com/repos/btg-pactual/btg-distribuicao-rv/actions/runs?per_page=8"
headers = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "prateleira-check",
    "Authorization": f"Bearer {token}",
}
req3 = urllib.request.Request(api, headers=headers)
with urllib.request.urlopen(req3, timeout=60) as resp:
    data = json.loads(resp.read().decode())
lines.append("\nrecent runs:")
for run in data.get("workflow_runs", []):
    lines.append(
        f"  {run.get('name')} | {run.get('status')}/{run.get('conclusion')} | "
        f"{run.get('created_at')} | head={str(run.get('head_sha',''))[:7]} | {run.get('html_url')}"
    )

out.write_text("\n".join(lines), encoding="utf-8")
print(out.read_text(encoding="utf-8"))
