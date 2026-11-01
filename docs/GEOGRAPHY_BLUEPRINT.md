# Greater New York 1977 — Geography Blueprint (Phase 1)

Status: **proposal awaiting approval**. Nothing in the running game has changed:
`GameContent` still loads `data/world/greater_new_york.json`; the blueprint
data is not read by any game code yet. Tests: 37 passed, 0 failed.

| Artefact | Path |
|---|---|
| Province map (labelled) | `docs/geography/nyc_1977_blueprint.png` |
| Little Italy placement close-up | `docs/geography/lower_manhattan.png` |
| Geography data (schema `geography-v1`) | `data/world/nyc_1977_blueprint.json` |
| Generator + validation | `tools/geography/nyc_blueprint.py` (`python3 tools/geography/nyc_blueprint.py`) |

Automated checks (run by the generator): Little Italy lies wholly inside
Manhattan; all 50 district seeds are on land; every road polyline stays on land
(bridges excepted).

## 1. Can the current 3.4 × 3.1 km province hold New York?

No. Today's land is ~10.5 km². Four recognisable boroughs need, at minimum:
Manhattan as a long island with distinct downtown/midtown/uptown bands, two
real rivers you have to bridge, and outer boroughs big enough to hold several
neighbourhoods each. At 3.4 km Manhattan would be ~2.5 km long; Little Italy
alone (444 × 394 m) would be a sixth of it, and every neighbourhood would be
a single block.

**Recommendation: a 12.8 × 15.3 km world frame with ~86 km² of playable land**
(variable compression, like a tourist map):

| Area | Game size | Real size | Compression |
|---|---|---|---|
| Manhattan | 7.5 km long, 1.2–2.4 km wide, 14.3 km² | 21.6 km, 59 km² | ~1:2.9 length, Lower Manhattan ~1:1.3 |
| Brooklyn (playable part) | 35.9 km² | 180 km² | ~1:2.5 linear |
| Queens (west/central) | 22.3 km² | 280 km² | partial borough |
| The Bronx (south/central) | 13.9 km² | 110 km² | partial borough |
| Hudson / East River | 0.8–1.0 / 0.35–0.6 km | 1.3 / 0.25–1.2 km | crossings stay meaningful |

Little Italy is kept at **1:1** (it is the authored hero district); density
falls off with distance from it. Travel: arterials are 13–19 m/s in the
simulation, so Little Italy → Midtown ≈ 2 min, → Williamsburg ≈ 2.5 min,
→ Bronx/Flushing ≈ 6–7 min of game time. That suits strategic convoys; if it
feels long, it is one speed table in data, not geometry.

## 2. Coordinate frame and transforms

- Units metres, **+X east, +Z south** (unchanged), north is screen-up in the
  overview.
- **Little Italy anchor: translation (0, 0), rotation 0.** Its 381 lots,
  road-node keys (integer cm) and landmark positions are bit-identical; the
  golden fingerprint `381:708f77ce754b9eda` must still pass.
- Manhattan's spine leans east going north (`x = 50 + 0.42·(−z)`, ~23°), so
  the uptown grid rotates by 22.8° while Lower Manhattan stays axis-aligned —
  just as the real street grid changes angle at Houston/14th.
- Each district declares its own grid frame (`grid.angle`, `grid.pitch`).
  Phase 2 adds `DistrictFrame`: `world = origin + R(angle)·local`. The
  existing `DistrictLayout` keeps working in local axis-aligned space and is
  transformed as a whole, so the block/lot code needs no rotation support.
- Chunk index stays 256 m on the world axes (≈1,320 land chunks).

## 3. Data structure (`geography-v1`)

```
extent, chunk_size, frame
anchors.little_italy {translation, rect, district}
landmasses[]  {id, name, borough, kind: playable|scenery, polygon}
waterways[]   {id, name, label_at, angle}         water = everything not land
parks[]       {id, name, kind, polygon, lakes[]}
districts[]   {id, name, borough, style, seed, polygon?, grid{angle,pitch,irregular?},
               territory, preserved?, area_km2}
styles{}      {label, color, floors[min,max], density}   neighbourhood generation rules
roads[]       {id, name, class: expressway|parkway|arterial|avenue, width, speed, path[]}
bridges[]     {id, name, kind, width, speed, path[], connects[a,b], branch?}
landmarks[]   {id, name, pos, kind}
territory_seed{district_id: player|rival|contested|neutral}
```

- District shapes are **seed cells clipped to their landmass** (explicit
  polygons win: Little Italy, LaGuardia). Phase 2 bakes these into polygons
  in the JSON so territory borders are stable data, not a by-product of the
  generator.
- Roads are polylines; local street grids are generated *inside* districts
  and stitched to the arterial network (the existing WorldLayout stitching).
- Bridges are graph edges with decks, approaches and a `connects` pair for
  chokepoint logic. Nine are defined: Brooklyn, Manhattan, Williamsburg,
  Queensboro, Triborough (with Bronx branch), Willis Ave, Macombs Dam,
  Pulaski, Kosciuszko.
- Territory: 50 districts with ownership seeds; bridges and their plazas are
  the natural chokepoints; contested = Hell's Kitchen, East Village, Harlem,
  Williamsburg, Greenpoint, Bushwick, Bed-Stuy.
- Extensibility: Staten Island is a `scenery` landmass that becomes
  `playable` by changing `kind` and adding districts + a Verrazzano/ferry
  bridge. Weather, night, seasons and holidays attach to `styles` (per-style
  palettes and decals) and to global shader params; no geography change.

## 4. Presentation tiers

| Tier | Camera | Content | Budget target |
|---|---|---|---|
| Local detail | < 250 m | Existing threaded detail chunks (full buildings, props, traffic) | ≤ 1.2 M primitives incl. shadows |
| Distant district | 250 m – ~2 km | **New:** per-chunk merged block massing (roof-height extrusions with baked facade texture), streamed by distance | ≈ 2–6 k tris per chunk |
| Province overview | > ~2 km | Baked top-down map tiles of this blueprint style + landmark silhouettes; territory overlay | < 150 k tris |

The camera's pitch already blends with distance (42°→60°); Phase 2 extends
the zoom range to the overview and uses the land footprint (playable
landmasses + 300 m) as camera bounds, so you never see past the generated
world. Scenery land (New Jersey, Long Island, south Brooklyn, Staten Island)
is rendered as cheap backdrop massing, never as void.

## 5. Migration plan

Saves (v2 → v3):
- Business, landmark, crew and vehicle IDs are unchanged (all start in
  Little Italy).
- Crew locations are node keys `"x,z"` (cm). Little Italy keys are identical
  in the new graph. A key not found in the new graph is parsed back to a
  point and snapped to the nearest node (the v1 migration already does this).
- Crews in transit: their stored route may reference removed nodes. v3
  migration cancels the move at its current interpolated position and
  re-issues it to the same destination landmark, preserving arrival order.
- Building lot IDs outside Little Italy (`<region>:<n>`) are not referenced by
  saves today; the new districts get new IDs (`<district>:<n>`) and the old
  18 regions are retired.

Code:
- `WorldLayout.build()` gains a geography loader; `greater_new_york.json`
  remains as a fallback until the new world passes all tests.
- `RoadGraph` is unchanged (position-keyed); new inputs are polyline roads and
  rotated district grids. Simulation stays independent of loaded chunks.
- Chunk streaming, MeshMerger, PBR materials, HUD, camera, audio and vehicles
  are reused as-is; only the shell/far builders are replaced by the tier 2/3
  builders.

Tests to add: Little Italy fingerprint inside the new world; every district
reachable from Little Italy by road; each bridge connects its declared
districts; v2 save → v3 round-trip; road polylines on land; chunk count and
far-tier triangle budgets.

## 6. Technical risks

1. **Scale of content.** At current densities the playable land implies
   ~120 k buildings. Full detail everywhere is impossible on mobile; the
   tier-2 massing must carry everything beyond 250 m. Mitigation: per-style
   density in data, and launch with a denser "core" (Lower Manhattan,
   Midtown, Williamsburg, LIC) while outer districts use lighter styles.
2. **Primitive budget.** Today's 2.5–3.4 M at close/mid zoom must come down
   in the same pass (shorter detail radius when tier 2 exists, instanced
   building variants, shadow caster culling).
3. **Rotated grids & polygon clipping.** Blocks clipped by shorelines and
   district borders create slivers; minimum lot size and corner rules needed.
   Grid seams between districts need connecting roads.
4. **Curved roads/bridges.** The road shader assumes straight segments
   (UV along/lateral); polylines need segmenting with mitred joints, and
   bridge decks need elevation, ramps and towers (new LanePath heights).
5. **Memory.** 1,320 chunks of tier-2 massing (~3 k tris) ≈ 4 M tris total;
   must stream, not stay resident like today's far city.
6. **Determinism.** The district generator must be seeded and fingerprinted
   per district so stable IDs survive data edits elsewhere.
7. **Travel times / gameplay.** Longer routes change crew timing balance;
   speeds are data and will need tuning.
8. **No device measurements yet.** All numbers are M3 Pro desktop; device
   profiling remains the first gate after Phase 2.

## Phases after approval

2. Integration: geography loader, district frames, polyline roads, bridges,
   save v3, tests. 3. Population: neighbourhood styles, tier-2 massing,
   overview tiles, landmarks. 4. Verification: benchmarks, fingerprint, saves.
