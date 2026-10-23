#!/usr/bin/env python3
"""Предпросмотр моделей TechCore: изометрический рендер геометрии блоков с текстурами.

Нужен Pillow (pip install pillow). Запуск из корня репозитория:
    python3 TechCore/tools/preview.py            # все блоки → TechCore/docs/preview.png
    python3 TechCore/tools/preview.py press out.png '{"techcore:phase": 1}'
Рендер упрощённый (сортировка граней по глубине) и служит для визуального контроля моделей,
а не для точного воспроизведения картинки игры.
"""
import json, sys, math, os, re, tempfile
from PIL import Image
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RP = os.path.join(ROOT, 'resource_pack')
BP = os.path.join(ROOT, 'behavior_pack')
terrain = json.load(open(f'{RP}/textures/terrain_texture.json'))['texture_data']
texcache = {}
def tex(atlas):
    if atlas not in texcache:
        p = terrain[atlas]['textures']
        im = Image.open(f'{RP}/{p}.png').convert('RGBA')
        w,h = im.size
        if h > w: im = im.crop((0,0,w,w))
        texcache[atlas] = im
    return texcache[atlas]

def molang(expr, states):
    if isinstance(expr, bool): return expr
    e = expr
    def rep(m):
        v = states.get(m.group(1), 0)
        return repr(v)
    e = re.sub(r"q\.block_state\('([^']+)'\)", rep, e)
    e = e.replace('&&',' and ').replace('||',' or ').replace('!',' not ').replace(' not =','!=')
    e = e.replace('true','True').replace('false','False')
    return bool(eval(e))

def render(block_name, states, out, scale=10, view_yaw=45):
    bj = json.load(open(f'{BP}/blocks/{block_name}.json'))['minecraft:block']
    comps = dict(bj['components'])
    for p in bj.get('permutations', []):
        try:
            if molang(p['condition'], states): comps.update(p['components'])
        except Exception as ex:
            print('cond err', p['condition'], ex)
    g = comps['minecraft:geometry']
    gid = g if isinstance(g,str) else g['identifier']
    vis = {} if isinstance(g,str) else g.get('bone_visibility', {})
    mats = comps['minecraft:material_instances']
    geo = None
    for f in os.listdir(f'{RP}/models/blocks'):
        d = json.load(open(f'{RP}/models/blocks/{f}'))
        for gg in d['minecraft:geometry']:
            if gg['description']['identifier'] == gid: geo = gg
    rot = comps.get('minecraft:transformation', {}).get('rotation', [0,0,0])[1]
    W = H = 48*scale
    img = Image.new('RGBA', (W,H), (40,44,52,255))
    faces = []
    ya = math.radians(view_yaw); pitch = math.radians(30)
    br = math.radians(rot)
    def tr(p):
        x,y,z = p
        # поворот блока (transformation), затем вид
        x,z = x*math.cos(br) + z*math.sin(br), -x*math.sin(br) + z*math.cos(br)
        X = x*math.cos(ya) - z*math.sin(ya)
        Z = x*math.sin(ya) + z*math.cos(ya)
        Y = y*math.cos(pitch) - Z*math.sin(pitch)
        D = y*math.sin(pitch) + Z*math.cos(pitch)
        return (W/2 + X*scale, H*0.68 - Y*scale, D)
    for b in geo['bones']:
        v = vis.get(b['name'], True)
        if not molang(v, states): continue
        for c in b.get('cubes', []):
            ox,oy,oz = c['origin']; sx,sy,sz = c['size']
            x0,y0,z0,x1,y1,z1 = ox,oy,oz,ox+sx,oy+sy,oz+sz
            F = {
              'north': [(x1,y1,z0),(x0,y1,z0),(x0,y0,z0),(x1,y0,z0)],
              'south': [(x0,y1,z1),(x1,y1,z1),(x1,y0,z1),(x0,y0,z1)],
              'east':  [(x1,y1,z1),(x1,y1,z0),(x1,y0,z0),(x1,y0,z1)],
              'west':  [(x0,y1,z0),(x0,y1,z1),(x0,y0,z1),(x0,y0,z0)],
              'up':    [(x0,y1,z0),(x1,y1,z0),(x1,y1,z1),(x0,y1,z1)],
              'down':  [(x0,y0,z1),(x1,y0,z1),(x1,y0,z0),(x0,y0,z0)],
            }
            light = {'north':0.7,'south':0.85,'east':0.75,'west':0.8,'up':1.0,'down':0.5}
            for fname, uvd in c['uv'].items():
                pts = F[fname]
                mi = uvd.get('material_instance','*')
                m = mats.get(mi, mats.get('*'))
                if isinstance(m, str): m = mats[m]
                faces.append((pts, m['texture'], uvd['uv'], uvd['uv_size'], light[fname]))
    # Сортировка по глубине центра (дальние раньше)
    def depth(f):
        return sum(tr(p)[2] for p in f[0])/4
    faces.sort(key=depth)
    px = img.load()
    for pts, atlas, uv, uvs, lt in faces:
        P = [tr(p) for p in pts]
        a, b, d = P[0], P[1], P[3]
        ex = (b[0]-a[0], b[1]-a[1]); ey = (d[0]-a[0], d[1]-a[1])
        det = ex[0]*ey[1]-ex[1]*ey[0]
        if abs(det) < 1e-6: continue
        if det < 0 and False: continue
        t = tex(atlas); tw,th = t.size
        tp = t.load()
        minx = int(max(0, min(p[0] for p in P))); maxx = int(min(W-1, max(p[0] for p in P))+1)
        miny = int(max(0, min(p[1] for p in P))); maxy = int(min(H-1, max(p[1] for p in P))+1)
        for yy in range(miny, maxy):
            for xx in range(minx, maxx):
                qx, qy = xx+0.5-a[0], yy+0.5-a[1]
                u = (qx*ey[1]-qy*ey[0])/det; v = (ex[0]*qy-ex[1]*qx)/det
                if 0 <= u < 1 and 0 <= v < 1:
                    tu = (uv[0] + u*uvs[0])/16*tw; tv = (uv[1] + v*uvs[1])/16*th
                    cc = tp[min(tw-1,int(tu)), min(th-1,int(tv))]
                    if cc[3] < 128: continue
                    px[xx,yy] = (int(cc[0]*lt), int(cc[1]*lt), int(cc[2]*lt), 255)
    img.save(out)

def render_all(out):
    from PIL import ImageDraw
    tmp = tempfile.mkdtemp()
    BLOCKS_DIR=os.path.join(BP, 'blocks')
    names = sorted(f[:-5] for f in os.listdir(BLOCKS_DIR))
    cfg = {
     'copper_wire': {'techcore:c_e':True,'techcore:c_w':True,'techcore:c_u':True},
     'insulated_wire': {'techcore:c_n':True,'techcore:c_s':True,'techcore:c_e':True},
     'reinforced_wire': {'techcore:c_e':True,'techcore:c_w':True},
     'superconductor_wire': {'techcore:c_n':True,'techcore:c_d':True,'techcore:c_e':True},
     'fluid_pipe': {'techcore:c_e':True,'techcore:c_w':True,'techcore:c_u':True},
     'conveyor': {'techcore:loaded':True}, 'item_filter': {'techcore:loaded':True},
     'fuel_tank': {'techcore:fluid':1,'techcore:level':3},
     'battery_basic': {'techcore:level':3},
    }
    imgs=[]
    for n in names:
        st = {'techcore:status':1,'minecraft:cardinal_direction':'south','minecraft:multi_block_part':0}
        st.update(cfg.get(n,{}))
        if n.startswith('wind_turbine'):
            parts = {'1':2,'2':2,'3':3,'4':3,'5':4}[n[-1]]
            # Собираем башню из частей
            tiles=[]
            for p in range(parts):
                s2=dict(st); s2['minecraft:multi_block_part']=p; s2['techcore:spin']=0
                render(n, s2, os.path.join(tmp, f'tmp_{p}.png'), scale=5)
                tiles.append(Image.open(os.path.join(tmp, f'tmp_{p}.png')))
            w,h = tiles[0].size
            step = int(16*5*0.866)
            canvas = Image.new('RGBA',(w, h+step*(parts-1)),(40,44,52,255))
            for p,t in enumerate(tiles):
                t2 = t.copy(); px=t2.load()
                for yy in range(t2.height):
                    for xx in range(t2.width):
                        if px[xx,yy][:3]==(40,44,52): px[xx,yy]=(0,0,0,0)
                canvas.alpha_composite(t2,(0, step*(parts-1-p)))
            im = canvas.resize((w, h))
        else:
            render(n, st, os.path.join(tmp, 'tmp.png'), scale=5)
            im = Image.open(os.path.join(tmp, 'tmp.png'))
        d = ImageDraw.Draw(im); d.text((4,4), n, fill=(230,230,230,255))
        imgs.append(im)
    w,h = imgs[0].size
    cols=6; rows=(len(imgs)+cols-1)//cols
    sheet=Image.new('RGBA',(cols*w,rows*h),(30,30,36,255))
    for i,im in enumerate(imgs): sheet.paste(im.resize((w,h)),((i%cols)*w,(i//cols)*h))
    sheet.save(out); print(out, len(imgs), sheet.size)


if __name__ == '__main__':
    if len(sys.argv) <= 2:
        render_all(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'docs', 'preview.png'))
    else:
        render(sys.argv[1], json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}, sys.argv[2])
