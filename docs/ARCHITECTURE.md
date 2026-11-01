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

## World and streaming (`src/world`, `src/world/stream`)

- **WorldLayout** composes a province from `data/world/*.json`. Grid regions
  reuse `DistrictLayout` with fill styles (tenement, industrial, rowhouse,
  towers, civic, suburban, waterfront, park). Little Italy is built from its
  unchanged definition: a golden fingerprint test proves its 381 lots are
  bit-identical inside the world. Road nodes merge by integer-cm position,
  arterials are stitched to every region road that meets them, piers get
  roads, and the Delancey Bridge ends at a future-city portal node. Building
  lots have stable ids (`<region>:<n>`); road locations persist by node key,
  so saves survive world growth (save v2, v1 migrates).
- **Geography worlds** (`schema: geography-v1`, `GeographyBuilder`): coastlines,
  borough and district polygons, parks, polyline arterials and bridges from
  `data/world/nyc_1977.json`. Little Italy is built unchanged at its original
  coordinates. Districts sharing a grid (Manhattan's) share one lattice; blocks
  shrink to fit coastlines, district borders, parks and plazas, and split where
  an arterial crosses them. Streets, Little Italy's edges, arterial and bridge
  ends are stitched into one graph; leftover islands are linked or dropped.
  Generated blocks store no lots: `BlockFiller` derives buildings, props and
  parking per chunk from the block seed (only Little Italy's 381 lots are
  stored). Save v3 records the world id; loading a save from another map keeps
  every crew, soldier and destination and re-routes travelling convoys.
- **Three presentation tiers** (geography worlds): province overview (one
  MultiMesh of block massing per 1 km tile plus scenery backdrop and landmark
  towers, resident), mid-distance massing (one box per building, streamed to
  `mid_radius`), full detail (streamed to `detail_radius`). Each chunk shows
  exactly one tier, swapped when the finer one is ready, so there are no gaps.
- **Chunks**: 256 m cells with stable integer coordinates.
- **Always resident** (`WorldShellBuilder`, `FarCityBuilder`): water, land and
  region grounds, quays, per-chunk road meshes, bridge, park lake/paths and a
  far-city LOD (one ~10-triangle box per building, procedural windows) for the
  whole province: ~125 k triangles. There is never empty terrain or a hard
  edge; backdrop districts fill the far shores and the north.
- **Streamed detail** (`WorldStreamer`, `ChunkDetailBuilder`, `MeshMerger`):
  full-detail chunks inside a zoom-dependent radius (220 m when close, none at
  the strategic zoom), built on `WorkerThreadPool` from cached asset arrays
  without touching the RenderingServer, uploaded on the main thread, unloaded
  with hysteresis. Landmarks, crews and traffic are always present.
- **Routing** is independent of visuals: the simulation's road graph covers
  the whole province regardless of which chunks are loaded.
- **Inspection**: `scenes/world/world_preview.tscn` (@tool) and
  `tests/tools_world_map.gd` (top-down PNG).

### Preparation: build time vs runtime
Expensive generation is export-time: Blender produces all models, LOD
vehicle variants, textures and the material library. At runtime the layout
is deterministic and cheap (0.25–0.45 s for the province), the shell and far
city build in ~0.3 s, and detail chunks are meshed on worker threads (≤0.35 s
each on the M3 Pro). Baking detail chunk meshes to disk was rejected: a dense
chunk is ~0.54 M triangles (~10 MB), which would add hundreds of MB to the
app. Next step if devices need it: a first-visit on-device chunk cache.

## Greater New York 1977 (Phase 2), Apple M3 Pro, 1600×900, `--benchmark=5`

Frame times are at the display cap and do not discriminate on this Mac.
Not measured on phones.

| View | Avg / p95 frame | Draw calls | Primitives (incl. shadows) | VRAM |
|---|---|---|---|---|
| Close, Little Italy (80 m) | 8.9 / 9.8 ms | 174 | 2.84 M | 914 MB* |
| Mid, Little Italy (200 m) | 8.3 / 11.9 ms | 181 | 3.49 M | 389 MB |
| Close, Bed-Stuy (90 m) | 8.4 / 12.7 ms | 164 | 1.62 M | 395 MB |
| Strategic (700 m) | 8.9 / 23.4 ms | 136 | 61 k | 321 MB |
| Province overview (2.6 km) | 8.4 / 13.0 ms | 132 | 40 k | 311 MB |

\*One run; repeat runs at the same view report ~400 MB. Peaks of 800–950 MB
also appear in the first province after heavy chunk streaming, so this is a
pre-existing streaming/VRAM accounting issue to investigate on device.
Layout build: 2–4 s (desktop); 5,269 generated blocks, 10,115 road nodes.

## Measured on an Apple M3 Pro (desktop, 1600×900)

Greater New York streaming build (`--benchmark=5`, forced 1600×900). Frame
times sit at the 120 Hz display cap and do not discriminate on this Mac;
primitives, draw calls and VRAM are the meaningful numbers.

| Zoom | Avg frame | Draw calls | Primitives (incl. shadows) | VRAM |
|---|---|---|---|---|
| Close (80 m) | 6.9 ms | 163 | 2.47 M | 377 MB |
| Mid (200 m) | 8.0 ms | 173 | 3.41 M | 362 MB |
| Strategic (700 m) | 7.2 ms | 154 | 1.57 M | 349 MB |

Profiling results that shaped the design: two shadow cascades cost ~3 M
primitives (now one, footprint-scaled); `SurfaceTool.append_from` on worker
threads blocked on the RenderingServer (2.9 s per chunk → 0.2 s with
`MeshMerger`); the default 64-slot reflection atlas cost ~270 MB VRAM (now
2 slots); licensed traffic cars at 10 k triangles (now 2.6 k variants).

**Not measured on devices** (no device, export templates or Android SDK in
this environment). Mobile risks to verify first: 2.5–3.4 M primitives at
close/mid zoom and ~0.5 M triangles per dense detail chunk.

## Earlier Little Italy measurements (desktop, 1600×900)

| Metric | Value |
|---|---|
| Frame rate | 120 fps (vsync-capped) |
| Draw calls, strategic view | 36 (world only) / ~230 (with HUD) |
| Primitives, including the shadow pass | ~1.1–1.3 M |
| City build at startup | 2.0–6.3 s |
| VRAM | 237–289 MB |

## Known gaps and next steps

1. **Mobile performance.** Not yet run on a phone.
   - Profile on a mid-range Android device and an iPhone (presets ready).
   - If primitives are too high: per-building-variant instancing with a facade
     texture atlas (1–2 materials per building), or a mid-distance block LOD
     between detail and the far boxes.
2. **Combat milestone.** Soldier models and animation, attack/defend/reinforce commands,
   seeded combat resolution in `SimWorld`, battle visuals (muzzle flashes, smoke, retreat),
   and anti-bullying rules (attack cooldowns, shields).
3. **HQ management view.** A separate scene that edits `HeadquartersState` facilities
   through new commands.
4. **Chapters.** Data-driven story chapters (dialogue, objectives, unlocks, rewards) using
   simulation events as objective triggers.
5. **Backend.** A headless authoritative server running `SimWorld`, with family
   membership caps and territory rules.
