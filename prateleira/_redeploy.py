import json
import subprocess
import time
import urllib.request
from pathlib import Path

root = Path(r"C:\Users\PIMENTPA\Projects\Artes\clone-github")
out = Path(__file__).resolve().parent / "_redeploy_out.txt"
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
    "Content-Type": "application/json",
}
parts = []

# list workflows for deploy
req = urllib.request.Request(
    "https://api.github.com/repos/btg-pactual/btg-distribuicao-rv/actions/workflows",
    headers=headers,
)
with urllib.request.urlopen(req, timeout=60) as resp:
    wfs = json.loads(resp.read().decode())["workflows"]
for w in wfs:
    parts.append(f"wf {w['id']} {w['name']} path={w['path']}")

# recent runs
req = urllib.request.Request(
    "https://api.github.com/repos/btg-pactual/btg-distribuicao-rv/actions/runs?per_page=12",
    headers=headers,
)
with urllib.request.urlopen(req, timeout=60) as resp:
    runs = json.loads(resp.read().decode())["workflow_runs"]
parts.append("\nrecent:")
for r in runs:
    parts.append(
        f"  {r['name']} | {r['status']}/{r.get('conclusion')} | {r['created_at']} | "
        f"head={r['head_sha'][:7]} | event={r['event']}"
    )

# dispatch deploy-pages if exists
deploy = next((w for w in wfs if "deploy-pages" in (w.get("path") or "")), None)
if deploy:
    url = f"https://api.github.com/repos/btg-pactual/btg-distribuicao-rv/actions/workflows/{deploy['id']}/dispatches"
    body = json.dumps({"ref": "pages"}).encode()
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            parts.append(f"\ndispatch deploy status={resp.status}")
    except Exception as e:
        err = ""
        if hasattr(e, "read"):
            try:
                err = e.read().decode("utf-8", errors="replace")[:1500]
            except Exception:
                pass
        parts.append(f"\ndispatch ERR {e}\n{err}")

out.write_text("\n".join(parts), encoding="utf-8")
print(out.read_text(encoding="utf-8"))
