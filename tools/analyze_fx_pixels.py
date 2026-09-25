"""Strict regional pixel gates; captures are windowed Godot, not synthesized.
Usage: python tools/analyze_fx_pixels.py scope EVIDENCE_DIR
"""
import argparse
import json
from collections import deque
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw


class Gates:
    def __init__(self):
        self.results = []

    def check(self, name, ok, **metrics):
        self.results.append(dict(name=name, ok=bool(ok), **metrics))
        print(('PASS ' if ok else 'FAIL ') + name + ' ' + json.dumps(metrics))

    def save(self, path):
        failures = sum(not r['ok'] for r in self.results)
        result = dict(checks=len(self.results), failures=failures, results=self.results)
        path.write_text(json.dumps(result, indent=2))
        print(f'PIXEL_GATES checks={len(self.results)} failures={failures}')
        return int(failures > 0)


def pixels(folder, name):
    a = np.asarray(Image.open(folder / (name + '.png')).convert('RGBA')).astype(np.float64) / 255
    assert a.shape == (720, 1280, 4) and np.isfinite(a).all(), (name, a.shape)
    return a


def bounded_holes(alpha):
    # Flood exterior zero-alpha pixels; only enclosed transparent components remain.
    zero = alpha == 0
    seen = np.zeros(zero.shape, dtype=bool)
    h, w = zero.shape
    queue = deque()
    for y, x in [(0, x) for x in range(w)] + [(h-1, x) for x in range(w)] + [(y, 0) for y in range(h)] + [(y, w-1) for y in range(h)]:
        if zero[y, x] and not seen[y, x]:
            seen[y, x] = True
            queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for yy, xx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
            if 0 <= yy < h and 0 <= xx < w and zero[yy, xx] and not seen[yy, xx]:
                seen[yy, xx] = True
                queue.append((yy, xx))
    return zero & ~seen


def region(g, name, delta, roi, changed=False):
    n = int(roi.sum())
    maximum = float(delta[roi].max()) if n else None
    mean = float(delta[roi].mean()) if n else None
    # One code value permits only framebuffer UNORM8 rounding, not motion/noise.
    ok = n > 0 and (mean > 0.002 if changed else maximum <= 1/255 + 1e-12)
    g.check(name, ok, population=n, max=maximum, mean=mean)


def scope(folder, g):
    manifest = json.loads((folder / 'capture_manifest.json').read_text())
    g.check('capture completed', manifest['failures'] == 0, captures_checks=manifest['checks'])
    for case in manifest['cases']:
        p = pixels(folder, case + '_primary_oracle')[..., 3]
        e = pixels(folder, case + '_echo_preocclusion_oracle')[..., 3]
        opaque, overlap, exposed = p == 1, (p == 1) & (e > 0.01), (p == 0) & (e > 0.01)
        hidden = case == 'hidden_ancestor'
        if hidden:
            g.check(case + ' actual original hierarchy invisible', not p.any() and not e.any())
        else:
            g.check(case + ' both independent masks populated', p.any() and e.any(), primary=int((p>0).sum()), echo=int((e>0).sum()))
        holes = bounded_holes(p) if case == 'fixture' else None
        if holes is not None:
            g.check('fixture bounded transparent holes', holes.any(), population=int(holes.sum()))
            Image.fromarray((holes*255).astype('uint8')).save(folder / 'fixture_bounded_holes.png')
        for mode in ('EXCLUDE_PRIMARY', 'ECHO_ONLY', 'PRIMARY_ONLY'):
            prefix = case + '_' + mode
            a, n, r = [pixels(folder, prefix+'_'+s)[..., :3] for s in ('active','neutral','repeat')]
            g.check(prefix + ' frozen neutral exact', np.array_equal(n, r), max=float(abs(n-r).max()))
            m = pixels(folder, prefix+'_matte')[..., 3]
            expected = e if mode == 'ECHO_ONLY' else p
            if mode == 'ECHO_ONLY':
                occ = folder / (prefix + '_occluder.png')
                if occ.exists():
                    o = pixels(folder, prefix+'_occluder')[..., 3]
                    g.check(prefix + ' occluder matches original primary', abs(o-p).max() <= 1/255+1e-12, max=float(abs(o-p).max()))
                    m = m * (1-o)
                expected = e * (1-p)
            support = (m > .01) | (expected > .01)
            union = int(support.sum())
            iou = float(((m>.01)&(expected>.01)).sum()/union) if union else None
            error = abs(m-expected)
            g.check(prefix + ' independent alpha max and IoU', error.max() <= 1/255+1e-12 and (hidden or (union>0 and iou>.99)), maximum=float(error.max()), population=union, iou=iou)
            d = abs(a-n)
            if hidden:
                if mode != 'EXCLUDE_PRIMARY': g.check(prefix+' invisible scope no effect', np.array_equal(a,n))
                continue
            if mode == 'PRIMARY_ONLY':
                region(g, prefix+' no leak outside primary', d, p==0)
                region(g, prefix+' affects primary', d, p>.2, True)
            else:
                if case in ('portraits','fixture'):
                    region(g, prefix+' opaque primary protected', d, opaque)
                if mode == 'ECHO_ONLY':
                    if case in ('portraits','fixture'): region(g,prefix+' real preocclusion overlap protected',d,overlap)
                    region(g,prefix+' exposed echo changes',d,exposed,True)
                    region(g,prefix+' no leak outside echo',d,e==0)
                else:
                    region(g,prefix+' nonprimary region changes',d,p==0,True)
                    if holes is not None: region(g,prefix+' actual bounded holes remain effect eligible',d,holes,True)
    contact_sheet(folder, [('fixture_EXCLUDE_PRIMARY_neutral','fixture_EXCLUDE_PRIMARY_active'),('fixture_primary_oracle','fixture_EXCLUDE_PRIMARY_matte'),('fixture_echo_preocclusion_oracle','fixture_ECHO_ONLY_active'),('portraits_EXCLUDE_PRIMARY_neutral','portraits_EXCLUDE_PRIMARY_active')], 'scope_contact_sheet.png')


def artist(folder, g):
    manifest = json.loads((folder / 'artist_manifest.json').read_text())
    g.check('capture completed', manifest['failures'] == 0, capture_checks=manifest['checks'])
    p = pixels(folder, 'primary_oracle')[..., 3]
    e = pixels(folder, 'echo_oracle')[..., 3]
    g.check('real portrait masks populated', (p == 1).any() and ((e > .01) & (p == 0)).any())
    for rec in manifest['records']:
        name, expected = rec['label'], rec['expected']
        a, n, r = [pixels(folder, name+'_'+s)[..., :3] for s in ('active', 'neutral', 'repeat')]
        d = abs(a-n)
        g.check(name+' exact neutral repeat', np.array_equal(n,r), maximum=float(abs(n-r).max()))
        mad = float(d.mean())
        g.check(name+' '+expected, np.array_equal(a,n) if expected == 'neutral' else mad > .0005, mad=mad, time=rec['time'], threshold=.0005)
        if expected in ('echo', 'protected'):
            region(g, name+' opaque primaries protected', d, p == 1)
        if expected == 'echo':
            region(g, name+' pre-occlusion overlap protected', d, (p == 1) & (e > .01))
            region(g, name+' only exposed echoes', d, e == 0)
            region(g, name+' exposed echo response', d, (p == 0) & (e > .01), True)
    g.check('line field does not rotate', np.array_equal(pixels(folder,'lines_only_active'), pixels(folder,'lines_static_later')))
    baseline = pixels(folder,'pattern_progress_2_active')[..., :3]
    for control in ('direction', 'shape', 'scale', 'feather', 'motion'):
        delta = abs(pixels(folder,'pattern_control_'+control+'_active')[..., :3]-baseline)
        g.check('pattern '+control+' visibly functional', delta.mean() > .0005, mad=float(delta.mean()))
    supports = []
    for i in range(5):
        delta = abs(pixels(folder, f'pattern_progress_{i}_active')[..., :3] - pixels(folder, f'pattern_progress_{i}_neutral')[..., :3]).max(axis=2)
        supports.append(delta > .01)
    counts = [int(s.sum()) for s in supports]
    g.check('pattern progress grows spatial coverage', counts[0] == 0 and all(a < b for a,b in zip(counts, counts[1:])), populations=counts)
    g.check('pattern half-progress has directional front', supports[2][:,:320].mean() > .5 and supports[2][:,960:].mean() < .01, left=float(supports[2][:,:320].mean()), right=float(supports[2][:,960:].mean()))
    contact_sheet(folder, [(name+'_neutral',name+'_active') for name in ('clash_pre','clash_vacuum','clash_impact','clash_recovery')], 'clash_contact_sheet.png')
    contact_sheet(folder, [(name+'_neutral',name+'_active') for name in ('vacuum_clash','kinetic_rush','distortion_only','lines_only')], 'isolated_contact_sheet.png')
    contact_sheet(folder, [('pattern_progress_%d_neutral'%i,'pattern_progress_%d_active'%i) for i in range(5)], 'pattern_contact_sheet.png')


def contact_sheet(folder, pairs, filename):
    sheet = Image.new('RGB', (1280, len(pairs)*390), '#141922')
    draw = ImageDraw.Draw(sheet)
    for row, pair in enumerate(pairs):
        for col, name in enumerate(pair):
            image = Image.open(folder/(name+'.png')).convert('RGB').resize((640,360))
            sheet.paste(image,(col*640,row*390+30))
            draw.text((col*640+8,row*390+8),name,fill='white')
    sheet.save(folder/filename)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('kind', choices=['scope', 'artist'])
    ap.add_argument('folder', type=Path)
    args = ap.parse_args()
    gates = Gates()
    {'scope': scope, 'artist': artist}[args.kind](args.folder, gates)
    raise SystemExit(gates.save(args.folder / 'pixel_gates.json'))
