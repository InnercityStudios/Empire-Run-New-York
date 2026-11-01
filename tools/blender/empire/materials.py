"""Single source of truth for world materials.

Blender uses this to assign named materials (with preview colours) and to scale
UVs in metres; `export_material_library` writes data/materials.json, which
Godot's MaterialLibrary uses to build the shared, texture-backed runtime
materials. Exported GLBs carry no textures, so every building shares one copy
of each texture in GPU memory.

Fields:
  color      sRGB albedo multiplier (hex)
  albedo     texture under res://assets/textures (optional)
  normal     normal map texture (optional)
  uv_m       metres covered by one texture repeat (world-scaled UVs)
  roughness, metallic, normal_scale
  emission   hex colour, emission_energy
  cull       "back" (default) or "disabled"
  animated   keeps a dedicated material so Godot can animate it (signals)
  tint       albedo is multiplied by a per-instance tint in Godot (car paint)
  arm        packed ambient occlusion / roughness / metalness texture (PBR sets)
  uv_scale   runtime UV multiplier (lets a photographic set use its true scale)

Palette: every untextured, non-animated material is packed into one swatch of
a shared palette atlas (albedo, roughness/metallic/tint-mask, emission). The
mesh builder points all UVs of such faces at the swatch centre, so an entire
building's trim, ironwork, signage and neon renders as a single surface.
"""
import json
import os

TEX = "res://assets/textures/"

MATERIALS = {
    # --- Masonry -------------------------------------------------------------
    # Photographic brick (Poly Haven brick_wall_006, CC0): 2.85 m tile vs 2.4 m UVs.
    "M_Brick_Red":    {"grime": 1.0, "color": "#d6c2b8", "albedo": "pbr/brick_wall_006_albedo.png", "normal": "pbr/brick_wall_006_normal.png", "arm": "pbr/brick_wall_006_arm.png", "uv_m": 2.4, "uv_scale": 0.84, "roughness": 0.92},
    "M_Brick_Brown":  {"grime": 1.0, "color": "#ffffff", "albedo": "brick_brown_albedo.png", "normal": "brick_normal.png", "uv_m": 2.4, "roughness": 0.92},
    "M_Brick_Tan":    {"grime": 1.0, "color": "#ffffff", "albedo": "brick_tan_albedo.png", "normal": "brick_normal.png", "uv_m": 2.4, "roughness": 0.9},
    "M_Brick_Dark":   {"grime": 0.8, "color": "#ffffff", "albedo": "brick_dark_albedo.png", "normal": "brick_normal.png", "uv_m": 2.4, "roughness": 0.93},
    "M_Brick_Painted": {"grime": 1.1, "color": "#d9cdb4", "albedo": "brick_painted_albedo.png", "normal": "brick_normal.png", "uv_m": 2.4, "roughness": 0.85},
    "M_Stone":        {"grime": 0.8, "color": "#ffffff", "albedo": "stone_albedo.png", "normal": "stone_normal.png", "uv_m": 2.0, "roughness": 0.85},
    "M_Concrete":     {"grime": 1.0, "color": "#b9b3a8", "albedo": "stone_albedo.png", "normal": "stone_normal.png", "uv_m": 3.0, "roughness": 0.95},
    "M_Sidewalk":     {"grime": 0.7, "color": "#ffffff", "albedo": "sidewalk_albedo.png", "normal": "sidewalk_normal.png", "uv_m": 3.0, "roughness": 0.9},
    "M_Curb":         {"grime": 0.7, "color": "#c9c3b6", "albedo": "stone_albedo.png", "normal": "stone_normal.png", "uv_m": 2.0, "roughness": 0.8},
    "M_Roof_Tar":     {"grime": 0.5, "color": "#ffffff", "albedo": "roof_tar_albedo.png", "normal": "roof_tar_normal.png", "uv_m": 4.0, "roughness": 0.9},
    "M_Roof_Silver":  {"grime": 0.6, "color": "#ffffff", "albedo": "roof_silver_albedo.png", "normal": "roof_silver_normal.png", "uv_m": 4.0, "roughness": 0.55, "metallic": 0.25},
    "M_Roof_Gravel":  {"grime": 0.5, "color": "#ffffff", "albedo": "roof_gravel_albedo.png", "normal": "roof_gravel_normal.png", "uv_m": 4.0, "roughness": 0.95},
    "M_Siding_White":  {"grime": 0.6, "color": "#e4ddcd", "albedo": "siding_albedo.png", "normal": "siding_normal.png", "uv_m": 2.0, "roughness": 0.75},
    "M_Siding_Green":  {"grime": 0.6, "color": "#7d9a84", "albedo": "siding_albedo.png", "normal": "siding_normal.png", "uv_m": 2.0, "roughness": 0.75},
    "M_Siding_Yellow": {"grime": 0.6, "color": "#d9c38a", "albedo": "siding_albedo.png", "normal": "siding_normal.png", "uv_m": 2.0, "roughness": 0.75},
    "M_Siding_Blue":   {"grime": 0.6, "color": "#8da2b4", "albedo": "siding_albedo.png", "normal": "siding_normal.png", "uv_m": 2.0, "roughness": 0.75},
    "M_Shingle_Gray":  {"grime": 0.5, "color": "#6b6a66", "albedo": "shingle_albedo.png", "normal": "shingle_normal.png", "uv_m": 3.0, "roughness": 0.9},
    "M_Shingle_Brown": {"grime": 0.5, "color": "#7a5a44", "albedo": "shingle_albedo.png", "normal": "shingle_normal.png", "uv_m": 3.0, "roughness": 0.9},
    "M_Shingle_Slate": {"grime": 0.4, "color": "#4a5058", "albedo": "shingle_albedo.png", "normal": "shingle_normal.png", "uv_m": 3.0, "roughness": 0.8},
    "M_Grass":         {"color": "#ffffff", "albedo": "grass_albedo.png", "uv_m": 6.0, "roughness": 0.95},
    "M_Gravel":        {"grime": 0.4, "color": "#ffffff", "albedo": "roof_gravel_albedo.png", "normal": "roof_gravel_normal.png", "uv_m": 4.0, "roughness": 0.95},
    "M_Quay":          {"grime": 1.0, "color": "#9a958c", "albedo": "stone_albedo.png", "normal": "stone_normal.png", "uv_m": 3.0, "roughness": 0.9},
    "M_Roof":         {"grime": 0.6, "color": "#ffffff", "albedo": "roof_albedo.png", "uv_m": 4.0, "roughness": 0.95},
    # --- Architectural trim ---------------------------------------------------
    "M_Cornice_Dark":  {"color": "#2b2a27", "roughness": 0.7},
    "M_Cornice_Green": {"color": "#2f4a3a", "roughness": 0.7},
    "M_Cornice_Cream": {"color": "#cfc4a6", "roughness": 0.75},
    "M_Frame_White":   {"color": "#d8d2c2", "roughness": 0.6},
    "M_Frame_Dark":    {"color": "#2a2622", "roughness": 0.6},
    "M_Iron":          {"color": "#1d1c1b", "roughness": 0.55, "metallic": 0.3, "cull": "disabled"},
    "M_Tile":          {"color": "#cfc6b2", "roughness": 0.35},
    "M_Door":          {"color": "#3b2618", "roughness": 0.6},
    "M_Window":        {"specular": 0.6, "color": "#ffffff", "albedo": "window_atlas.png", "roughness": 0.15, "emission_tex": "window_emission.png", "emission": "#ffd9a0", "emission_energy": 0.0},
    "M_ShopGlass":     {"specular": 0.6, "color": "#ffffff", "albedo": "shop_atlas.png", "roughness": 0.12, "emission_tex": "shop_atlas.png", "emission": "#ffcf8a", "emission_energy": 0.25},
    "M_Shutter":       {"grime": 0.6, "color": "#8d8b85", "albedo": "corrugated_albedo.png", "normal": "corrugated_normal.png", "uv_m": 1.0, "roughness": 0.6, "metallic": 0.4},
    "M_Shutter_Green": {"grime": 0.6, "color": "#4f6b58", "albedo": "corrugated_albedo.png", "normal": "corrugated_normal.png", "uv_m": 1.0, "roughness": 0.6, "metallic": 0.3},
    "M_Shopfront_Red":   {"color": "#5a1b17", "roughness": 0.55},
    "M_Shopfront_Green": {"color": "#1f3a2c", "roughness": 0.55},
    "M_Shopfront_Black": {"color": "#141312", "roughness": 0.5},
    "M_Shopfront_Cream": {"color": "#c9b994", "roughness": 0.6},
    "M_Awning":        {"color": "#ffffff", "albedo": "awning_atlas.png", "roughness": 0.85, "cull": "disabled"},
    "M_Sign_Board":    {"color": "#ffffff", "roughness": 0.6},
    "M_Sign_Gold":     {"color": "#c9a24a", "roughness": 0.35, "metallic": 0.7},
    "M_Sign_White":    {"color": "#eee6d2", "roughness": 0.5},
    "M_Sign_Black":    {"color": "#151413", "roughness": 0.5},
    "M_Neon_Red":      {"color": "#ff4a3a", "emission": "#ff3a2a", "emission_energy": 2.2, "roughness": 0.3},
    "M_Neon_Green":    {"color": "#6dffa0", "emission": "#4dff8a", "emission_energy": 1.8, "roughness": 0.3},
    "M_Neon_Gold":     {"color": "#ffd27a", "emission": "#ffc04d", "emission_energy": 1.8, "roughness": 0.3},
    "M_Wood":          {"grime": 0.5, "color": "#ffffff", "albedo": "wood_albedo.png", "uv_m": 2.0, "roughness": 0.9},
    "M_Tarpaper":      {"color": "#2a2826", "roughness": 0.95},
    "M_MetalGalv":     {"color": "#9a9a95", "roughness": 0.45, "metallic": 0.6},
    "M_AC_Unit":       {"color": "#c8c1ae", "roughness": 0.55, "metallic": 0.2},
    "M_Gold_Trim":     {"color": "#b8913f", "roughness": 0.3, "metallic": 0.85},
    # --- Vehicles ---------------------------------------------------------------
    "M_CarPaint":      {"color": "#0d0d0f", "tint": True, "roughness": 0.22, "metallic": 0.35},
    "M_CarPaint_Taxi": {"color": "#e8b21c", "roughness": 0.3, "metallic": 0.2},
    "M_CarPaint_Truck": {"color": "#e6e0d2", "roughness": 0.45, "metallic": 0.1},
    "M_VinylRoof":     {"color": "#161514", "roughness": 0.7},
    "M_Chrome":        {"color": "#d8d8d8", "roughness": 0.12, "metallic": 1.0},
    "M_CarGlass":      {"color": "#1a2228", "roughness": 0.05, "metallic": 0.4},
    "M_Tire":          {"color": "#141414", "roughness": 0.9},
    "M_Whitewall":     {"color": "#e8e4da", "roughness": 0.7},
    "M_Headlight":     {"color": "#f4f0dc", "emission": "#fff2c8", "emission_energy": 0.6, "roughness": 0.1},
    "M_Taillight":     {"color": "#8a1010", "emission": "#ff2010", "emission_energy": 0.4, "roughness": 0.2},
    "M_CarInterior":   {"color": "#3a2a20", "roughness": 0.8},
    "M_Grille":        {"color": "#202020", "roughness": 0.4, "metallic": 0.6},
    # --- Street props -----------------------------------------------------------
    "M_PoleGreen":     {"color": "#2c3d32", "roughness": 0.6, "metallic": 0.3},
    "M_LampGlass":     {"color": "#fff1c9", "emission": "#ffe2a0", "emission_energy": 0.4, "roughness": 0.2},
    "M_SignalHousing": {"color": "#c9a227", "roughness": 0.55},
    "M_SignalRed":     {"animated": True, "color": "#3a0b08", "emission": "#ff2a1a", "emission_energy": 0.0, "roughness": 0.2},
    "M_SignalAmber":   {"animated": True, "color": "#3a2a08", "emission": "#ffaa1a", "emission_energy": 0.0, "roughness": 0.2},
    "M_SignalGreen":   {"animated": True, "color": "#0a2a18", "emission": "#30ff8a", "emission_energy": 0.0, "roughness": 0.2},
    "M_SignalRed_EW":   {"animated": True, "color": "#3a0b08", "emission": "#ff2a1a", "emission_energy": 0.0, "roughness": 0.2},
    "M_SignalAmber_EW": {"animated": True, "color": "#3a2a08", "emission": "#ffaa1a", "emission_energy": 0.0, "roughness": 0.2},
    "M_SignalGreen_EW": {"animated": True, "color": "#0a2a18", "emission": "#30ff8a", "emission_energy": 0.0, "roughness": 0.2},
    "M_HydrantRed":    {"color": "#9c1f17", "roughness": 0.55},
    "M_MailBlue":      {"color": "#24426e", "roughness": 0.5},
    "M_Bark":          {"color": "#4a3d33", "roughness": 0.95},
    "M_Foliage":       {"color": "#ffffff", "albedo": "foliage_albedo.png", "uv_m": 1.5, "roughness": 0.85},
    "M_TrashWire":     {"color": "#5d605c", "roughness": 0.5, "metallic": 0.5, "cull": "disabled"},
    "M_TrashBag":      {"color": "#161616", "roughness": 0.35, "metallic": 0.0},
    "M_SubwayGlobe":   {"color": "#9fe0a8", "emission": "#7dff9a", "emission_energy": 1.2, "roughness": 0.2},
    "M_PaperBox":      {"color": "#b8312a", "roughness": 0.5},
}


PALETTE_NAME = "M_Palette"
PALETTE_GRID = 16  # 16 x 16 swatches
PALETTE_SWATCH_PX = 16
PALETTE_EMISSION_SCALE = 4.0  # emission texture stores energy / scale


def get(name):
    return MATERIALS[name]


def is_palette(name):
    m = MATERIALS[name]
    return "albedo" not in m and not m.get("animated")


def palette_names():
    return [n for n in MATERIALS if is_palette(n)]


def palette_uv(name):
    """UV (Blender convention, v up) of the swatch centre for `name`."""
    i = palette_names().index(name)
    col, row = i % PALETTE_GRID, i // PALETTE_GRID
    return ((col + 0.5) / PALETTE_GRID, 1.0 - (row + 0.5) / PALETTE_GRID)


def export_material_library(path):
    lib = {
        PALETTE_NAME: {
            "albedo": TEX + "palette_albedo.png",
            "orm": TEX + "palette_orm.png",
            "emission_tex": TEX + "palette_emission.png",
            "emission": "#ffffff",
            "emission_energy": PALETTE_EMISSION_SCALE,
            "palette": True,
            "grime": 0.35,
            "cull": "disabled",
        }
    }
    for name, m in MATERIALS.items():
        if is_palette(name):
            continue
        entry = dict(m)
        for key in ("albedo", "normal", "emission_tex", "arm"):
            if key in entry:
                entry[key] = TEX + entry[key]
        lib[name] = entry
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump({"version": 1, "materials": lib}, f, indent=2, sort_keys=True)
