# Architecture

## Layers

```
data/*.json ──► GameContent ──┐
                              ▼
DistrictLayout ──► RoadGraph ─► SimWorld  ◄── commands ── Game (session) ◄── Main / HUD
      │                         │ events ───────────────────►│
      ▼                         ▼                            ▼
CityWorld (chunks, landmarks)   state read-only ─────► CrewView, WorldMarkers, panels
```

### Simulation (`src/sim`)

The simulation runs in `SimWorld`. It is pure logic, so it can later run unchanged on a
headless Godot server.

- **Integer state only.** Dollars, centimetres and milliseconds, plus a seeded
  xorshift RNG. This makes it deterministic; `test_simulation_is_deterministic` proves it.
- **Commands in, events out.** Every change goes through `execute({"type": ...})`.
  A command is validated against ownership, cash, level caps and similar rules. This is the
  same contract a server will expose.
- **Time-driven, not tick-driven.**
  - Business income is computed from timestamps: `stored = min(cap, banked + rate × Δt)`.
  - Crew position is a function of the departure and arrival times.
  - `advance_to(t)` processes due timers (arrivals, upgrades, AI) in timestamp order.

  Offline progress is therefore exact, and frame rate never affects outcomes.
- **Saves.** `to_dict()` / `from_dict()` round-trip losslessly. The client writes
  `user://saves/slot_0.json` atomically (temp file then rename). It saves every 15 s when
  something has changed, when the app is paused or backgrounded, and on exit.
- **Power and defence.** These come from `PowerCalculator`, using data-driven tiers and
  permille modifiers:
  - capo leadership
  - vehicle bonus
  - research (not yet used)

  Future combat resolution belongs here too, with seeded rolls, so that higher power
  reliably wins.

### Moving to server authority

`Game.execute()` is the only place commands enter. To go online, this method sends the
command to the server and applies the authoritative snapshot or events that come back;
the views stay the same. The server should use the server clock for timestamps
(`Game.now_ms()` is local time today), and the rival AI moves server-side.

### World rendering (`src/world`)

- **District layout.** `DistrictLayout` turns a district JSON into everything the world
  needs. It is deterministic, seeded and covered by tests:
  - streets and intersections
  - blocks
  - building lots (corners, mid-block fill, landmark slots)
  - street furniture
  - parking spots
  - the road graph
- **Draw calls.** `CityWorld` merges each block's buildings, sidewalk and props into
  one mesh, with one surface per material. The whole district renders in about 36–45 draw
  calls on desktop, with per-block frustum culling.
- **Materials.**
  - Every flat-colour material lives in one palette atlas; Blender points those faces' UVs
    at a swatch. As a result a building has about 7 surfaces instead of 15.
  - `MaterialLibrary` builds shared ShaderMaterials from `data/materials.json`.
  - There is one shared surface shader (`world_surface.gdshaderinc`) with variants:
    - opaque
    - double-sided
    - occlusion cutout
    - instanced tint
- **Occlusion.** `OcclusionFader` publishes up to two targets as global shader
  parameters: the selected crew and the followed crew. It swaps the cutout variant only
  onto chunks that cross a camera-to-target sightline, because shaders that discard pixels
  are expensive on mobile tile-based GPUs.
- **Roads.** Markings are drawn in `road.gdshader` from per-vertex metadata: centre lines,
  lane dashes, crosswalks and stop lines. They stay crisp at any zoom.
- **Crews.** `CrewView` maps the simulation's progress onto a `LanePath` (right-hand
  lane, rounded corners). `TrafficSystem` is presentation-only ambient traffic, drawn as
  MultiMesh. It obeys a 30 s signal cycle and queues behind cars and crews.

### Assets (`tools/blender`)

- Generators are parametric Python (`empire/buildings.py`, `vehicles.py`, `props.py`).
- Textures are procedural and tileable (`empire/textures.py`).
- GLBs ship without textures. Godot remaps material names to the shared library, so each
  texture exists once in GPU memory.
- `tools/configure_imports.py` pins texture import settings: ASTC/ETC2 VRAM compression
  on mobile, mipmaps, and normal-map handling.

## Measured on an Apple M3 Pro (desktop, 1600×900)

| Metric | Value |
|---|---|
| Frame rate | 120 fps (vsync-capped) |
| Draw calls, strategic view | 36 (world only) / ~230 (with HUD) |
| Primitives, including the shadow pass | ~1.1–1.3 M |
| City build at startup | 2.0–6.3 s |
| VRAM | 237–289 MB |

## Known gaps and next steps

1. **Mobile performance.** None of this has been run on a phone yet.
   - Move chunk merging to build time (export pre-merged block meshes) to cut startup time.
   - Add LOD or impostor roofs for distant blocks to bring primitive counts down.
   - Profile on a mid-range Android device and an iPhone.
   - Add export presets, including `data/*.json`, and check that the JSON is packed in an
     exported build.
2. **Combat milestone.** Soldier models and animation, attack/defend/reinforce commands,
   seeded combat resolution in `SimWorld`, battle visuals (muzzle flashes, smoke, retreat),
   and anti-bullying rules (attack cooldowns, shields).
3. **HQ management view.** A separate scene that edits `HeadquartersState` facilities
   through new commands.
4. **Chapters.** Data-driven story chapters (dialogue, objectives, unlocks, rewards) using
   simulation events as objective triggers.
5. **Backend.** A headless authoritative server running `SimWorld`, with family
   membership caps and territory rules.
