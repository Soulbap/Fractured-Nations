"""NAV-PERF-01C: static road connectivity check of a generated world (read-only).

Compares the two road representations that exist outside the running game:

  * worlds/<world>/source/roads.json  - the road data the game loads (RoadNetwork, VehicleRouter, StrategicRoutes read only this);
  * the Road Generator scene          - RoadManager / RoadContainer / RoadPoint / RoadIntersection nodes in scenes/world/<world>.tscn
                                        (what the road meshes and the terrain connector were built from).

It reports, without changing anything:

  * roads.json: road ends (joined / dead end at the map edge / dead end at a settlement or site / near miss to another road /
    unexplained), near misses (an end 10.5-45 m from another road: looks connected, is not), junction entries of the file and the
    roads that meet there, duplicate or degenerate geometry (repeated points, zero-length segments, duplicate roads), components
    when roads are joined the way VehicleRouter joins them (vertices of two roads within 10.5 m);
  * the Road Generator scene: dangling NodePaths, container edges that are not mirrored by the other container, duplicate edges,
    RoadPoints without neighbours, open chain ends, components;
  * both: roads.json roads not covered by RoadPoints and RoadPoints far from every roads.json road, junction entries without an
    intersection, bridge spans without a bridge structure.

    python tools/terrain_ref/road_connectivity.py [--world ref_20km] [--out benchmarks/raw/road_connectivity_static.json]
"""
import argparse
import json
import math
import re
from collections import defaultdict

LINK_M = 10.5          # VehicleRouter.LINK_M: vertices of two roads this close are joined
NEAR_MISS_M = 45.0     # RoadAudit.JOIN_GAP_M
EDGE_M = 9800.0        # |x| or |z| beyond this: the map edge (the world is 20 km, centred)
SITE_M = 450.0         # a dead end this close to a settlement or plateau is taken as an access road
COVER_M = 4.0


def dist2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def seg_dist(p, a, b):
    ax, az = a[0], a[1]
    bx, bz = b[0], b[1]
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / l2))
    return math.hypot(p[0] - (ax + dx * t), p[1] - (az + dz * t))


class Grid:
    def __init__(self, cell=50.0):
        self.cell = cell
        self.g = defaultdict(list)

    def key(self, p):
        return (int(math.floor(p[0] / self.cell)), int(math.floor(p[1] / self.cell)))

    def add(self, p, item):
        self.g[self.key(p)].append((p, item))

    def near(self, p, r):
        k = self.key(p)
        n = int(math.ceil(r / self.cell))
        for dx in range(-n, n + 1):
            for dz in range(-n, n + 1):
                for q, item in self.g.get((k[0] + dx, k[1] + dz), []):
                    if dist2(p, q) <= r:
                        yield q, item


def load_roads(src):
    d = json.load(open(src + 'roads.json', encoding='utf-8'))
    roads = []
    for i, r in enumerate(d['roads']):
        pts = [(p[0], p[2], p[1]) for p in r['points']]  # (x, z, y)
        roads.append({'i': i, 'name': r['name'], 'class': r['class'], 'mesh': bool(r.get('mesh', False)), 'pts': pts, 'bridges': r.get('bridges', []), 'culverts': r.get('culverts', [])})
    return roads, [(j[0], j[2]) for j in d.get('junctions', [])]


def load_sites(src):
    d = json.load(open(src + 'sites.json', encoding='utf-8'))
    out = []
    for k in ('settlements', 'plateaus'):
        for s in d.get(k, []):
            p = s.get('pos') or s.get('center')
            out.append((s['name'], (p[0], p[2])))
    return out


def roads_json_checks(roads, junctions, sites):
    vgrid = Grid(25.0)
    for r in roads:
        for k, p in enumerate(r['pts']):
            vgrid.add(p, (r['i'], k))
    # Components the way VehicleRouter joins roads: consecutive vertices of a road, and vertices of two roads within LINK_M.
    parent = list(range(len(roads)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    links = defaultdict(set)
    for r in roads:
        for k, p in enumerate(r['pts']):
            for q, (ri, kk) in vgrid.near(p, LINK_M):
                if ri != r['i']:
                    links[r['i']].add(ri)
                    a, b = find(r['i']), find(ri)
                    if a != b:
                        parent[a] = b
    comps = defaultdict(list)
    for r in roads:
        comps[find(r['i'])].append(r['i'])
    comp_list = sorted(comps.values(), key=lambda c: -sum(len(roads[i]['pts']) for i in c))
    comp_of = {}
    for ci, c in enumerate(comp_list):
        for i in c:
            comp_of[i] = ci
    # Road ends.
    ends = []
    for r in roads:
        for end_k in (0, len(r['pts']) - 1):
            p = r['pts'][end_k]
            joined = [ri for q, (ri, kk) in vgrid.near(p, LINK_M) if ri != r['i']]
            kind = ''
            near = None
            if joined:
                kind = 'joined'
            elif abs(p[0]) > EDGE_M or abs(p[1]) > EDGE_M:
                kind = 'map edge'
            else:
                best = None
                for q, (ri, kk) in vgrid.near(p, NEAR_MISS_M):
                    if ri == r['i']:
                        continue
                    d = dist2(p, q)
                    if best is None or d < best[0]:
                        best = (d, ri)
                site = min(((dist2(p, s[1]), s[0]) for s in sites), default=(1e9, ''))
                if best is not None:
                    # VehicleRouter repairs gaps up to 32 m (GAP_FIX_M) and plans soft links up to 70 m per vehicle: the
                    # router drives them, the road meshes / decals do not meet.
                    kind = 'near miss, router repairs it' if best[0] <= 32.0 else 'near miss, router soft link'
                    near = {'road': roads[best[1]]['name'], 'gap_m': round(best[0], 1), 'same_component': comp_of[best[1]] == comp_of[r['i']]}
                elif site[0] <= SITE_M:
                    kind = 'dead end at a place'
                    near = {'place': site[1], 'm': round(site[0])}
                elif r['class'] in ('track', 'street'):
                    kind = 'dead end (%s)' % r['class']
                else:
                    kind = 'dead end, unexplained'
            ends.append({'road': r['name'], 'class': r['class'], 'end': 'start' if end_k == 0 else 'end', 'pos': [round(p[0]), round(p[1])], 'kind': kind, 'near': near})
    # Junction entries of the file.
    jrows = []
    for jp in junctions:
        meet = sorted({roads[ri]['name'] for q, (ri, kk) in vgrid.near(jp, 25.0)})
        jrows.append({'pos': [round(jp[0]), round(jp[1])], 'roads': meet, 'ok': len(meet) >= 2})
    dup_j = [[i, j] for i in range(len(junctions)) for j in range(i + 1, len(junctions)) if dist2(junctions[i], junctions[j]) < 1.0]
    # Degenerate geometry.
    zero = []
    for r in roads:
        for k in range(1, len(r['pts'])):
            if dist2(r['pts'][k - 1], r['pts'][k]) < 0.05:
                zero.append({'road': r['name'], 'k': k})
    dups = []
    for a in roads:
        for b in roads:
            if b['i'] <= a['i'] or abs(len(a['pts']) - len(b['pts'])) > 2:
                continue
            same = sum(1 for p in a['pts'][::max(1, len(a['pts']) // 20)] if any(dist2(p, q) < 1.0 for q, (ri, kk) in vgrid.near(p, 1.0) if ri == b['i']))
            if same >= 0.9 * len(a['pts'][::max(1, len(a['pts']) // 20)]):
                dups.append([a['name'], b['name']])
    return {
        'roads': len(roads), 'points': sum(len(r['pts']) for r in roads),
        'components': [{'roads': len(c), 'names': [roads[i]['name'] for i in c][:8], 'km': round(sum(sum(dist2(roads[i]['pts'][k - 1], roads[i]['pts'][k]) for k in range(1, len(roads[i]['pts']))) for i in c) / 1000.0, 2)} for c in comp_list],
        'ends': ends,
        'end_kinds': dict(sorted(defaultdict(int, {k: sum(1 for e in ends if e['kind'] == k) for k in {e['kind'] for e in ends}}).items())),
        'junction_entries': jrows, 'duplicate_junction_entries': dup_j, 'zero_length_segments': zero, 'duplicate_roads': dups,
    }, comp_of


NODE_RE = re.compile(r'^\[node name="([^"]+)" type="[^"]+"(?: parent="([^"]*)")?')


def load_scene(path):
    nodes = {}
    cur = None
    scripts = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('[ext_resource') and 'type="Script"' in line:
                m = re.search(r'path="([^"]+)" id="([^"]+)"', line)
                if m:
                    scripts[m.group(2)] = m.group(1).split('/')[-1]
                continue
            m = NODE_RE.match(line)
            if m:
                name, parent = m.group(1), m.group(2)
                p = name if parent in (None, '.') else (parent + '/' + name if parent else name)
                if parent is None:
                    p = ''
                cur = {'path': p, 'props': {}}
                nodes[p] = cur
                continue
            if line.startswith('['):
                cur = None
                continue
            if cur is not None and ' = ' in line:
                k, v = line.split(' = ', 1)
                cur['props'][k] = v
    for n in nodes.values():
        s = n['props'].get('script', '')
        m = re.search(r'ExtResource\("([^"]+)"\)', s)
        n['script'] = scripts.get(m.group(1), '') if m else ''
        t = n['props'].get('transform', '')
        m = re.search(r'Transform3D\(([^)]*)\)', t)
        if m:
            v = [float(x) for x in m.group(1).split(',')]
            n['pos'] = (v[9], v[11], v[10])
    return nodes


def resolve(base, rel):
    if rel == '':
        return None
    parts = base.split('/') if base else []
    for seg in rel.split('/'):
        if seg == '..':
            parts = parts[:-1]
        elif seg not in ('.', ''):
            parts.append(seg)
    return '/'.join(parts)


def np_list(v):
    return re.findall(r'NodePath\("([^"]*)"\)', v or '')


def scene_checks(nodes, roads, junctions, comp_of):
    rps = {p: n for p, n in nodes.items() if n['script'] == 'road_point.gd'}
    conts = {p: n for p, n in nodes.items() if n['script'] == 'road_container.gd'}
    inters = {p: n for p, n in nodes.items() if n['script'] == 'road_intersection.gd'}
    adj = defaultdict(set)
    dangling = []
    edges_seen = defaultdict(int)

    def link(a, b, why):
        if a == b:
            dangling.append({'from': a, 'why': 'self link (%s)' % why})
            return
        edges_seen[tuple(sorted((a, b)))] += 1
        adj[a].add(b)
        adj[b].add(a)
    for p, n in rps.items():
        for k in ('prior_pt_init', 'next_pt_init'):
            rel = np_list(n['props'].get(k, ''))
            if rel and rel[0] != '':
                t = resolve(p, rel[0])
                if t not in nodes:
                    dangling.append({'from': p, 'prop': k, 'to': t})
                else:
                    link(p, t, k)
    one_way = []
    for p, n in conts.items():
        cs = np_list(n['props'].get('edge_containers'))
        ts = np_list(n['props'].get('edge_rp_targets'))
        ls = np_list(n['props'].get('edge_rp_locals'))
        for i, c in enumerate(cs):
            if c == '':
                continue
            other = resolve(p, c)
            if other not in conts:
                dangling.append({'from': p, 'prop': 'edge_containers', 'to': other})
                continue
            local = resolve(p, ls[i]) if i < len(ls) else None
            target = resolve(other, ts[i]) if i < len(ts) and ts[i] != '' else None
            if local not in nodes or target not in nodes:
                dangling.append({'from': p, 'edge': i, 'local': local, 'target': target})
                continue
            back = np_list(conts[other]['props'].get('edge_containers'))
            if not any(resolve(other, b) == p for b in back if b != ''):
                one_way.append({'from': p, 'to': other})
            link(local, target, 'container edge')
    for p, n in inters.items():
        for e in np_list(n['props'].get('edge_points')):
            t = resolve(p, e)
            if t not in nodes:
                dangling.append({'from': p, 'prop': 'edge_points', 'to': t})
            else:
                link(p, t, 'intersection')
    dup_edges = [list(k) for k, c in edges_seen.items() if c > 2]  # prior/next both ways count twice
    # Components and open ends.
    allp = set(rps) | set(inters)
    seen = set()
    comps = []
    for s in allp:
        if s in seen:
            continue
        stack = [s]
        seen.add(s)
        c = []
        while stack:
            x = stack.pop()
            c.append(x)
            for y in adj[x]:
                if y not in seen and y in allp:
                    seen.add(y)
                    stack.append(y)
        comps.append(c)
    comps.sort(key=len, reverse=True)
    isolated = [p for p in rps if not adj[p]]
    open_ends = [p for p in rps if len(adj[p]) == 1]
    # Coverage against roads.json.
    seg_grid = Grid(50.0)
    for r in roads:
        for k in range(1, len(r['pts'])):
            a, b = r['pts'][k - 1], r['pts'][k]
            seg_grid.add(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2), (r['i'], a, b))
    far_rps = []
    rp_road = {}
    for p, n in rps.items():
        q = (n['pos'][0], n['pos'][1])
        best = (1e9, -1)
        for _, (ri, a, b) in seg_grid.near(q, 120.0):
            d = seg_dist(q, a, b)
            if d < best[0]:
                best = (d, ri)
        rp_road[p] = best[1]
        if best[0] > COVER_M:
            far_rps.append({'rp': p, 'pos': [round(q[0]), round(q[1])], 'nearest_m': round(best[0], 1)})
    rp_grid = Grid(50.0)
    for p, n in rps.items():
        rp_grid.add((n['pos'][0], n['pos'][1]), p)
    uncovered = []
    for r in roads:
        n_pts = 0
        miss = 0
        for k in range(0, len(r['pts']), 3):
            n_pts += 1
            # covered when an RP chain segment passes within COVER_M: sample the polyline against RPs within 60 m
            p = r['pts'][k]
            near = [q for q, _ in rp_grid.near(p, 60.0)]
            if not near:
                miss += 1
        if n_pts and miss / n_pts > 0.05 and r.get('mesh', False):
            uncovered.append({'road': r['name'], 'uncovered_share': round(miss / n_pts, 2)})
    # Open ends of the scene against roads.json ends: an open RP end where roads.json has a joined road is a lost connection.
    lost = []
    vgrid = Grid(25.0)
    for r in roads:
        for k, p in enumerate(r['pts']):
            vgrid.add(p, (r['i'], k))
    for p in open_ends:
        q = (rps[p]['pos'][0], rps[p]['pos'][1])
        others = {ri for _, (ri, kk) in vgrid.near(q, LINK_M + 3.0)}
        if len(others) >= 2:
            lost.append({'rp': p, 'pos': [round(q[0]), round(q[1])], 'roads': sorted(roads[i]['name'] for i in others)})
    # Junction entries against intersections.
    j_missing = []
    for jp in junctions:
        if not any(dist2(jp, (n['pos'][0], n['pos'][1])) < 6.0 for n in inters.values()):
            j_missing.append([round(jp[0]), round(jp[1])])
    # Components: does a scene component span roads of different roads.json components (or one roads.json component split)?
    mixed = []
    for c in comps:
        rc = {comp_of.get(rp_road.get(x, -1), -1) for x in c if x in rp_road and rp_road[x] >= 0}
        if len(rc) > 1:
            mixed.append({'size': len(c), 'roads_json_components': sorted(rc)})
    return {
        'road_points': len(rps), 'containers': len(conts), 'intersections': len(inters), 'edges': len(edges_seen),
        'dangling_paths': dangling, 'one_way_container_edges': one_way, 'duplicate_edges': dup_edges,
        'components': [len(c) for c in comps][:20], 'component_count': len(comps), 'isolated_points': isolated,
        'open_ends': len(open_ends), 'open_ends_where_roads_json_joins': lost, 'points_off_roads_json': far_rps[:40], 'points_off_roads_json_count': len(far_rps),
        'roads_json_not_covered': uncovered, 'junction_entries_without_intersection': j_missing, 'components_mixing_roads_json_components': mixed,
    }


def bridge_checks(nodes, roads):
    # A bridge structure is a group under RoadStructures (modules and piers); its place is the mean of its parts.
    groups = defaultdict(list)
    for p, n in nodes.items():
        parts = p.split('/')
        if len(parts) == 3 and parts[0] == 'RoadStructures' and parts[1].startswith('Bridge') and 'pos' in n:
            groups[parts[0] + '/' + parts[1]].append(n['pos'])
    structs = [(g, {'pos': (sum(q[0] for q in v) / len(v), sum(q[1] for q in v) / len(v), 0.0), 'parts': len(v)}) for g, v in groups.items()]
    out = []
    for r in roads:
        for si, sp in enumerate(r['bridges']):
            a, b = r['pts'][sp[0]], r['pts'][sp[1]]
            c = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
            near = [(round(dist2(c, (n['pos'][0], n['pos'][1])), 1), p) for p, n in structs]
            near.sort()
            out.append({'id': 'bridge_r%d_s%d' % (r['i'], si), 'road': r['name'], 'span_m': round(dist2(a, b), 1), 'centre': [round(c[0]), round(c[1])],
                        'structure': near[0][1] if near and near[0][0] < 60.0 else None, 'structure_m': near[0][0] if near else None})
    return {'spans': out, 'bridge_structures': len(structs), 'spans_without_structure': [s['id'] for s in out if s['structure'] is None]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--world', default='ref_20km')
    ap.add_argument('--out', default='benchmarks/raw/road_connectivity_static.json')
    a = ap.parse_args()
    src = 'worlds/%s/source/' % a.world
    roads, junctions = load_roads(src)
    sites = load_sites(src)
    rj, comp_of = roads_json_checks(roads, junctions, sites)
    nodes = load_scene('scenes/world/%s.tscn' % a.world)
    sc = scene_checks(nodes, roads, junctions, comp_of)
    br = bridge_checks(nodes, roads)
    rep = {'world': a.world, 'roads_json': rj, 'road_generator_scene': sc, 'bridges': br}
    with open(a.out, 'w', encoding='utf-8') as f:
        json.dump(rep, f, indent=2, ensure_ascii=False)
    print('roads.json: %d roads, %d points, %d components (largest %d roads), ends %s' % (rj['roads'], rj['points'], len(rj['components']), rj['components'][0]['roads'], json.dumps(rj['end_kinds'], ensure_ascii=False)))
    nm = [e for e in rj['ends'] if e['kind'].startswith('near miss')]
    print('near misses: %d (%d between different components): %s' % (len(nm), sum(1 for e in nm if not e['near']['same_component']), json.dumps([e for e in nm if not e['near']['same_component']], ensure_ascii=False)))
    print('unexplained dead ends: %s' % json.dumps([e for e in rj['ends'] if e['kind'] == 'dead end, unexplained'], ensure_ascii=False))
    print('junction entries: %s; duplicate entries %s; zero-length segments %d; duplicate roads %s' % (json.dumps([j for j in rj['junction_entries'] if not j['ok']], ensure_ascii=False), rj['duplicate_junction_entries'], len(rj['zero_length_segments']), rj['duplicate_roads']))
    print('scene: %d RoadPoints, %d containers, %d intersections, %d edges, %d components %s, %d isolated points, %d open ends' % (sc['road_points'], sc['containers'], sc['intersections'], sc['edges'], sc['component_count'], sc['components'][:8], len(sc['isolated_points']), sc['open_ends']))
    print('scene problems: dangling %d, one-way container edges %d, duplicate edges %d, open ends where roads.json joins %d, points off roads.json %d, roads.json roads not covered %d, junction entries without intersection %d, components mixing %d' % (
        len(sc['dangling_paths']), len(sc['one_way_container_edges']), len(sc['duplicate_edges']), len(sc['open_ends_where_roads_json_joins']), sc['points_off_roads_json_count'], len(sc['roads_json_not_covered']), len(sc['junction_entries_without_intersection']), len(sc['components_mixing_roads_json_components'])))
    print('bridges: %s; spans without a structure: %s' % (json.dumps([[s['id'], s['road'], s['span_m'], s['structure']] for s in br['spans']], ensure_ascii=False), br['spans_without_structure']))
    print('written', a.out)


if __name__ == '__main__':
    main()
