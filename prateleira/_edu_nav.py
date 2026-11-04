"""Insere o item Educacional no hub que veio da pages, sem regravar as fichas."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LINK = '    <a class="nav-item" href="./educacao.html">Educacional</a>\n'
ITEM = '    {item("educacao", "./educacao.html", "Educacional")}\n'

def patch_html(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if "educacao.html" in text:
        return
    needle = "  </nav>"
    if needle not in text:
        raise SystemExit(f"nav nao encontrada em {path.name}")
    path.write_text(text.replace(needle, LINK + needle, 1), encoding="utf-8")

def patch_build(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if '"./educacao.html"' in text:
        return
    needle = '{item("estruturas", "./estruturas.html", "Estruturas")}\n'
    if needle not in text:
        raise SystemExit("sidebar do _build.py nao encontrada")
    path.write_text(text.replace(needle, needle + ITEM, 1), encoding="utf-8")

for name in ("index.html", "empresas.html", "estruturas.html"):
    patch_html(ROOT / name)
patch_build(ROOT / "_build.py")
print("nav ok")
