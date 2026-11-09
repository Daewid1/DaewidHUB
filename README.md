# DaewidHUB

Ball VS Ball controls in the original Giorgio/Lumen interface, tailored for DaewidHUB.

## Run

Execute this in your compatible executor:

~~~lua
local response = request({Url = "https://raw.githubusercontent.com/Daewid1/DaewidHUB/main/Loader.lua", Method = "GET"})
assert(response.StatusCode == 200 and response.Success ~= false, "DaewidHUB loader download failed")
local run, reason = loadstring(response.Body)
assert(run, reason)
run()
~~~

Alternatively execute Loader.lua directly. The loader uses request(), validates the HTTP response and loads a pinned DaewidHUB.lua revision. All UI icons and sounds are embedded in the runtime: there is no video, edits folder or media-pack download.

- Original charcoal/ivory styling, spring interactions, animated sidebar icons and opening sequence.
- Original corner-dot/infinity minimize-and-restore interaction, command palette and compact shortcut HUD.
- Home, Duel, Intel, Rewards and Settings retain their original feature controls, defaults and backend behavior.
- Multi-select pick exclusions and event-shop selections, dynamic inventory lists and live status panels remain supported.
- Menu key: RightShift by default. Ctrl+K opens search. Click a toggle's key chip to bind it; Backspace clears a captured binding.
- Configurations, custom themes, autoload and per-feature shortcuts save under DaewidHUB/. Earlier UI editions and their profiles are not overwritten.
- No old community invite or unrelated gameplay features are added. Required open-source notices are retained in licenses/ and the bundled runtime.

## Source

- src/core/: original Ball VS Ball integration and simulation.
- src/features/: Home, Duel, Intel, Rewards and Settings.
- src/shared/: original lifecycle/environment utilities plus the UI bridge, local profiles and themes.
- ui/: ordered Giorgio/Lumen source modules, UI-only assets, native text, skin and adapter.
- tools/build.py: deterministic single-file runtime build using Python's standard library.
- tests/ and tools/verify.py: preserved-backend hashes, control/adapter/configuration fixtures and original spring math checks.

Build: py -3.13 tools/build.py

Verify: py -3.13 tools/verify.py --luau PATH_TO_LUAU --compiler PATH_TO_LUAU_COMPILE

## Verification limits

Compilation, backend preservation, embedded-asset lengths and offline behavioral fixtures are checked. The running Roblox session was not changed, and no live controls were toggled. Visual/device behavior and gameplay against the current game build still require an in-game check. Existing game/executor limitations remain; a UI port cannot guarantee server behavior.

Config files can contain your webhook URL. Keep local configuration files private; none are included in this repository.
