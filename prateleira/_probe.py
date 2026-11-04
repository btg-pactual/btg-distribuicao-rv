from pathlib import Path
from datetime import datetime
p = Path(__file__).with_name("_probe.txt")
p.write_text(datetime.now().isoformat(), encoding="utf-8")
