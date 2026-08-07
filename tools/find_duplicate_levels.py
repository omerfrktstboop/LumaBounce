"""Bolum kutuphanesindeki TEKRARLARI bulur (gelistirme araci, oyuna dahil degil).

Uc ayri "ayni" tanimi raporlanir, cunku uclu de farkli bir tasarim sorunudur:

  1. BIREBIR AYNI   - paneller, bloklar, engeller, hedef ve firlatici tamamen
                      ayni. Oyuncu icin ayni bolumu iki kez oynamak demektir.
  2. AYNA KOPYASI   - biri digerinin x-ekseninde aynalanmisi (x -> 720-x,
                      aci -> -aci). Oynanisi neredeyse ayni; kutuphanede bir
                      miktar bilerek kullanilir ama fazlasi tekrar hissi verir.
  3. AYNI ISKELET   - paneller ve hedef ayni, yalnizca blok/engel dizilimi
                      farkli. Tek basina kusur degildir (bir sablonun uzerine
                      mekanik kurmak mesru bir tasarimdir) ama ayni iskelet
                      cok tekrarlaniyorsa bant gorsel olarak monotonlasir.

Kullanim:
    py -3 tools/find_duplicate_levels.py
    python3 tools/find_duplicate_levels.py
"""

import os
import re
from collections import defaultdict

LEVELS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "levels")
PLAY_WIDTH = 720.0
# Kayan nokta gurultusu tekrarlari gizlemesin diye kaba yuvarlama.
NDIGITS = 1

VECTOR_RE = re.compile(r"Vector2\(\s*([-\d.eE]+)\s*,\s*([-\d.eE]+)\s*\)")
SUBRES_RE = re.compile(r'SubResource\("([^"]+)"\)')


def r(value):
    return round(float(value), NDIGITS)


def parse_level(path):
    """.tres dosyasini alt kaynaklara ve ana kaynaga ayirir."""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    blocks = []
    current = None
    for line in text.splitlines():
        stripped = line.strip()
        header = re.match(r'\[sub_resource .*id="([^"]+)"\]', stripped)
        if header:
            current = {"__id__": header.group(1)}
            blocks.append(current)
            continue
        if stripped.startswith("[resource]"):
            current = {"__id__": "__resource__"}
            blocks.append(current)
            continue
        if stripped.startswith("["):
            current = None
            continue
        if current is None or "=" not in stripped:
            continue
        key, _, raw = stripped.partition("=")
        current[key.strip()] = raw.strip()

    subs = {b["__id__"]: b for b in blocks if b["__id__"] != "__resource__"}
    resource = next((b for b in blocks if b["__id__"] == "__resource__"), {})
    return subs, resource


def vec(raw, default=(0.0, 0.0)):
    if raw is None:
        return default
    match = VECTOR_RE.search(raw)
    if not match:
        return default
    return (float(match.group(1)), float(match.group(2)))


def num(raw, default=0.0):
    if raw is None:
        return default
    try:
        return float(str(raw).strip())
    except ValueError:
        return default


def referenced(resource, key):
    return SUBRES_RE.findall(resource.get(key, ""))


def build_signature(subs, resource, mirror=False):
    """Bolumun oynanisini belirleyen her seyi kanonik bir demete cevirir.

    display_name, yildiz esikleri ve level_id BILEREK disarida: iki bolum
    yalnizca adiyla farklilasiyorsa oyuncu icin ayni bolumdur.
    """
    def x(value):
        return r(PLAY_WIDTH - value) if mirror else r(value)

    def angle(value):
        return r(-value) if mirror else r(value)

    launcher = vec(resource.get("launcher_position"), (360.0, 1120.0))
    target = vec(resource.get("target_position"), (360.0, 300.0))

    panels = []
    for rid in referenced(resource, "panels"):
        sub = subs.get(rid, {})
        position = vec(sub.get("position"))
        panels.append((
            x(position[0]), r(position[1]),
            angle(num(sub.get("rotation_degrees"))),
            r(num(sub.get("length"), 300.0)),
            r(num(sub.get("thickness"), 26.0)),
        ))

    blocks = []
    for rid in referenced(resource, "breakable_blocks"):
        sub = subs.get(rid, {})
        position = vec(sub.get("position"))
        size = vec(sub.get("size"), (160.0, 44.0))
        blocks.append((
            x(position[0]), r(position[1]),
            r(size[0]), r(size[1]),
            angle(num(sub.get("rotation_degrees"))),
            int(num(sub.get("hit_points"), 1)),
        ))

    obstacles = []
    for rid in referenced(resource, "obstacles"):
        sub = subs.get(rid, {})
        position = vec(sub.get("position"))
        size = vec(sub.get("size"), (150.0, 28.0))
        obstacles.append((
            int(num(sub.get("kind"), 0)),
            x(position[0]), r(position[1]),
            r(size[0]), r(size[1]),
            angle(num(sub.get("rotation_degrees"))),
            r(num(sub.get("inner_radius"), 42.0)),
            int(num(sub.get("spoke_count"), 6)),
            # Aynalamada donus yonu ve hareket ekseni de terslenir.
            angle(num(sub.get("angular_speed_degrees"), 55.0)),
            angle(num(sub.get("motion_direction_degrees"), 0.0)),
            r(num(sub.get("travel_distance"), 110.0)),
            r(num(sub.get("motion_period"), 2.8)),
        ))

    # Aynalamada sol/sag duvar bosluklari yer degistirir.
    left = resource.get("left_wall_segments", "")
    right = resource.get("right_wall_segments", "")
    walls = (right, left) if mirror else (left, right)

    return (
        (x(launcher[0]), r(launcher[1])),
        (x(target[0]), r(target[1])),
        tuple(sorted(panels)),
        tuple(sorted(blocks)),
        tuple(sorted(obstacles)),
        walls,
    )


def skeleton_signature(signature):
    """Yalnizca iskelet: firlatici + hedef + paneller (blok/engel haric)."""
    return signature[0], signature[1], signature[2]


def describe(signature):
    return "paneller=%d bloklar=%d engeller=%d hedef=%s" % (
        len(signature[2]), len(signature[3]), len(signature[4]), signature[1])


def main():
    levels = {}
    mirrors = {}
    names = {}
    missing = []

    for level_id in range(1, 126):
        path = os.path.join(LEVELS_DIR, "level_%d.tres" % level_id)
        if not os.path.exists(path):
            path = os.path.join(LEVELS_DIR, "level_%02d.tres" % level_id)
        if not os.path.exists(path):
            missing.append(level_id)
            continue
        subs, resource = parse_level(path)
        levels[level_id] = build_signature(subs, resource, mirror=False)
        mirrors[level_id] = build_signature(subs, resource, mirror=True)
        names[level_id] = resource.get("display_name", "").strip('"')

    if missing:
        print("UYARI: bulunamayan bolumler: %s" % missing)

    ordered = sorted(levels)

    # 1) Birebir ayni
    exact = defaultdict(list)
    for level_id in ordered:
        exact[levels[level_id]].append(level_id)
    exact_groups = [ids for ids in exact.values() if len(ids) > 1]

    # 2) Ayna kopyasi (birebir ayni olanlar haric)
    same_group = {}
    for ids in exact_groups:
        for level_id in ids:
            same_group[level_id] = ids[0]
    mirror_pairs = []
    for i, a in enumerate(ordered):
        for b in ordered[i + 1:]:
            if same_group.get(a) is not None and same_group.get(a) == same_group.get(b):
                continue
            if levels[a] == mirrors[b]:
                mirror_pairs.append((a, b))

    # 3) Ayni iskelet (paneller + hedef ayni)
    skeletons = defaultdict(list)
    for level_id in ordered:
        skeletons[skeleton_signature(levels[level_id])].append(level_id)
    skeleton_groups = sorted(
        (ids for ids in skeletons.values() if len(ids) > 1),
        key=lambda ids: (-len(ids), ids[0]))

    print("=" * 72)
    print("1) BIREBIR AYNI BOLUMLER")
    print("=" * 72)
    if not exact_groups:
        print("  yok")
    for ids in sorted(exact_groups, key=lambda g: g[0]):
        label = ", ".join("%d (%s)" % (i, names[i]) for i in ids)
        print("  %s" % label)
        print("      %s" % describe(levels[ids[0]]))

    print()
    print("=" * 72)
    print("2) AYNA KOPYASI BOLUMLER (x-ekseninde yansima)")
    print("=" * 72)
    if not mirror_pairs:
        print("  yok")
    for a, b in mirror_pairs:
        print("  %d (%s)  <->  %d (%s)" % (a, names[a], b, names[b]))

    print()
    print("=" * 72)
    print("3) AYNI ISKELET (ayni panel yerlesimi + ayni hedef)")
    print("=" * 72)
    if not skeleton_groups:
        print("  yok")
    for ids in skeleton_groups:
        print("  %2d bolum: %s" % (len(ids), ", ".join(str(i) for i in ids)))
        print("      %s" % describe(levels[ids[0]]))

    print()
    print("=" * 72)
    print("OZET")
    print("=" * 72)
    print("  incelenen bolum          : %d" % len(levels))
    print("  birebir ayni grup        : %d (%d bolum)"
          % (len(exact_groups), sum(len(g) for g in exact_groups)))
    print("  ayna kopyasi cift        : %d" % len(mirror_pairs))
    print("  ayni iskelet grubu       : %d (%d bolum)"
          % (len(skeleton_groups), sum(len(g) for g in skeleton_groups)))


if __name__ == "__main__":
    main()
