"""Build the self-contained DaewidHUB runtime from local source."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]

def build():
    parts = json.loads((ROOT / "ui/order.json").read_text(encoding="utf-8"))["parts"]
    ui = []
    for part in parts:
        name = part["path"]
        assert Path(name).name == name and name.endswith(".lua"), "Invalid UI module"
        ui.append((ROOT / "ui" / name).read_text(encoding="utf-8"))
    engine = 'local HttpService = game:GetService("HttpService")\n' + "\n".join(ui)
    modules = json.loads((ROOT / "src/module-order.json").read_text(encoding="utf-8"))
    modules += ["shared/ui-bridge", "shared/profiles", "shared/themes"]
    assert len(modules) == len(set(modules)), "Duplicate application module"
    bootstrap = '''local modules, cache, loading = {}, {}, {}
local function use(name)
    if cache[name] ~= nil then return cache[name] end
    assert(modules[name], "DaewidHUB: missing module " .. tostring(name))
    assert(not loading[name], "DaewidHUB: circular module " .. tostring(name))
    loading[name] = true
    local ok, result = xpcall(modules[name], debug.traceback, use)
    loading[name] = nil
    if not ok then error(result, 0) end
    if result == nil then result = true end
    cache[name] = result
    return result
end
'''
    license_text = (ROOT / "licenses/Gameplay-MIT.txt").read_text(encoding="utf-8")
    result = ["--[[\n" + license_text + "\n]]\n", bootstrap]
    for name in modules:
        payload = (ROOT / "src" / (name + ".luau")).read_text(encoding="utf-8")
        result.append('modules[' + json.dumps(name) + '] = function(use)\n' + payload + '\nend\n')
    result.append('modules["vendor/ui"] = function(use)\n' + engine + '\nend\n')
    result.append('return use("main")\n')
    runtime = "".join(result)
    assert "media/edits" not in runtime and "G.openEdit" not in runtime, "Unexpected film UI"
    (ROOT / "DaewidHUB.lua").write_text(runtime, encoding="utf-8", newline="\n")
    print(f"Built DaewidHUB.lua: {len(modules)} app modules, {len(ui)} UI modules, {len(runtime.encode()):,} bytes")

if __name__ == "__main__":
    build()
