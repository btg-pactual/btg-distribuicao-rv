import json
import subprocess
import urllib.request
from pathlib import Path

root = Path(r"C:\Users\PIMENTPA\Projects\Artes\clone-github")
out = Path(__file__).resolve().parent / "_poll_live_out.txt"
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

headers = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {token}",
    "User-Agent": "prateleira-check",
    "X-GitHub-Api-Version": "2022-11-28",
}
req = urllib.request.Request(
    "https://api.github.com/repos/btg-pactual/btg-distribuicao-rv/actions/runs?per_page=6",
    headers=headers,
)
with urllib.request.urlopen(req, timeout=60) as resp:
    runs = json.loads(resp.read().decode())["workflow_runs"]
lines = ["runs:"]
for r in runs:
    lines.append(
        f"  {r['name']} | {r['status']}/{r.get('conclusion')} | {r['created_at']} | head={r['head_sha'][:7]}"
    )

# bust cache with query
for url in [
    "https://btg-pactual.github.io/btg-distribuicao-rv/prateleira/index.html",
    "https://btg-pactual.github.io/btg-distribuicao-rv/prateleira/index.html?v=18a3bf1",
]:
    html = urllib.request.urlopen(
        urllib.request.Request(url, headers={"User-Agent": "x", "Cache-Control": "no-cache"}),
        timeout=60,
    ).read().decode("utf-8", errors="replace")
    lines.append(f"\n{url}")
    for needle in ["Source Serif 4", "hero-kicker", "Selecione o ativo", "Toque para ver"]:
        lines.append(f"  {needle!r}: {needle in html}")

out.write_text("\n".join(lines), encoding="utf-8")
print("\n".join(lines))
