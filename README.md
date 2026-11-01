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

## Exporting

`export_presets.cfg` defines Android (arm64) and iOS presets that include
`data/**/*.json` and exclude source art, tests and tools. Install the Godot
4.7.2 export templates (Editor > Manage Export Templates), then for Android an
SDK/JDK and keystore, for iOS a team ID and signing. A content pack can be
built without templates: `--export-pack "Android" build/empire.pck`.

## Visual capture and benchmarks

Benchmarks: add `--benchmark=<seconds>` (vsync off, frame-time percentiles,
draw calls, primitives, VRAM) and pass `--windowed --resolution 1600x900`
before `--` so the window size is comparable. Profiling switches:
`--no-shadows`, `--no-detail`, `--no-traffic`, `--no-probe`, `--no-blur`,
`--no-compress`.

```sh
$GODOT --path . -- --new-game --capture=/tmp/shot.png --capture-delay=5 --stats \
  --view=-80,-30,75,-32 \
  '--command={"type":"move_crew","crew":"crew_mulberry","landmark":"lm_grand_freight"}' \
  --select=crew:crew_mulberry
```

## The world

The game streams **Greater New York 1977** (`data/world/nyc_1977.json`, a
12.8 × 15.3 km compressed New York: Manhattan, Brooklyn, Queens, the Bronx,
rivers, nine bridges, 50 neighbourhoods) with Little Italy preserved at its
original coordinates. The data is authored by `tools/geography/nyc_blueprint.py`
(see `docs/GEOGRAPHY_BLUEPRINT.md`); `tools/geography/render_world.py` renders the
generated in-game layout (dump it with `tests/tools_geo_dump.gd`). The first
province is still available: `-- --world=greater_new_york`.

## Regenerating art (Blender 5.2)

```sh
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
$BLENDER -b --factory-startup --python tools/blender/build_textures.py   # textures, palette, data/materials.json
$BLENDER -b --factory-startup --python tools/blender/build_props.py      # vehicles and street props
$BLENDER -b --factory-startup --python tools/blender/build_buildings.py  # buildings and data/building_catalog.json
$BLENDER -b --factory-startup --python tools/blender/build_licensed_vehicles.py  # licensed cars (+ lean traffic variants)
$BLENDER -b --factory-startup --python tools/blender/build_pbr_textures.py       # Poly Haven 2K -> 1K PBR sets
$BLENDER -b --factory-startup --python tools/blender/build_licensed_buildings.py  # licensed skyscrapers + Brooklyn building
python3 tools/geography/nyc_blueprint.py                                 # geography data + blueprint maps
python3 tools/configure_imports.py                                       # mobile texture import presets (idempotent)
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
| `assets/` | Models (generated + `vehicles/licensed`), textures (generated + `pbr/`), audio (`ambience/`, `events/`, `music/`, `sfx/`), fonts (OFL), branding, UI icons. |
| `data/world/` | Province definitions (regions, arterials, piers, bridges, backdrops). |
| `tools/blender/` | Python asset pipeline. |
| `tests/` | Headless test suite. |
| `art_source/` | Full-resolution and third-party sources (not imported; see docs/CREDITS.md). |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design and the roadmap.
