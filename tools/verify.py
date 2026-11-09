"""Run offline preservation, compile and focused UI adapter regression checks."""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import re
import subprocess
import tempfile
from build import ROOT, build


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--luau", required=True)
    parser.add_argument("--compiler", required=True)
    args = parser.parse_args()
    build()
    runtime = (ROOT / "DaewidHUB.lua").read_bytes()
    build()
    assert runtime == (ROOT / "DaewidHUB.lua").read_bytes(), "Non-deterministic build"
    for entry in json.loads((ROOT / "tests/feature-baseline.json").read_text())["modules"]:
        data = (ROOT / "src" / (entry["name"] + ".luau")).read_text(encoding="utf-8").rstrip() + "\n"
        assert hashlib.sha256(data.encode()).hexdigest() == entry["sha256"], entry["name"]
    print("PASS: 20 original application modules preserved; reproducible runtime")
    body = runtime.decode()
    assert not re.search(r"slopix|TrustyCoding/daewid-hub|__HUSS_LUMEN|HussValley", body, re.I), "Stale branding/namespace"
    assert "G.openEdit" not in body and "G.loaderFilm" not in body and 'G.assets.background=' not in body
    assert not re.search(r'game:HttpGet\s*\(', body), "Unexpected HTTP API"
    assert 'use("vendor/icons")' not in body, "Unused legacy UI dependency"
    embedded = (ROOT / "ui/embedded-assets.lua").read_text(encoding="utf-8")
    assets = re.findall(r'\{\["path"\]="([^"]+)",\["bytes"\]=(\d+),\["data"\]=([\s\S]*?)\}', embedded)
    assert len(assets) == 18, len(assets)
    for path, size, payload in assets:
        data = base64.b64decode("".join(re.findall(r'"([A-Za-z0-9+/=]+)"', payload)), validate=True)
        assert len(data) == int(size), path
        assert path.startswith(("icons/", "sounds/")) and ".." not in path
    print("PASS: 18 embedded icon/sound assets; no film UI or remote media install")
    sources = [str(ROOT / "DaewidHUB.lua")] + [str(path) for path in (ROOT / "src").rglob("*.luau")]
    subprocess.run([args.compiler, "--null", *sources], check=True)
    fixtures = [
        ("controls", (ROOT / "ui/lm_06_controls.lua").read_text(encoding="utf-8")),
        ("bridge", (ROOT / "src/shared/ui-bridge.luau").read_text(encoding="utf-8")),
        ("profiles", (ROOT / "src/shared/profiles.luau").read_text(encoding="utf-8")),
    ]
    with tempfile.TemporaryDirectory(prefix="daewid-ui-") as temporary:
        for name, source in fixtures:
            prefix = (ROOT / "tests" / (name + "-prefix.luau")).read_text(encoding="utf-8")
            suffix = (ROOT / "tests" / (name + "-suffix.luau")).read_text(encoding="utf-8")
            fixture = Path(temporary) / (name + ".luau")
            fixture.write_text(prefix + "\n" + source + "\n" + suffix, encoding="utf-8")
            subprocess.run([args.luau, str(fixture)], check=True)
        spring = Path(temporary) / "spring.luau"
        spring.write_text('local L = {}\nlocal function getgenv() return { __DAEWID_BALL_LUMEN = L } end\n' +
            (ROOT / "ui/lm_02_spring.lua").read_text(encoding="utf-8") +
            '\nlocal report, failures = L.Spring.selftest()\nassert(failures == 0, report)\nprint("PASS: original spring math self-test")\n', encoding="utf-8")
        subprocess.run([args.luau, str(spring)], check=True)
    print("PASS: all offline checks. Live Roblox visual/gameplay behavior is not exercised.")

if __name__ == "__main__":
    main()
