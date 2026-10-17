"""Builds Aether melee weapons in grip space and exports each to .glb.

Run from Blender's Scripting tab or through the Blender MCP.
Blender axes -> Godot grip space: +Z = tip (+Y), +X = strike side (+X), -Y = face (+Z).
Origin is the centre of the closed hand.
Empty "offhand_grip" marks the second hand on two-handers; material "accent" is
the damage-type glow placeholder. weapons_manifest.json lists both per weapon.
"""
import bpy
import json
import math
import os
from mathutils import Matrix, Vector

PROJECT_ROOT = r"S:\projects\Project Aether"
EXPORT_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "weapons")
BUILD = None  # None = every entry in BUILDERS, or a list of keys
EXPORT = True

# Same values as WeaponModelLibrary._mat (sRGB colour, roughness, metallic).
MATERIALS = {
    "steel": ((0.72, 0.74, 0.78), 0.32, 0.75),
    "darksteel": ((0.26, 0.27, 0.3), 0.4, 0.7),
    "brass": ((0.78, 0.6, 0.28), 0.35, 0.8),
    "leather": ((0.3, 0.18, 0.1), 0.85, 0.0),
    "wood": ((0.45, 0.27, 0.14), 0.75, 0.0),
    "bone": ((0.86, 0.82, 0.7), 0.7, 0.0),
    "accent": ((0.5, 0.8, 1.0), 0.5, 0.0),
}


def _linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    color, rough, metal = MATERIALS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*[_linear(c) for c in color], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if name == "accent":
        (bsdf.inputs.get("Emission Color") or bsdf.inputs["Emission"]).default_value = (*[_linear(c) for c in color], 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.5
    mat.diffuse_color = (*[_linear(c) for c in color], 1.0)
    return mat


class Part:
    """Accumulates closed pieces into one mesh object."""

    def __init__(self, name, mat):
        self.name, self.mat = name, mat
        self.verts, self.faces, self.smooth = [], [], []

    def add(self, verts, faces, smooth, matrix=None):
        if matrix is not None:
            verts = [tuple(matrix @ Vector(v)) for v in verts]
        vol = 0.0
        for f in faces:
            a = Vector(verts[f[0]])
            for i in range(1, len(f) - 1):
                vol += a.dot(Vector(verts[f[i]]).cross(Vector(verts[f[i + 1]])))
        if vol < 0:
            faces = [tuple(reversed(f)) for f in faces]
        base = len(self.verts)
        self.verts += verts
        self.faces += [tuple(i + base for i in f) for f in faces]
        self.smooth += smooth
        return self

    def build(self, parent):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts, [], self.faces)
        mesh.polygons.foreach_set("use_smooth", self.smooth)
        mesh.validate()
        mesh.update()
        mesh.materials.append(material(self.mat))
        obj = bpy.data.objects.new(self.name, mesh)
        parent.users_collection[0].objects.link(obj)
        obj.parent = parent
        return obj


def lathe(profile, seg=12, smooth=True):
    """Revolve [(z, r), ...] (bottom to top) around Z. r=0 makes a point."""
    verts, faces, flags, rings = [], [], [], []
    for z, r in profile:
        if r < 1e-6:
            rings.append([len(verts)])
            verts.append((0.0, 0.0, z))
        else:
            rings.append(list(range(len(verts), len(verts) + seg)))
            verts += [(r * math.cos(2 * math.pi * i / seg), r * math.sin(2 * math.pi * i / seg), z) for i in range(seg)]
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            j = (i + 1) % seg
            if len(a) == 1 and len(b) == 1:
                break
            if len(a) == 1:
                faces.append((a[0], b[j], b[i]))
            elif len(b) == 1:
                faces.append((a[i], a[j], b[0]))
            else:
                faces.append((a[i], a[j], b[j], b[i]))
            flags.append(smooth)
    for ring, top in ((rings[0], False), (rings[-1], True)):
        if len(ring) == 1:
            continue
        start = len(verts)
        verts += [verts[i] for i in ring]
        cap = list(range(start, start + seg))
        faces.append(tuple(cap if top else reversed(cap)))
        flags.append(False)
    return verts, faces, flags


def loft(sections, smooth=False):
    """Skin consecutive closed loops of equal size; a 1-point loop is a tip."""
    verts, faces, flags, idx = [], [], [], []
    for s in sections:
        idx.append(list(range(len(verts), len(verts) + len(s))))
        verts += [tuple(p) for p in s]
    n = max(len(s) for s in sections)
    for a, b in zip(idx, idx[1:]):
        for i in range(n):
            j = (i + 1) % n
            if len(a) == 1:
                faces.append((a[0], b[j], b[i]))
            elif len(b) == 1:
                faces.append((a[i], a[j], b[0]))
            else:
                faces.append((a[i], a[j], b[j], b[i]))
            flags.append(smooth)
    if len(idx[0]) > 1:
        faces.append(tuple(reversed(idx[0])))
        flags.append(False)
    if len(idx[-1]) > 1:
        faces.append(tuple(idx[-1]))
        flags.append(False)
    return verts, faces, flags


def tube(points, radius, seg=8, smooth=True):
    pts = [Vector(p) for p in points]
    radii = radius if isinstance(radius, (list, tuple)) else [radius] * len(pts)
    sections = []
    ref = Vector((0.0, 1.0, 0.0))
    for k, p in enumerate(pts):
        t = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]).normalized()
        if abs(t.dot(ref)) > 0.95:
            ref = Vector((1.0, 0.0, 0.0))
        u = t.cross(ref).normalized()
        v = t.cross(u)
        sections.append([p + (u * math.cos(2 * math.pi * i / seg) + v * math.sin(2 * math.pi * i / seg)) * radii[k] for i in range(seg)])
    return loft(sections, smooth)


def box(size, center):
    sx, sy, sz = (s * 0.5 for s in size)
    cx, cy, cz = center
    verts = [(cx + x * sx, cy + y * sy, cz + z * sz) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return verts, faces, [False] * 6


def prism(poly, thickness):
    """Extrude an (x, z) polygon symmetrically along Y."""
    n = len(poly)
    h = thickness * 0.5
    verts = [(x, -h, z) for x, z in poly] + [(x, h, z) for x, z in poly]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return verts, faces, [False] * len(faces)


def wrap_profile(z0, z1, r, ridge, turns):
    step = (z1 - z0) / (turns * 2)
    return [(z0 + i * step, r + (ridge if i % 2 else 0.0)) for i in range(turns * 2 + 1)]


def at(x=0.0, y=0.0, z=0.0, rx=0.0, ry=0.0, rz=0.0):
    rot = Matrix.Rotation(math.radians(rz), 4, "Z") @ Matrix.Rotation(math.radians(ry), 4, "Y") @ Matrix.Rotation(math.radians(rx), 4, "X")
    return Matrix.Translation((x, y, z)) @ rot


# Godot grip space (tip +Y, face +Z) -> Blender, for porting WeaponModelLibrary coordinates.
GODOT = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
# WeaponModelLibrary's forward-authored space (knuckles -Z, top +Y) -> Blender.
FORWARD = Matrix.Diagonal((1, -1, -1, 1))


def sphere(r, seg=10, rings=6):
    return lathe([(-r * math.cos(math.pi * i / rings), r * math.sin(math.pi * i / rings)) for i in range(rings + 1)], seg)


def cyl(r_bottom, r_top, length, seg=10, smooth=True):
    """Cylinder centred on the origin along Z."""
    return lathe([(-length * 0.5, r_bottom), (length * 0.5, r_top)], seg, smooth)


def blade(z0, z1, w0, w1, t0, t1, tip_z, shape="hex", curve=0.0, steps=5, widths=None):
    """Blade along +Z. curve bends the tip toward -X; shape: hex, diamond or single (edge +X)."""
    sections = []
    for i in range(steps):
        f = i / (steps - 1)
        z = z0 + (z1 - z0) * f
        w = widths[i] if widths else w0 + (w1 - w0) * f
        t = t0 + (t1 - t0) * f
        c = -curve * f * f
        if shape == "diamond":
            loop = [(c + w, 0, z), (c, t, z), (c - w, 0, z), (c, -t, z)]
        elif shape == "single":
            loop = [(c + w, 0, z), (c - w, t, z), (c - w, -t, z)]
        else:
            loop = [(c + w, 0, z), (c + w * 0.4, t, z), (c - w * 0.4, t, z), (c - w, 0, z), (c - w * 0.4, -t, z), (c + w * 0.4, -t, z)]
        sections.append(loop)
    tip_x = -curve * ((tip_z - z0) / (z1 - z0)) ** 2
    sections.append([(tip_x - (w1 * 0.5 if shape == "single" else 0.0), 0, tip_z)])
    return loft(sections)


def marker(root, name, location):
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "SPHERE"
    empty.empty_display_size = 0.015
    empty.location = location
    root.users_collection[0].objects.link(empty)
    empty.parent = root
    return empty


def pommel(part, z, r=0.02, length=0.03, seg=10):
    h = length * 0.5
    part.add(*lathe([(z - h, 0.0), (z - h * 0.6, r * 0.7), (z, r), (z + h * 0.6, r * 0.8), (z + h, r * 0.5)], seg))


def wheel_pommel(part, z, r=0.022, thickness=0.016):
    part.add(*lathe([(-thickness * 0.5, r * 0.8), (-thickness * 0.3, r), (thickness * 0.3, r), (thickness * 0.5, r * 0.8)], 12, False), at(z=z, rx=90))
    part.add(*lathe([(-thickness * 0.65, r * 0.35), (thickness * 0.65, r * 0.35)], 8, False), at(z=z, rx=90))


def grip(name, root, z0, z1, r=0.0155, mat="leather", turns=None, seg=10):
    turns = turns or max(3, int((z1 - z0) / 0.016))
    Part(name, mat).add(*lathe(wrap_profile(z0, z1, r, 0.0014, turns), seg)).build(root)


def band(part, z, r, h=0.01, seg=8):
    part.add(*lathe([(z, r), (z + h, r)], seg, False))


# --- weapons ---

def build_mace(root):
    Part("Mace_Pommel", "darksteel").add(*lathe([(-0.092, 0.0), (-0.088, 0.014), (-0.078, 0.023), (-0.066, 0.023), (-0.058, 0.016)], 8)).build(root)
    Part("Mace_Grip", "leather").add(*lathe(wrap_profile(-0.058, 0.055, 0.016, 0.0015, 7), 10)).build(root)
    fittings = Part("Mace_Fittings", "brass")
    fittings.add(*lathe([(0.055, 0.021), (0.072, 0.021)], 6, False))
    for z in (0.17, 0.27):
        fittings.add(*lathe([(z, 0.0165), (z + 0.012, 0.0165)], 8, False))
    fittings.add(*lathe([(0.478, 0.017), (0.492, 0.017), (0.505, 0.0)], 6, False))
    fittings.build(root)
    Part("Mace_Shaft", "darksteel").add(*lathe([(0.07, 0.0135), (0.35, 0.012)], 10)).build(root)
    head = Part("Mace_Head", "steel")
    head.add(*lathe([(0.33, 0.017), (0.35, 0.025), (0.41, 0.03), (0.455, 0.027), (0.48, 0.017)], 14))
    flange = [(0.018, 0.34), (0.044, 0.368), (0.058, 0.41), (0.056, 0.448), (0.036, 0.474), (0.018, 0.47)]
    for k in range(7):
        head.add(*prism(flange, 0.008), at(rz=k * 360 / 7))
    head.build(root)
    rivets = Part("Mace_Rivets", "brass")
    for k in range(7):
        for side in (-1, 1):
            rivets.add(*lathe([(0.0, 0.0045), (0.002, 0.004), (0.004, 0.0)], 6), at(rz=k * 360 / 7) @ at(0.036, side * 0.004, 0.408, rx=-90 * side))
    rivets.build(root)


def build_war_pick(root):
    Part("WarPick_Pommel", "darksteel").add(*lathe([(-0.1, 0.0), (-0.085, 0.012), (-0.07, 0.019), (-0.062, 0.017)], 8, False)).build(root)
    Part("WarPick_Grip", "leather").add(*lathe(wrap_profile(-0.062, 0.06, 0.0165, 0.0015, 8), 10)).build(root)
    Part("WarPick_Haft", "wood").add(*lathe([(0.06, 0.015), (0.5, 0.0135)], 8, False)).build(root)
    head = Part("WarPick_Head", "steel")
    head.add(*box((0.042, 0.034, 0.075), (0.0, 0.0, 0.525)))
    spike = []
    for t in (0.0, 0.25, 0.5, 0.75):
        x, z = 0.02 + 0.15 * t, 0.53 - 0.04 * t * t
        w, h = 0.014 * (1 - 0.6 * t), 0.026 * (1 - 0.6 * t)
        spike.append([(x, w, z), (x, 0.0, z + h), (x, -w, z), (x, 0.0, z - h)])
    spike.append([(0.19, 0.0, 0.475)])
    head.add(*loft(spike))
    head.add(*lathe([(0.0, 0.017), (0.045, 0.019), (0.055, 0.021), (0.06, 0.017)], 8, False), at(-0.02, 0, 0.53, ry=-90))
    head.add(*lathe([(0.0, 0.012), (0.04, 0.0)], 4, False), at(z=0.562, rz=45))
    head.build(root)
    langets = Part("WarPick_Langets", "darksteel")
    for side in (-1, 1):
        langets.add(*box((0.014, 0.004, 0.2), (0.0, side * 0.0145, 0.4)))
    langets.build(root)
    bolts = Part("WarPick_Bolts", "brass")
    bolts.add(*lathe([(-0.022, 0.008), (0.022, 0.008)], 6, False), at(z=0.53, rx=90))
    for z in (0.33, 0.39, 0.45):
        bolts.add(*lathe([(-0.019, 0.004), (0.019, 0.004)], 6, False), at(z=z, rx=90))
    bolts.build(root)


def build_rapier(root):
    Part("Rapier_Pommel", "brass").add(*lathe([(-0.118, 0.0), (-0.112, 0.012), (-0.098, 0.02), (-0.082, 0.02), (-0.07, 0.012), (-0.062, 0.008)], 12)).build(root)
    Part("Rapier_Grip", "darksteel").add(*lathe(wrap_profile(-0.062, 0.05, 0.0135, 0.0012, 10), 8)).build(root)
    hilt = Part("Rapier_Hilt", "brass")
    hilt.add(*lathe([(-0.064, 0.0155), (-0.058, 0.0155)], 8, False))
    hilt.add(*lathe([(0.048, 0.016), (0.07, 0.016)], 8, False))
    quillon = [(-0.11, 0.0, 0.04), (-0.09, 0.0, 0.055), (-0.05, 0.0, 0.063), (0.0, 0.0, 0.065),
               (0.05, 0.0, 0.067), (0.09, 0.0, 0.075), (0.11, 0.0, 0.09)]
    hilt.add(*tube(quillon, 0.0055))
    for end in (quillon[0], quillon[-1]):
        hilt.add(*lathe([(-0.009, 0.0), (-0.006, 0.007), (0.0, 0.009), (0.006, 0.007), (0.009, 0.0)], 8), at(*end))
    bow = [(0.0, 0.0, 0.065), (0.035, 0.0, 0.058), (0.055, 0.0, 0.035), (0.06, 0.0, -0.005),
           (0.054, 0.0, -0.04), (0.036, 0.0, -0.06), (0.012, 0.0, -0.068)]
    hilt.add(*tube(bow, 0.0045))
    ring = [(math.sin(a) * 0.03, -0.03 + math.cos(a) * 0.03, 0.066) for a in (2 * math.pi * i / 16 for i in range(17))]
    hilt.add(*tube(ring, 0.0035, 6))
    hilt.build(root)
    blade = Part("Rapier_Blade", "steel")
    blade.add(*box((0.016, 0.008, 0.035), (0.0, 0.0, 0.0875)))
    sections = []
    for z in (0.105, 0.3, 0.55, 0.8):
        f = (z - 0.105) / 0.8
        w, t = 0.0095 - 0.006 * f, 0.0038 - 0.002 * f
        sections.append([(w, 0.0, z), (0.0, t, z), (-w, 0.0, z), (0.0, -t, z)])
    sections.append([(0.0, 0.0, 0.92)])
    blade.add(*loft(sections))
    blade.build(root)


def build_shortsword(root):
    pom = Part("Shortsword_Pommel", "darksteel")
    wheel_pommel(pom, -0.075)
    pom.build(root)
    grip("Shortsword_Grip", root, -0.062, 0.052)
    guard = Part("Shortsword_Guard", "darksteel")
    guard.add(*box((0.17, 0.022, 0.016), (0.0, 0.0, 0.062)))
    for side in (-1, 1):
        guard.add(*sphere(0.011, 8, 4), at(side * 0.087, 0, 0.062))
    guard.build(root)
    Part("Shortsword_Fittings", "brass").add(*lathe([(0.048, 0.017), (0.055, 0.017)], 8, False)).build(root)
    Part("Shortsword_Blade", "steel").add(*blade(0.07, 0.6, 0.024, 0.014, 0.005, 0.003, 0.66)).build(root)


def build_saber(root):
    Part("Saber_Pommel", "brass").add(*lathe([(-0.078, 0.0), (-0.074, 0.012), (-0.066, 0.016), (-0.058, 0.013)], 10)).build(root)
    grip("Saber_Grip", root, -0.058, 0.052, 0.014, "leather")
    hilt = Part("Saber_Hilt", "brass")
    hilt.add(*box((0.095, 0.026, 0.01), (0.012, 0.0, 0.062)))
    hilt.add(*sphere(0.008, 8, 4), at(-0.038, 0, 0.066))
    hilt.add(*tube([(0.058, 0, 0.062), (0.066, 0, 0.03), (0.064, 0, -0.01), (0.052, 0, -0.045), (0.03, 0, -0.066), (0.01, 0, -0.072)], 0.005))
    hilt.build(root)
    Part("Saber_Blade", "steel").add(*blade(0.068, 0.66, 0.016, 0.011, 0.004, 0.0025, 0.72, "single", 0.05, 6)).build(root)


def build_cutlass(root):
    Part("Cutlass_Pommel", "brass").add(*lathe([(-0.074, 0.0), (-0.07, 0.013), (-0.062, 0.017), (-0.055, 0.014)], 10)).build(root)
    grip("Cutlass_Grip", root, -0.055, 0.05, 0.015, "wood", 4, 8)
    shell = Part("Cutlass_Shell", "darksteel")
    shell.add(*lathe([(0.05, 0.068), (0.062, 0.06), (0.072, 0.028), (0.076, 0.018)], 14), at(x=0.018))
    shell.build(root)
    hilt = Part("Cutlass_Hilt", "brass")
    hilt.add(*tube([(0.08, 0, 0.052), (0.086, 0, 0.02), (0.08, 0, -0.02), (0.06, 0, -0.05), (0.03, 0, -0.065), (0.01, 0, -0.07)], 0.006))
    hilt.add(*sphere(0.008, 8, 4), at(-0.05, 0, 0.056))
    hilt.build(root)
    Part("Cutlass_Blade", "steel").add(*blade(0.074, 0.53, 0.023, 0.02, 0.0045, 0.003, 0.6, "single", 0.035, 6)).build(root)


def build_dagger(root):
    pom = Part("Dagger_Pommel", "darksteel")
    pommel(pom, -0.058, 0.017, 0.026, 8)
    pom.build(root)
    grip("Dagger_Grip", root, -0.048, 0.044, 0.0135)
    Part("Dagger_Guard", "darksteel").add(*box((0.09, 0.016, 0.012), (0.0, 0.0, 0.052))).build(root)
    Part("Dagger_Blade", "steel").add(*blade(0.058, 0.22, 0.017, 0.009, 0.0042, 0.003, 0.27, "diamond")).build(root)


def build_athame(root):
    Part("Athame_Pommel", "bone").add(*lathe([(-0.07, 0.0), (-0.066, 0.012), (-0.056, 0.017), (-0.048, 0.012)], 10)).build(root)
    grip("Athame_Grip", root, -0.048, 0.044, 0.0135, "darksteel", 5, 8)
    fit = Part("Athame_Fittings", "brass")
    fit.add(*tube([(x, 0, 0.05 + 0.022 * (x / 0.048) ** 2) for x in (-0.048, -0.03, -0.012, 0.0, 0.012, 0.03, 0.048)], 0.006))
    band(fit, -0.004, 0.0152, 0.008)
    fit.build(root)
    Part("Athame_Blade", "darksteel").add(*blade(0.056, 0.23, 0, 0, 0.0045, 0.003, 0.27, "diamond", 0, 5, [0.014, 0.019, 0.017, 0.013, 0.008])).build(root)
    Part("Athame_Inlay", "accent").add(*box((0.004, 0.0094, 0.12), (0.0, 0.0, 0.14))).build(root)


def _two_hand_sword(root, name, quillons, blade_args, pommel_r=0.026):
    pom = Part(name + "_Pommel", "steel")
    pommel(pom, -0.19, pommel_r, 0.04, 12)
    pom.build(root)
    grip(name + "_Grip", root, -0.172, 0.052, 0.017)
    Part(name + "_Fittings", "brass").add(*lathe([(0.048, 0.019), (0.058, 0.019)], 8, False)).add(*lathe([(-0.176, 0.019), (-0.168, 0.019)], 8, False)).build(root)
    quillons(Part(name + "_Guard", "steel")).build(root)
    Part(name + "_Blade", "steel").add(*blade(*blade_args)).build(root)
    marker(root, "offhand_grip", (0, 0, -0.12))


def build_greatsword(root):
    def guard(p):
        p.add(*box((0.3, 0.032, 0.022), (0.0, 0.0, 0.068)))
        for side in (-1, 1):
            p.add(*box((0.024, 0.036, 0.034), (side * 0.15, 0.0, 0.068)))
        p.add(*box((0.07, 0.014, 0.05), (0.0, 0.0, 0.1)))
        return p
    _two_hand_sword(root, "Greatsword", guard, (0.08, 0.95, 0.031, 0.019, 0.0065, 0.0035, 1.02))


def build_claymore(root):
    def guard(p):
        p.add(*box((0.05, 0.03, 0.026), (0.0, 0.0, 0.066)))
        for side in (-1, 1):
            pts = [(side * 0.02, 0, 0.066), (side * 0.07, 0, 0.09), (side * 0.12, 0, 0.12), (side * 0.145, 0, 0.14)]
            p.add(*tube(pts, 0.007))
            c = Vector((side * 0.16, 0, 0.152))
            ring = [c + Vector((math.cos(a) * 0.016, 0, math.sin(a) * 0.016)) for a in (2 * math.pi * i / 12 for i in range(13))]
            p.add(*tube(ring, 0.004, 6))
        return p
    _two_hand_sword(root, "Claymore", guard, (0.08, 0.95, 0.028, 0.017, 0.006, 0.0032, 1.02), 0.024)


def build_greataxe(root):
    Part("Greataxe_Haft", "wood").add(*lathe([(-0.32, 0.0175), (0.72, 0.016)], 8, False)).build(root)
    grip("Greataxe_Grip", root, -0.06, 0.06, 0.0185)
    grip("Greataxe_OffGrip", root, -0.28, -0.16, 0.0185)
    metal = Part("Greataxe_Fittings", "darksteel")
    metal.add(*lathe([(-0.36, 0.0), (-0.345, 0.016), (-0.32, 0.02), (-0.31, 0.02)], 8, False))
    metal.add(*box((0.05, 0.042, 0.13), (0.0, 0.0, 0.64)))
    metal.add(*lathe([(0.0, 0.012), (0.05, 0.0)], 4, False), at(z=0.705, rz=45))
    metal.build(root)
    bit = [(0.024, 0.6), (0.08, 0.585), (0.13, 0.535), (0.16, 0.57), (0.175, 0.64), (0.16, 0.71), (0.13, 0.745), (0.08, 0.695), (0.024, 0.68)]
    head = Part("Greataxe_Head", "steel")
    for side in (-1, 1):
        head.add(*prism(bit, 0.012), Matrix.Diagonal((side, 1, 1, 1)))
    head.build(root)
    bands = Part("Greataxe_Bands", "brass")
    for z in (0.12, 0.45, 0.55):
        band(bands, z, 0.0185)
    bands.build(root)
    marker(root, "offhand_grip", (0, 0, -0.22))


def _pole(root, name, z0, z1, off_z, mat="wood", r=0.016):
    Part(name + "_Shaft", mat).add(*lathe([(z0, r * 1.05), (z1, r)], 8, mat != "wood")).build(root)
    grip(name + "_Grip", root, -0.06, 0.06, r + 0.0015)
    grip(name + "_OffGrip", root, off_z - 0.06, off_z + 0.06, r + 0.0015)
    marker(root, "offhand_grip", (0, 0, off_z))


def build_spear(root):
    _pole(root, "Spear", -0.35, 1.1, 0.42)
    metal = Part("Spear_Fittings", "darksteel")
    metal.add(*lathe([(-0.42, 0.0), (-0.36, 0.017)], 6, False))
    metal.add(*lathe([(1.08, 0.019), (1.15, 0.015), (1.17, 0.011)], 8))
    metal.build(root)
    Part("Spear_Head", "steel").add(*blade(1.165, 1.33, 0, 0, 0.007, 0.004, 1.4, "diamond", 0, 5, [0.012, 0.032, 0.03, 0.022, 0.011])).build(root)
    bands = Part("Spear_Bands", "brass")
    for z in (0.12, 0.3, 1.03):
        band(bands, z, 0.018)
    bands.build(root)


def build_shock_lance(root):
    _pole(root, "ShockLance", -0.25, 0.98, 0.36, "darksteel", 0.016)
    Part("ShockLance_Vamplate", "steel").add(*lathe([(0.06, 0.0), (0.065, 0.075), (0.08, 0.072), (0.2, 0.02)], 14)).build(root)
    brass = Part("ShockLance_Coils", "brass")
    for i in range(6):
        band(brass, 0.52 + i * 0.07, 0.024, 0.014)
    brass.add(*lathe([(-0.32, 0.0), (-0.25, 0.018)], 6, False))
    brass.build(root)
    tip = Part("ShockLance_Tip", "steel")
    tip.add(*lathe([(0.98, 0.022), (1.04, 0.016), (1.15, 0.0)], 4, False), at(rz=45))
    tip.build(root)
    Part("ShockLance_Glow", "accent").add(*lathe([(0.995, 0.03), (1.015, 0.03)], 12)).build(root)


def build_halberd(root):
    _pole(root, "Halberd", -0.35, 1.12, 0.35)
    metal = Part("Halberd_Fittings", "darksteel")
    metal.add(*lathe([(-0.42, 0.0), (-0.36, 0.017)], 6, False))
    metal.add(*box((0.036, 0.036, 0.16), (0.0, 0.0, 1.06)))
    for side in (-1, 1):
        metal.add(*box((0.012, 0.004, 0.22), (0.0, side * 0.018, 0.92)))
    metal.build(root)
    head = Part("Halberd_Head", "steel")
    head.add(*prism([(0.016, 0.99), (0.07, 0.965), (0.13, 0.93), (0.165, 1.0), (0.168, 1.08), (0.15, 1.15), (0.07, 1.11), (0.016, 1.11)], 0.01))
    head.add(*prism([(-0.016, 1.02), (-0.06, 1.04), (-0.13, 1.03), (-0.06, 1.07), (-0.016, 1.09)], 0.012))
    head.add(*blade(1.14, 1.23, 0.014, 0.009, 0.007, 0.0045, 1.28, "diamond"))
    head.build(root)
    rivets = Part("Halberd_Rivets", "brass")
    for z in (0.86, 0.96):
        rivets.add(*lathe([(-0.021, 0.004), (0.021, 0.004)], 6, False), at(z=z, rx=90))
    rivets.build(root)


def build_staff(root):
    Part("Staff_Shaft", "wood").add(*lathe([(-0.48, 0.016), (-0.1, 0.018), (0.2, 0.018), (0.55, 0.016)], 8, False)).build(root)
    grip("Staff_Grip", root, -0.06, 0.06, 0.0195)
    grip("Staff_OffGrip", root, -0.33, -0.21, 0.0195)
    brass = Part("Staff_Fittings", "brass")
    brass.add(*lathe([(-0.52, 0.0), (-0.5, 0.014), (-0.47, 0.019)], 8, False))
    brass.add(*lathe([(0.52, 0.019), (0.565, 0.024), (0.575, 0.02)], 10, False))
    for k in range(4):
        a = math.pi * 0.5 * k + math.pi * 0.25
        d = Vector((math.cos(a), math.sin(a), 0))
        brass.add(*tube([d * 0.018 + Vector((0, 0, 0.565)), d * 0.045 + Vector((0, 0, 0.59)), d * 0.055 + Vector((0, 0, 0.625)), d * 0.03 + Vector((0, 0, 0.66))], [0.006, 0.005, 0.004, 0.003], 6))
    brass.build(root)
    Part("Staff_Orb", "accent").add(*sphere(0.045, 14, 8), at(z=0.615)).build(root)
    marker(root, "offhand_grip", (0, 0, -0.27))


def build_wand(root):
    Part("Wand_Shaft", "wood").add(*lathe([(-0.07, 0.014), (0.27, 0.009)], 8)).build(root)
    Part("Wand_Grip", "leather").add(*cyl(0.017, 0.017, 0.05), at(z=-0.06)).build(root)
    Part("Wand_Ferrule", "brass").add(*lathe([(0.24, 0.016), (0.26, 0.012)], 8, False)).build(root)
    Part("Wand_Orb", "accent").add(*sphere(0.022), at(z=0.285)).build(root)


def build_whip(root):
    Part("Whip_Handle", "leather").add(*cyl(0.016, 0.018, 0.22), GODOT @ at(y=0.02, rx=-90)).build(root)
    metal = Part("Whip_Fittings", "steel")
    metal.add(*sphere(0.024), GODOT @ at(y=-0.1))
    metal.add(*cyl(0.021, 0.021, 0.025, 10, False), GODOT @ at(y=0.13, rx=-90))
    metal.build(root)
    p, d, r = Vector((0, 0.14, 0)), Vector((0, 0.6, -0.8)).normalized(), 0.012
    pts, radii = [p.copy()], [r]
    for _ in range(14):
        p = p + d * 0.07
        d = (d + Vector((0.05, -0.22, 0.04))).normalized()
        r = max(r * 0.9, 0.004)
        pts.append(p.copy())
        radii.append(r)
    radii[-1] = 0.0015
    Part("Whip_Lash", "leather").add(*tube(pts, radii, 6), GODOT).build(root)


def _gauntlet(root, name, kind, left):
    side = -1.0 if left else 1.0
    m = FORWARD @ Matrix.Diagonal((side, 1, 1, 1))
    metal = "darksteel" if kind == "spell" else "steel"
    shell = Part(name + "_Shell", metal)
    shell.add(*box((0.1, 0.095, 0.11), (0, 0, -0.01)), m)
    for k in range(4):
        shell.add(*box((0.022, 0.025, 0.03), ((k - 1.5) * 0.024, 0.052, -0.075)), m)
    shell.add(*box((0.035, 0.04, 0.06), (-0.055, -0.01, -0.03)), m)
    shell.add(*lathe([(0.04, 0.045), (0.14, 0.05)], 12), m @ at(y=-0.005))
    shell.build(root)
    trim = Part(name + "_Trim", "darksteel")
    trim.add(*box((0.105, 0.03, 0.035), (0, 0.045, -0.06)), m)
    if kind == "plain":
        trim.add(*box((0.06, 0.012, 0.12), (0, 0.052, 0.11)), m)
    trim.build(root)
    if kind == "pressure":
        brass = Part(name + "_Pistons", "brass")
        for x in (0.03, -0.03):
            brass.add(*lathe([(-0.04, 0.012), (0.14, 0.012)], 8), m @ at(x, 0.06, 0.0))
        brass.add(*lathe([(0.125, 0.03), (0.215, 0.03)], 12), m @ at(y=0.06))
        brass.build(root)
        Part(name + "_Glow", "accent").add(*box((0.06, 0.012, 0.02), (0, 0.077, 0.12)), m).build(root)
    elif kind == "spell":
        glow = Part(name + "_Glow", "accent")
        glow.add(*box((0.012, 0.012, 0.13), (0, 0.05, 0.1)), m)
        glow.add(*sphere(0.022), m @ at(y=0.05))
        glow.build(root)


GAUNTLETS = {"gauntlet": ("Gauntlet", "plain"), "pressure_fist": ("PressureFist", "pressure"), "spell_gauntlet": ("SpellGauntlet", "spell")}


def _gauntlet_builder(name, kind, left):
    return lambda root: _gauntlet(root, name + ("_L" if left else ""), kind, left)


# key: (object name, builder, weapon_type, family, hide_hand)
BUILDERS = {
    "mace": ("Mace", build_mace, "Mace", "blunt", False),
    "war_pick": ("WarPick", build_war_pick, "War Pick", "blunt", False),
    "rapier": ("Rapier", build_rapier, "Rapier", "thrust", False),
    "shortsword": ("Shortsword", build_shortsword, "Shortsword", "blade", False),
    "saber": ("Saber", build_saber, "Saber", "blade", False),
    "cutlass": ("Cutlass", build_cutlass, "Cutlass", "blade", False),
    "dagger": ("Dagger", build_dagger, "Dagger", "thrust", False),
    "athame": ("Athame", build_athame, "Athame", "thrust", False),
    "greatsword": ("Greatsword", build_greatsword, "Greatsword", "heavy", False),
    "claymore": ("Claymore", build_claymore, "Claymore", "heavy", False),
    "greataxe": ("Greataxe", build_greataxe, "Greataxe", "heavy", False),
    "spear": ("Spear", build_spear, "Spear", "spear", False),
    "shock_lance": ("ShockLance", build_shock_lance, "Shock Lance", "spear", False),
    "halberd": ("Halberd", build_halberd, "Halberd", "halberd", False),
    "staff": ("Staff", build_staff, "Staff", "staff", False),
    "whip": ("Whip", build_whip, "Whip", "whip", False),
    "wand": ("Wand", build_wand, "Wand", "wand", False),
}
for _key, (_name, _kind) in GAUNTLETS.items():
    _type = {"gauntlet": "Gauntlet", "pressure_fist": "Pressure Fist", "spell_gauntlet": "Spell Gauntlet"}[_key]
    BUILDERS[_key] = (_name, _gauntlet_builder(_name, _kind, False), _type, "fist", True)
    BUILDERS[_key + "_left"] = (_name + "_L", _gauntlet_builder(_name, _kind, True), _type + " (left)", "fist", True)


def collection_for(name):
    col = bpy.data.collections.get("WPN_" + name)
    if col:
        for obj in list(col.objects):
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if data and data.users == 0:
                bpy.data.meshes.remove(data)
    else:
        col = bpy.data.collections.new("WPN_" + name)
        bpy.context.scene.collection.children.link(col)
    return col


def export(root, path):
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True)


def _godot(v):
    return [round(v.x, 4) + 0.0, round(v.z, 4) + 0.0, round(-v.y, 4) + 0.0]


def write_manifest(entries):
    path = os.path.join(EXPORT_DIR, "weapons_manifest.json")
    manifest = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            manifest = json.load(f)
    manifest.update(entries)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(manifest.items())), f, indent=2)


def main():
    keys = BUILD or list(BUILDERS)
    entries = {}
    for i, key in enumerate(keys):
        name, builder, weapon_type, family, hide_hand = BUILDERS[key]
        col = collection_for(name)
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = "ARROWS"
        root.empty_display_size = 0.05
        col.objects.link(root)
        builder(root)
        entry = {"file": "res://assets/models/weapons/%s.glb" % key, "weapon_type": weapon_type, "family": family, "hide_hand": hide_hand}
        grip_marker = next((c for c in root.children if c.name.startswith("offhand_grip")), None)
        if grip_marker:
            entry["offhand_grip"] = _godot(grip_marker.location)
        entries[key] = entry
        if EXPORT:
            export(root, os.path.join(EXPORT_DIR, key + ".glb"))
        root.location = ((i % 12) * 0.3, 0.0, -(i // 12) * 1.6)
    if EXPORT:
        write_manifest(entries)
    print("Aether weapons built:", ", ".join(keys))


main()
