# EMPIRE: RUN NEW YORK

Persistent online Mafia empire-building strategy game set in 1977 New York.
Godot 4.7 (GDScript, Mobile renderer), landscape, iOS and Android.

## Running

Open the folder in Godot 4.7 and press Play, or run it from the command line:

```sh
GODOT=~/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --path .                       # play (loads the save if there is one)
$GODOT --path . -- --new-game         # ignore the save and start Chapter 1 fresh
```

Desktop controls:

- Left-drag: pan.
- Wheel: zoom toward the cursor.
- Right-drag or Q/E: rotate.
- WASD or arrow keys: pan.
- +/-: zoom.
- Click: select.

Touch controls:

- One finger: pan.
- Pinch: zoom.
- Two-finger twist: rotate.
- Tap: select.

## Tests

```sh
$GODOT --headless --path . --import                # refresh the class cache after adding scripts
$GODOT --headless --path . -s tests/run_tests.gd   # exits non-zero on failure
```

## Visual capture (automated screenshots)

```sh
$GODOT --path . -- --new-game --capture=/tmp/shot.png --capture-delay=5 --stats \
  --view=-80,-30,75,-32 \
  '--command={"type":"move_crew","crew":"crew_mulberry","landmark":"lm_grand_freight"}' \
  --select=crew:crew_mulberry
```

## Regenerating art (Blender 5.2)

```sh
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
$BLENDER -b --factory-startup --python tools/blender/build_textures.py   # textures, palette, data/materials.json
$BLENDER -b --factory-startup --python tools/blender/build_props.py      # vehicles and street props
$BLENDER -b --factory-startup --python tools/blender/build_buildings.py  # buildings and data/building_catalog.json
python3 tools/configure_imports.py                                       # mobile texture import presets
```

## Layout

| Path | Contents |
|---|---|
| `src/sim/` | Authoritative simulation: pure logic, integer state, no nodes. |
| `src/core/` | Content loading (`Content`) and the client session (`Game`). |
| `src/world/` | Rendering: district layout, roads, block chunks, crews, traffic, shaders. |
| `src/camera/` | Strategy camera (touch, mouse, keyboard). |
| `src/ui/` | HUD, selection panels, world markers, theme. |
| `src/main/`, `scenes/` | Entry scene and world-map controller. |
| `data/` | Data-driven content. `materials.json` and `building_catalog.json` are generated. |
| `assets/` | Generated models and textures, fonts (OFL), branding, UI icons. |
| `tools/blender/` | Python asset pipeline. |
| `tests/` | Headless test suite. |
| `art_source/` | Full-resolution source art (not imported). |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design and the roadmap.
