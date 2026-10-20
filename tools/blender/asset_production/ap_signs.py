"""Sign / marking atlas (2048 px, 8 x 8 cells of 256 px) for the "Signs" material.

Rendered in Blender (Workbench, flat colours, Standard view transform) from simple shapes
and text, so signs stay crisp and editable as code. Builders map quads/discs onto a sign
with ap_lib.Asset.quad_uv / sign_shape and `rect(name)`.

Designs are generic (Vienna-convention road signs, NATO-style range targets, base
placards); no real unit insignia or national emblems.
"""
import math
import os

import bmesh
import bpy

ATLAS_PX = 2048
CELLS = 8
FONT = "C:/Windows/Fonts/arialbd.ttf"

RED = (0.78, 0.08, 0.07)
WHITE = (0.95, 0.95, 0.93)
BLACK = (0.04, 0.04, 0.04)
YELLOW = (0.98, 0.78, 0.05)
BLUE = (0.05, 0.25, 0.62)
GREEN = (0.05, 0.40, 0.18)
ORANGE = (0.95, 0.45, 0.05)
OLIVE = (0.30, 0.33, 0.22)
TAN = (0.80, 0.72, 0.55)
GREY = (0.55, 0.55, 0.55)

# name: (col, row, w, h) in cells, row 0 at the top.
SIGNS = {
    "stop": (0, 0, 1, 1), "yield": (1, 0, 1, 1), "no_entry": (2, 0, 1, 1), "speed_30": (3, 0, 1, 1),
    "speed_50": (4, 0, 1, 1), "speed_15": (5, 0, 1, 1), "warning": (6, 0, 1, 1), "keep_right": (7, 0, 1, 1),
    "restricted": (0, 1, 2, 1), "checkpoint": (2, 1, 2, 1), "medical_cross": (4, 1, 1, 1), "no_smoking": (5, 1, 1, 1),
    "flammable": (6, 1, 1, 1), "explosive": (7, 1, 1, 1),
    "hazard_stripes": (0, 2, 2, 1), "high_voltage": (2, 2, 1, 1), "chevron": (3, 2, 1, 1), "bullseye": (4, 2, 1, 1),
    "target_fig11": (5, 2, 1, 2), "target_fig12": (6, 2, 1, 2), "delineator": (7, 2, 1, 1),
    "lane_1": (0, 3, 1, 1), "lane_2": (1, 3, 1, 1), "lane_3": (2, 3, 1, 1), "lane_4": (3, 3, 1, 1),
    "range_100": (4, 3, 1, 1), "range_300": (7, 3, 1, 1),
    "plate_hq": (0, 4, 2, 1), "plate_barracks": (2, 4, 2, 1), "plate_supply": (4, 4, 2, 1), "plate_motorpool": (6, 4, 2, 1),
    "plate_medical": (0, 5, 2, 1), "plate_comms": (2, 5, 2, 1), "plate_training": (4, 5, 2, 1), "plate_ammo": (6, 5, 2, 1),
    "plate_fuel": (0, 6, 2, 1), "plate_range": (2, 6, 2, 1), "plate_gate": (4, 6, 2, 1), "plate_slow": (6, 6, 2, 1),
    "container_doors": (0, 7, 2, 1), "number_plate": (2, 7, 2, 1), "gauge_dial": (4, 7, 1, 1), "vent_grille": (5, 7, 1, 1),
    "window_dark": (6, 7, 1, 1), "door_panel": (7, 7, 1, 1),
}


def rect(name, inset_px=3):
    """UV rectangle (u0, v0, u1, v1) of a sign in Blender UV space (v up)."""
    c, r, w, h = SIGNS[name]
    s = 1.0 / CELLS
    i = inset_px / ATLAS_PX
    return (c * s + i, 1.0 - (r + h) * s + i, (c + w) * s - i, 1.0 - r * s - i)


# --------------------------------------------------------------------------- drawing


def _lin(c):
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


class Canvas:
    """Draws into one cell group; coordinates in px from the cell's top-left corner.
    Polygons are clipped to the cell; z grows globally so later shapes stay on top."""

    z = 0.0
    mats = {}

    def __init__(self, scene, name):
        self.scene = scene
        c, r, w, h = SIGNS[name]
        self.ox, self.oy = c * 256, r * 256
        self.w, self.h = w * 256, h * 256
        self.mats = Canvas.mats

    def _xy(self, x, y):
        return ((self.ox + x) / 256.0, -(self.oy + y) / 256.0)

    def _mat(self, col):
        key = tuple(round(v, 3) for v in col)
        if key not in self.mats:
            m = bpy.data.materials.new("sign_%d" % len(bpy.data.materials))
            m.diffuse_color = (*_lin(col), 1)
            self.mats[key] = m
        return self.mats[key]

    def _clip(self, pts):
        """Sutherland-Hodgman clip against the cell rectangle."""
        def cut(poly, inside, inter):
            out = []
            for i in range(len(poly)):
                a, b = poly[i - 1], poly[i]
                if inside(b):
                    if not inside(a):
                        out.append(inter(a, b))
                    out.append(b)
                elif inside(a):
                    out.append(inter(a, b))
            return out

        def lerp_x(x):
            return lambda a, b: (x, a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0]))

        def lerp_y(y):
            return lambda a, b: (a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]), y)
        for inside, inter in ((lambda p: p[0] >= 0, lerp_x(0)), (lambda p: p[0] <= self.w, lerp_x(self.w)),
                              (lambda p: p[1] >= 0, lerp_y(0)), (lambda p: p[1] <= self.h, lerp_y(self.h))):
            pts = cut(pts, inside, inter)
            if not pts:
                break
        return pts

    def _poly(self, pts, col):
        pts = self._clip(list(pts))
        if len(pts) < 3:
            return
        Canvas.z += 0.0005
        bm = bmesh.new()
        vs = [bm.verts.new((*self._xy(x, y), Canvas.z)) for x, y in pts]
        bm.faces.new(vs)
        me = bpy.data.meshes.new("sp")
        bm.to_mesh(me)
        o = bpy.data.objects.new("sp", me)
        self.scene.collection.objects.link(o)
        me.materials.append(self._mat(col))

    def rect(self, x0, y0, x1, y1, col):
        self._poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], col)

    def ngon(self, cx, cy, r, n, col, rot=0.0):
        self._poly([(cx + r * math.cos(rot + 2 * math.pi * k / n), cy - r * math.sin(rot + 2 * math.pi * k / n)) for k in range(n)], col)

    def circle(self, cx, cy, r, col):
        self.ngon(cx, cy, r, 64, col)

    def poly(self, pts, col):
        self._poly(pts, col)

    def text(self, s, cx, cy, size, col, font=None):
        Canvas.z += 0.0005
        cu = bpy.data.curves.new("t", "FONT")
        cu.body = s
        cu.size = size / 256.0
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        if os.path.exists(FONT):
            f = bpy.data.fonts.get("arialbd") or bpy.data.fonts.load(FONT)
            f.name = "arialbd"
            cu.font = f
        o = bpy.data.objects.new("t", cu)
        o.location = (*self._xy(cx, cy), Canvas.z)
        self.scene.collection.objects.link(o)
        cu.materials.append(self._mat(col))

    def full(self, col):
        self.rect(0, 0, self.w, self.h, col)


def _round_sign(cv, ring, fill, text, tsize=96):
    cv.full(GREY)
    cv.circle(128, 128, 122, ring)
    cv.circle(128, 128, 96, fill)
    if text:
        cv.text(text, 128, 132, tsize, BLACK)


def _plate(cv, label, fg=WHITE, bg=OLIVE, sub=None):
    cv.full(bg)
    cv.rect(8, 8, cv.w - 8, cv.h - 8, fg)
    cv.rect(16, 16, cv.w - 16, cv.h - 16, bg)
    cv.text(label, cv.w / 2, cv.h / 2 - (18 if sub else 0), 74, fg)
    if sub:
        cv.text(sub, cv.w / 2, cv.h / 2 + 62, 34, fg)


def _silhouette(cv, x0, y0, w, h, col, head=0.30, shoulder_y=0.34):
    """Head-and-shoulders target silhouette (NATO Figure 11/12 style): round head, short
    neck, sloping shoulders, straight sides."""
    cx = x0 + w / 2
    hr = w * head / 2
    hc = y0 + hr * 1.15
    pts = []
    for k in range(0, 13):                       # head arc, from the left of the neck over the top
        a = math.pi * (1.25 - 1.5 * k / 12)
        pts.append((cx + hr * math.cos(a), hc - hr * 1.15 * math.sin(a)))
    neck_y = hc + hr * 1.05
    sy = y0 + h * shoulder_y
    pts = pts + [(cx + hr * 0.62, neck_y + 6), (cx + w * 0.30, neck_y + (sy - neck_y) * 0.35), (cx + w * 0.47, sy),
                 (cx + w * 0.49, y0 + h), (cx - w * 0.49, y0 + h), (cx - w * 0.47, sy),
                 (cx - w * 0.30, neck_y + (sy - neck_y) * 0.35), (cx - hr * 0.62, neck_y + 6)]
    cv.poly(pts, col)


def draw_all(scene):
    D = lambda name: Canvas(scene, name)
    cv = D("stop"); cv.full(GREY); cv.ngon(128, 128, 124, 8, WHITE, math.pi / 8); cv.ngon(128, 128, 114, 8, RED, math.pi / 8); cv.text("STOP", 128, 132, 78, WHITE)
    cv = D("yield"); cv.full(GREY); cv.poly([(128, 236), (8, 28), (248, 28)], RED); cv.poly([(128, 196), (44, 50), (212, 50)], WHITE)
    cv = D("no_entry"); cv.full(GREY); cv.circle(128, 128, 122, RED); cv.rect(40, 108, 216, 148, WHITE)
    _round_sign(D("speed_30"), RED, WHITE, "30", 110)
    _round_sign(D("speed_50"), RED, WHITE, "50", 110)
    _round_sign(D("speed_15"), RED, WHITE, "15", 110)
    cv = D("warning"); cv.full(GREY); cv.poly([(128, 12), (248, 226), (8, 226)], RED); cv.poly([(128, 52), (212, 204), (44, 204)], WHITE); cv.text("!", 128, 150, 120, BLACK)
    cv = D("keep_right"); cv.full(GREY); cv.circle(128, 128, 122, BLUE)
    cv.poly([(80, 80), (176, 176), (176, 120), (196, 196), (120, 196), (150, 176), (64, 96)], WHITE)
    cv = D("restricted"); cv.full(WHITE); cv.rect(0, 0, 512, 70, RED); cv.text("RESTRICTED AREA", 256, 36, 50, WHITE)
    cv.text("MILITARY ZONE", 256, 118, 46, BLACK); cv.text("NO UNAUTHORISED ENTRY", 256, 180, 34, BLACK); cv.text("USE OF FORCE AUTHORISED", 256, 222, 26, RED)
    cv = D("checkpoint"); cv.full(RED); cv.rect(10, 10, 502, 246, WHITE); cv.rect(18, 18, 494, 238, RED)
    cv.text("CHECKPOINT", 256, 72, 62, WHITE); cv.text("STOP", 256, 140, 70, WHITE); cv.text("SHOW ID - LIGHTS OFF", 256, 206, 32, WHITE)
    cv = D("medical_cross"); cv.full(WHITE); cv.rect(96, 32, 160, 224, RED); cv.rect(32, 96, 224, 160, RED)
    cv = D("no_smoking"); cv.full(WHITE); cv.circle(128, 128, 118, RED); cv.circle(128, 128, 98, WHITE)
    cv.rect(52, 116, 190, 140, BLACK); cv.rect(192, 116, 206, 140, ORANGE)
    cv.poly([(56, 70), (70, 56), (200, 186), (186, 200)], RED)
    cv = D("flammable"); cv.full(GREY); cv.ngon(128, 128, 126, 4, WHITE, math.pi / 2); cv.ngon(128, 128, 116, 4, RED, math.pi / 2)
    cv.poly([(128, 44), (146, 78), (160, 108), (156, 134), (138, 150), (118, 150), (100, 134), (98, 110), (112, 88), (118, 104), (124, 80)], WHITE); cv.rect(92, 154, 164, 162, WHITE); cv.text("3", 128, 190, 50, WHITE)
    cv = D("explosive"); cv.full(GREY); cv.ngon(128, 128, 126, 4, BLACK, math.pi / 2); cv.ngon(128, 128, 116, 4, ORANGE, math.pi / 2)
    cv.text("1.1", 128, 112, 64, BLACK); cv.text("1", 128, 196, 44, BLACK)
    cv = D("hazard_stripes"); cv.full(YELLOW)
    for k in range(-4, 12):
        x = k * 64
        cv.poly([(x, 256), (x + 32, 256), (x + 32 + 256, 0), (x + 256, 0)], BLACK)
    cv = D("high_voltage"); cv.full(GREY); cv.poly([(128, 12), (248, 226), (8, 226)], BLACK); cv.poly([(128, 40), (224, 210), (32, 210)], YELLOW)
    cv.poly([(140, 70), (100, 150), (128, 150), (110, 200), (160, 126), (132, 126), (150, 70)], BLACK)
    cv = D("chevron"); cv.full(WHITE)
    for dx in (-60, 40):
        cv.poly([(70 + dx, 28), (120 + dx, 28), (190 + dx, 128), (120 + dx, 228), (70 + dx, 228), (140 + dx, 128)], RED)
    cv = D("bullseye"); cv.full(WHITE)
    for r, c in ((124, BLACK), (100, WHITE), (78, BLACK), (56, WHITE), (36, BLACK), (16, RED)):
        cv.circle(128, 128, r, c)
    cv = D("target_fig11"); cv.full(TAN); _silhouette(cv, 24, 60, 208, 446, OLIVE, head=0.30, shoulder_y=0.32)
    cv.rect(0, 0, 256, 6, BLACK)
    cv = D("target_fig12"); cv.full(TAN); _silhouette(cv, 20, 214, 216, 292, OLIVE, head=0.36, shoulder_y=0.50)
    cv = D("delineator"); cv.full(WHITE); cv.rect(0, 0, 256, 60, BLACK); cv.rect(88, 96, 168, 176, RED)
    for i in range(4):
        cv = D("lane_%d" % (i + 1)); cv.full(WHITE); cv.rect(10, 10, 246, 246, BLACK); cv.rect(22, 22, 234, 234, WHITE); cv.text(str(i + 1), 128, 136, 170, BLACK)
    cv = D("range_100"); cv.full(RED); cv.text("100", 128, 110, 92, WHITE); cv.text("M", 128, 196, 56, WHITE)
    cv = D("range_300"); cv.full(RED); cv.text("300", 128, 110, 92, WHITE); cv.text("M", 128, 196, 56, WHITE)
    _plate(D("plate_hq"), "HQ", sub="HEADQUARTERS")
    _plate(D("plate_barracks"), "BARRACKS", sub="ACCOMMODATION")
    _plate(D("plate_supply"), "SUPPLY", sub="DEPOT")
    _plate(D("plate_motorpool"), "MOTOR POOL", sub="VEHICLE DEPOT")
    _plate(D("plate_medical"), "MEDICAL", fg=WHITE, bg=(0.65, 0.07, 0.06), sub="AID STATION")
    _plate(D("plate_comms"), "COMMS", sub="SIGNALS")
    _plate(D("plate_training"), "TRAINING", sub="AREA")
    _plate(D("plate_ammo"), "AMMUNITION", fg=BLACK, bg=ORANGE, sub="NO SMOKING - NO FLAMES")
    _plate(D("plate_fuel"), "FUEL POINT", fg=BLACK, bg=YELLOW, sub="ENGINES OFF")
    _plate(D("plate_range"), "LIVE FIRE", fg=WHITE, bg=RED, sub="RANGE IN USE")
    _plate(D("plate_gate"), "GATE", sub="VEHICLES STOP")
    _plate(D("plate_slow"), "SLOW", fg=BLACK, bg=YELLOW, sub="DEAD SLOW 10")
    cv = D("container_doors"); cv.full((0.30, 0.32, 0.23))
    for x in (40, 150, 362, 472):
        cv.rect(x - 4, 0, x + 4, 256, (0.17, 0.18, 0.13))
    cv.rect(254, 0, 258, 256, (0.08, 0.08, 0.07))
    for x in (100, 210, 302, 412):
        cv.rect(x - 7, 0, x + 7, 256, (0.62, 0.62, 0.60)); cv.rect(x - 14, 110, x + 14, 146, (0.55, 0.55, 0.53))
    cv.text("FNTU 204718 4", 130, 40, 20, WHITE); cv.text("22G1", 130, 64, 18, WHITE)
    cv = D("number_plate"); cv.full(BLACK); cv.rect(6, 70, 506, 186, WHITE); cv.text("FN 41-27 BJ", 256, 130, 76, BLACK)
    cv = D("gauge_dial"); cv.full(GREY); cv.circle(128, 128, 110, BLACK); cv.circle(128, 128, 96, WHITE)
    cv.poly([(124, 128), (132, 128), (190, 60), (186, 56)], RED)
    cv = D("vent_grille"); cv.full((0.12, 0.12, 0.12))
    for y in range(16, 256, 24):
        cv.rect(12, y, 244, y + 10, (0.42, 0.42, 0.42))
    cv = D("window_dark"); cv.full((0.35, 0.36, 0.34)); cv.rect(14, 14, 242, 242, (0.06, 0.08, 0.09)); cv.rect(122, 14, 134, 242, (0.35, 0.36, 0.34))
    cv.poly([(30, 30), (90, 30), (40, 120)], (0.16, 0.19, 0.21))
    cv = D("door_panel"); cv.full((0.40, 0.40, 0.38)); cv.rect(20, 20, 236, 236, (0.30, 0.31, 0.29)); cv.rect(30, 30, 226, 120, (0.36, 0.37, 0.35))
    cv.rect(190, 130, 220, 150, (0.70, 0.70, 0.68))


def build(tex_dir):
    """Renders the atlas into tex_dir/signs.png in a temporary scene."""
    main = bpy.context.window.scene if bpy.context.window else bpy.context.scene
    sc = bpy.data.scenes.new("SignAtlas")
    draw_all(sc)
    cam = bpy.data.objects.new("SignCam", bpy.data.cameras.new("SignCam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = CELLS
    cam.location = (CELLS / 2, -CELLS / 2, 5)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "MATERIAL"
    sc.display.render_aa = "16"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.resolution_x = sc.render.resolution_y = ATLAS_PX
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    w = bpy.data.worlds.new("SignWorld")
    w.color = _lin(GREY)
    sc.world = w
    sc.render.filepath = os.path.join(tex_dir, "signs.png")
    bpy.ops.render.render(write_still=True, scene=sc.name)
    for o in list(sc.collection.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.scenes.remove(sc)
    if bpy.context.window:
        bpy.context.window.scene = main
    return sc
