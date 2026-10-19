"""Texture and UV helpers for the WORLD-BASE-01 construction set (on top of fn_blender_lib).

Textures are generated procedurally with numpy (tileable by construction: FFT-filtered
noise and periodic patterns), saved as PNG under assets/structures/textures/ and used
by plain Principled materials, so the GLB export carries them and Godot imports them
with the mesh. Colours are baked into each texture (glTF base colour = texture), which
keeps the export rules trivial.

UVs are world-scale box projections: every face is projected along its dominant axis
and divided by the material's tile size in metres, so a 0.6 m texture tile is 0.6 m on
every asset and modules line up without visible seams.
"""
import math
import os

import bmesh
import bpy
import numpy as np

TEX_DIR = None
_TILE = {}      # material name -> metres per UV unit
_IMAGES = {}


def set_texture_dir(path):
    global TEX_DIR
    TEX_DIR = path
    os.makedirs(path, exist_ok=True)


# --- Noise and patterns (all periodic on the image size) -----------------------------

def fnoise(n, cut, seed, power=2.0):
    """Tileable noise in [0, 1]: white noise low-passed at `cut` cycles per tile."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((n, n))
    f = np.fft.fft2(white)
    fy = np.fft.fftfreq(n)[:, None] * n
    fx = np.fft.fftfreq(n)[None, :] * n
    r = np.sqrt(fx * fx + fy * fy)
    filt = 1.0 / (1.0 + (r / cut) ** (2.0 * power))
    out = np.real(np.fft.ifft2(f * filt))
    out -= out.min()
    out /= max(out.max(), 1e-9)
    return out


def fractal(n, seed, cuts=(2, 6, 18, 60), weights=(0.45, 0.3, 0.17, 0.08)):
    acc = np.zeros((n, n))
    for i, (c, w) in enumerate(zip(cuts, weights)):
        acc += fnoise(n, c, seed + 31 * i) * w
    acc -= acc.min()
    return acc / max(acc.max(), 1e-9)


def _rgb(base, shade):
    """base colour (3,) scaled by a shade field (n, n) -> (n, n, 3)."""
    return np.clip(np.asarray(base)[None, None, :] * shade[:, :, None], 0.0, 1.0)


def save_image(name, rgb, alpha=None, non_color=False):
    """Writes an (n, n, 3) float array (+ optional alpha) as PNG and returns the image."""
    n = rgb.shape[0]
    rgba = np.ones((n, n, 4), dtype=np.float32)
    rgba[:, :, :3] = rgb
    if alpha is not None:
        rgba[:, :, 3] = alpha
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    img = bpy.data.images.new(name, n, n, alpha=alpha is not None, float_buffer=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(rgba.ravel())
    path = os.path.join(TEX_DIR, name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    img.filepath = path
    _IMAGES[name] = img
    return img


def normal_from_height(h, strength):
    """Tangent-space normal map (OpenGL convention, as glTF) from a periodic height field."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength
    nz = np.ones_like(h)
    length = np.sqrt(dx * dx + dy * dy + nz * nz)
    return np.stack([(-dx / length) * 0.5 + 0.5, (-dy / length) * 0.5 + 0.5, (nz / length) * 0.5 + 0.5], axis=-1)


# --- Texture recipes -------------------------------------------------------------------

def tex_painted(name, color, n=512, seed=1, grime=0.22, chips=0.0):
    """Painted steel / container paint: broad fading, vertical rain streaks (V is up on
    walls with box_uv), fine speckle, a few soft dirt patches, optional paint chips."""
    shade = 1.0 - grime * 0.6 * (fnoise(n, 1.5, seed) - 0.5)
    shade *= 1.0 - 0.06 * (fnoise(n, 7, seed + 1) - 0.5)
    shade *= 0.985 + 0.03 * fnoise(n, 140, seed + 2)
    streak = fnoise(n, 40, seed + 3)[0, :][None, :]
    streak2 = fnoise(n, 3, seed + 4)
    shade *= 1.0 - grime * 0.35 * np.clip(streak - 0.45, 0.0, 1.0) * (0.6 + 0.8 * streak2)
    dirt = fnoise(n, 4, seed + 9)
    shade *= 1.0 - grime * 0.4 * np.clip((dirt - 0.65) * 3.0, 0.0, 1.0)
    rgb = _rgb(color, shade)
    if chips > 0.0:
        c = fnoise(n, 40, seed + 13)
        mask = np.clip((c - (1.0 - chips)) * 25.0, 0.0, 1.0)[:, :, None]
        rgb = rgb * (1 - mask) + np.array([0.33, 0.32, 0.30])[None, None, :] * mask
    return save_image(name, rgb)


def tex_concrete(name, color=(0.62, 0.61, 0.58), n=1024, seed=3):
    base = fractal(n, seed)
    shade = 0.84 + 0.22 * base
    pores = fnoise(n, 260, seed + 2)
    shade *= 1.0 - 0.35 * np.clip((pores - 0.8) * 6.0, 0.0, 1.0)
    stains = fnoise(n, 3, seed + 7)
    shade *= 1.0 - 0.12 * np.clip((stains - 0.55) * 3.0, 0.0, 1.0)
    return save_image(name, _rgb(color, shade))


def tex_fabric(name, color, n=512, seed=5, weave_px=4, dirt=0.25):
    y, x = np.mgrid[0:n, 0:n]
    weave = 0.5 + 0.5 * np.sin(2 * math.pi * x / weave_px) * np.sin(2 * math.pi * y / weave_px)
    shade = 0.93 + 0.06 * weave
    shade *= 1.0 - dirt * 0.7 * (fnoise(n, 1.5, seed) - 0.5)
    shade *= 1.0 - 0.05 * (fnoise(n, 10, seed + 1) - 0.5)
    stain = fnoise(n, 4, seed + 4)
    shade *= 1.0 - dirt * 0.4 * np.clip((stain - 0.62) * 3.0, 0.0, 1.0)
    return save_image(name, _rgb(color, shade))


def tex_hesco_liner(name, color, n=512, seed=21, cells=8):
    """Geotextile liner with the weld-mesh grid printed faintly into it, so the grid still
    reads at distance where the alpha mesh layer fades (same tile as tex_grid_mesh)."""
    y, x = np.mgrid[0:n, 0:n]
    weave = 0.5 + 0.5 * np.sin(2 * math.pi * x / 3) * np.sin(2 * math.pi * y / 3)
    shade = 0.94 + 0.05 * weave
    shade *= 1.0 - 0.1 * (fnoise(n, 1.5, seed) - 0.5)
    shade *= 1.0 - 0.05 * (fnoise(n, 10, seed + 1) - 0.5)
    period = n / cells
    gx = np.abs(((x + period / 2) % period) - period / 2) < 4
    gy = np.abs(((y + period / 2) % period) - period / 2) < 4
    rgb = _rgb(color, shade)
    grid = (gx | gy)[:, :, None]
    rgb = np.where(grid, rgb * 0.75 + np.array([0.55, 0.55, 0.52])[None, None, :] * 0.25, rgb)
    # Pillowing between wires: slightly darker toward each grid line.
    pil = (np.minimum(np.abs(((x + period / 2) % period) - period / 2), np.abs(((y + period / 2) % period) - period / 2)) / (period / 2))
    rgb *= (0.9 + 0.1 * np.clip(pil, 0, 1))[:, :, None]
    return save_image(name, np.clip(rgb, 0, 1))


def tex_wood(name, color, n=512, seed=7, grain=40):
    """Sawn timber / plywood: grain stretched along U, knots, weathering."""
    g = fnoise(n, grain, seed)
    g = np.repeat(g[:, :1], n, axis=1) * 0.5 + fnoise(n, grain, seed + 1) * 0.5  # mostly along x
    y, x = np.mgrid[0:n, 0:n]
    streak = np.sin(2 * math.pi * (y / n) * 23 + g * 6.0) * 0.5 + 0.5
    shade = 0.8 + 0.2 * streak
    shade *= 0.9 + 0.15 * fractal(n, seed + 3)
    return save_image(name, _rgb(color, shade))


def tex_grid_mesh(name, color=(0.62, 0.63, 0.61), n=512, cells=8, wire_px=5, seed=11):
    """Welded wire mesh (HESCO): `cells` squares per tile, RGBA with alpha on the wires."""
    y, x = np.mgrid[0:n, 0:n]
    period = n / cells
    wx = np.abs(((x + period / 2) % period) - period / 2) < wire_px / 2
    wy = np.abs(((y + period / 2) % period) - period / 2) < wire_px / 2
    alpha = (wx | wy).astype(np.float32)
    shade = 0.85 + 0.25 * fnoise(n, 30, seed)
    # Weld points slightly darker, a little rust.
    weld = (wx & wy).astype(np.float32)
    shade *= 1.0 - 0.15 * weld
    rgb = _rgb(color, shade)
    rust = np.clip((fnoise(n, 12, seed + 2) - 0.75) * 4.0, 0, 1)[:, :, None]
    rgb = rgb * (1 - 0.5 * rust) + np.array([0.45, 0.30, 0.18])[None, None, :] * 0.5 * rust
    return save_image(name, rgb, alpha)


def tex_chainlink(name, color=(0.68, 0.70, 0.69), n=512, diamonds=8, wire_px=4.0, seed=13):
    """Chain-link diamonds (woven, so the wires bend at the crossings)."""
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    p = n / diamonds
    u = (x + y) / p
    v = (x - y) / p
    # Distance to the nearest diagonal wire in each family, with a small zig-zag weave.
    du = np.abs(u - np.round(u)) * p / math.sqrt(2)
    dv = np.abs(v - np.round(v)) * p / math.sqrt(2)
    alpha = ((du < wire_px / 2) | (dv < wire_px / 2)).astype(np.float32)
    shade = 0.8 + 0.3 * fnoise(n, 25, seed)
    return save_image(name, _rgb(color, shade), alpha)


def tex_sandbag(name, color=(0.58, 0.52, 0.38), n=512, seed=17):
    return tex_fabric(name, color, n=n, seed=seed, weave_px=3, dirt=0.35)


def tex_corrugation_normal(name, n=256, ribs=4, max_slope=0.9, profile="sine"):
    """Normal map of corrugated sheet: `ribs` ribs per tile along U, steepest face
    slope max_slope (rise over run)."""
    x = np.arange(n, dtype=np.float64)
    ph = 2 * math.pi * x / (n / ribs)
    if profile == "trapezoid":
        h = np.clip(np.sin(ph) * 1.8, -1, 1)
    else:
        h = np.sin(ph)
    d = (np.roll(h, -1) - np.roll(h, 1)) * 0.5 * (n / ribs) / (2 * math.pi)
    dx = np.repeat((d * max_slope)[None, :], n, axis=0)
    length = np.sqrt(dx * dx + 1.0)
    rgb = np.stack([(-dx / length) * 0.5 + 0.5, np.full_like(dx, 0.5), (1.0 / length) * 0.5 + 0.5], axis=-1)
    return save_image(name, rgb, non_color=True)


def tex_camo_net(name, n=512, seed=19):
    """Garnished camouflage net: muted woodland patches on a coarse knotted net with
    plenty of holes (about half open), so what is under it stays readable."""
    a = fnoise(n, 12, seed)
    b = fnoise(n, 5, seed + 1)
    garnish = (a > 0.52).astype(np.float32)
    y, x = np.mgrid[0:n, 0:n]
    p = n / 8
    net = ((np.abs(((x + y) % p) - p / 2) < 1.2) | (np.abs(((x - y) % p) - p / 2) < 1.2)).astype(np.float32)
    alpha = np.clip(garnish + net, 0, 1)
    cols = np.array([[0.25, 0.28, 0.18], [0.30, 0.31, 0.21], [0.33, 0.30, 0.21], [0.21, 0.23, 0.15]])
    idx = np.clip((b * 4).astype(int), 0, 3)
    rgb = cols[idx] * (0.9 + 0.2 * fnoise(n, 60, seed + 2))[:, :, None]
    rgb = np.where(net[:, :, None] > 0.5, np.array([0.18, 0.18, 0.14])[None, None, :], rgb)
    return save_image(name, np.clip(rgb, 0, 1), alpha)


# --- Materials -------------------------------------------------------------------------

def textured(name, image, tile_m, roughness=0.8, metallic=0.0, normal=None, normal_strength=1.0, alpha=False, double_sided=False):
    """Principled material with an image base colour (and optional normal map / alpha).
    tile_m: metres covered by one texture repeat (used by box_uv)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for node in list(nt.nodes):
        nt.nodes.remove(node)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        try:
            mat.surface_render_method = "DITHERED"
        except AttributeError:
            mat.blend_method = "CLIP"
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.use_backface_culling = False if double_sided else True
    if normal is not None:
        nt_tex = nt.nodes.new("ShaderNodeTexImage")
        nt_tex.image = normal
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(nt_tex.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    avg = np.array(image.pixels[:]).reshape(-1, 4)[:, :3].mean(axis=0)
    mat.diffuse_color = (avg[0], avg[1], avg[2], 1.0)
    _TILE[name] = tile_m
    return mat


def flat(name, rgb, roughness=0.8, metallic=0.0, tile_m=1.0):
    """Untextured material (small parts: glass, rubber, lamps)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        bsdf = mat.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    _TILE[name] = tile_m
    return mat


# --- UVs -------------------------------------------------------------------------------

def box_uv(obj, keep_material_names=()):
    """World-scale box projection for every face whose material has a tile size.
    Faces of materials listed in keep_material_names keep their existing UVs."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active or bm.loops.layers.uv.new("UVMap")
    mats = [m.name if m else "" for m in me.materials]
    for f in bm.faces:
        mname = mats[f.material_index] if f.material_index < len(mats) else ""
        if mname in keep_material_names:
            continue
        tile = _TILE.get(mname, 1.0)
        nrm = f.normal
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        for loop in f.loops:
            co = loop.vert.co
            if ax == 0:
                u, v = co.y * (1 if nrm.x > 0 else -1), co.z
            elif ax == 1:
                u, v = co.x * (-1 if nrm.y > 0 else 1), co.z
            else:
                u, v = co.x, co.y
            loop[uv].uv = (u / tile, v / tile)
    bm.to_mesh(me)
    bm.free()


def set_uv_scale(obj, tile_m):
    """Scale existing UVs (from generated geometry in metres) by a tile size."""
    me = obj.data
    for d in me.uv_layers.active.data:
        d.uv = (d.uv[0] / tile_m, d.uv[1] / tile_m)


# --- Geometry helpers --------------------------------------------------------------------

def mesh_from(name, verts, faces, mat, uvs=None):
    """Object from raw verts / faces (with optional per-loop UVs in metres)."""
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if mat is not None:
        me.materials.append(mat)
    if uvs is not None:
        layer = me.uv_layers.new(name="UVMap")
        i = 0
        for poly in me.polygons:
            for li in poly.loop_indices:
                layer.data[li].uv = uvs[i]
                i += 1
    return obj


def decimate_copy(obj, ratio, name):
    """A decimated copy (manual LOD check; Godot generates import LODs itself)."""
    c = obj.copy()
    c.data = obj.data.copy()
    c.name = name
    bpy.context.scene.collection.objects.link(c)
    mod = c.modifiers.new("Dec", "DECIMATE")
    mod.ratio = ratio
    return c


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def ground_ao(obj, height=0.6, strength=0.4, floor=0.0):
    """Vertex colour darkening toward the ground (dust, splash, contact shadow). Exported
    as COLOR_0, which glTF / Godot multiply with the base colour."""
    me = obj.data
    attr = me.color_attributes.get("Col") or me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in me.polygons:
        for li in poly.loop_indices:
            z = me.vertices[me.loops[li].vertex_index].co.z - floor
            t = min(max(z / height, 0.0), 1.0)
            k = 1.0 - strength * (1.0 - t) ** 1.5
            attr.data[li].color = (k, k * 0.98, k * 0.95, 1.0)
    me.color_attributes.active_color = attr


def preview_ground(size=40.0):
    """A dusty ground plane for previews (removed by remove_preview_ground)."""
    if bpy.data.objects.get("PreviewGround"):
        return
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    g = bpy.context.active_object
    g.name = "PreviewGround"
    m = bpy.data.materials.get("PreviewGroundMat") or bpy.data.materials.new("PreviewGroundMat")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.36, 0.32, 0.25, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    g.data.materials.append(m)


def remove_preview_ground():
    g = bpy.data.objects.get("PreviewGround")
    if g:
        bpy.data.objects.remove(g, do_unlink=True)


def preview_set(lib, obj, base_path, views):
    """Renders several views: views = [(suffix, azimuth, elevation, distance or None)]."""
    preview_ground(max(obj.dimensions.x, obj.dimensions.y) * 8.0)
    paths = []
    for view in views:
        suffix, az, el, dist = view[:4]
        lookat = view[4] if len(view) > 4 else None
        p = base_path + "_" + suffix + ".png"
        lib.preview(obj, p, width=900, height=700, azimuth_deg=az, elevation_deg=el, distance=dist, lookat_z=lookat)
        paths.append(p)
    return paths


def top_view(obj, path, size=None):
    """Orthographic top-down render."""
    scene = bpy.context.scene
    cam = bpy.data.objects.get("PreviewCamera")
    dims = obj.dimensions
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = (size or max(dims.x, dims.y)) * 1.25
    cam.location = (0, 0, dims.z + 20)
    cam.rotation_mode = "XYZ"
    cam.rotation_euler = (0, 0, 0)
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    cam.data.type = "PERSP"
    remove_preview_ground()
    return path
