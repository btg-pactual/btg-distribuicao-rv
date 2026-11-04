import subprocess
from pathlib import Path
root = Path(r"C:\Users\PIMENTPA\Projects\Artes\clone-github")
r = subprocess.run(
    ["git", "show", "origin/pages:.github/workflows/deploy-pages.yml"],
    cwd=root, capture_output=True, text=True, encoding="utf-8", errors="replace"
)
Path(__file__).with_name("_deploy_yml.txt").write_text(r.stdout or r.stderr, encoding="utf-8")
print((r.stdout or r.stderr)[:2500])
