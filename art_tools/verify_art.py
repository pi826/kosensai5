"""Verify determinism, binary cutouts, palettes, sheets and tile continuity."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets/art'
QA=ROOT/'builds/qa/art/stage3'
checks=0
failures=[]


def check(ok,message):
    global checks
    checks+=1
    if not ok: failures.append(message)


def hashes():
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(ART.rglob('*.png'))}


def main():
    before=hashes()
    subprocess.run([sys.executable,'-B',str(ROOT/'art_tools/build_art.py')],cwd=ROOT,check=True)
    after=hashes()
    check(before==after,'all source parts and output PNG bytes match on rebuilding')
    data=json.loads((ART/'manifest.json').read_text(encoding='utf-8'))
    for path,expected in data['hashes'].items():
        check(hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==expected,'manifest hash '+path)
        a=np.array(Image.open(ROOT/path).convert('RGBA'))
        check(bool(np.isin(a[:,:,3],[0,255]).all()),'binary alpha '+path)
        check(Image.open(ROOT/path).convert('RGBA').getcolors(64) is not None,'at most 64 colors '+path)
    for color in ('blue','orange'):
        colors=set()
        for name in (color,color+'-arm'):
            im=Image.open(ART/'player'/f'{name}.png').convert('RGBA')
            colors.update(color for count,color in im.getcolors(65))
        check(len(colors)<=64,'player body and replacement arm share <=64 colors '+color)
    for key,info in data['sheets'].items():
        for color in ('blue','orange'):
            path=ROOT/info['path'].replace('res://','').replace('{color}',color)
            sheet=Image.open(path).convert('RGBA')
            w,h=info['cell']
            check(sheet.width==8*w and sheet.height>=(info['row']+1)*h,'dimensions '+key+' '+color)
            distinct=set()
            for i in range(info['frames']):
                frame=sheet.crop((i*w,info['row']*h,(i+1)*w,(info['row']+1)*h))
                a=np.array(frame)
                distinct.add(frame.tobytes())
                kind,state=key.split('/')
                if state not in ('windup_switch','switch') and (kind in ('turret','walker','flyer','laser','breaker','builder','shifter','enhancer','guardian','final','secret','bomb') or kind.startswith('bullet_')) and '{color}' in info['path']:
                    from build_art import polarity_clean
                    # Quantization can change a hue by <1/255; use the same
                    # explicit RGB/HSV bounds on the FINAL PNG, not source parts.
                    check(np.array_equal(np.array(polarity_clean(frame,color)),a),'no opposite elemental hue '+key+f' {color} {i}')
                check(bool(a[:,:,3].any()),'nonempty '+key+f' {color} {i}')
                if key.split('/')[0] not in ('wall','laser'):
                    check(not (a[0,:,3].any() or a[-1,:,3].any() or a[:,0,3].any() or a[:,-1,3].any()),'transparent cell perimeter '+key+f' {color} {i}')
                # Detect a surviving source backdrop: dark flat rectangles enclosing
                # the silhouette rather than merely the transparent padded sheet.
                bbox=frame.getbbox()
                if bbox and key.split('/')[0] not in ('wall','laser'):
                    crop=np.array(frame.crop(bbox))[:,:,3]
                    check(not(crop[0,:].all() and crop[-1,:].all() and crop[:,0].all() and crop[:,-1].all()),'no opaque rectangular cutout '+key+f' {color} {i}')
                    if key in ('player/idle','player/run','player/land','walker/idle','walker/move'):
                        check(bbox[3]==88,'feet on collision bottom '+key+f' {color} {i}')
            if info['frames']>1 and key!='wall/idle': check(len(distinct)>1,'animation changes across frames '+key+' '+color)
    # Connected filled tiles share exactly the same edge pixels for ALL variants.
    for name in ('waterway','crystal','ash'):
        atlas=np.array(Image.open(ART/'terrain'/(name+'.png')))
        check(atlas.shape[:2]==(128,8192),'256 masks x 4 variants '+name)
        tiles=[atlas[v*32:(v+1)*32,255*32:256*32] for v in range(4)]
        for a in tiles:
            for b in tiles:
                check(np.array_equal(a[:,-1],b[:,0]),'filled horizontal texture seam '+name)
                check(np.array_equal(a[-1,:],b[0,:]),'filled vertical texture seam '+name)
    for region in range(3):
        for layer in range(2):
            a=np.array(Image.open(ART/'backdrops'/f'{region}-{layer}.png'))
            check(np.array_equal(a[:,0],a[:,-1]),'background horizontal seam')
            check(np.array_equal(a[0],a[-1]),'background vertical seam')
            check(a[:,:,:3].max()<135,'background darker than foreground highlights')
    from art_components import components
    audit={}
    for key,info in data['sheets'].items():
        if key.split('/')[0] not in ('turret','walker','flyer','laser','breaker','builder','shifter','enhancer','guardian','final','secret','bomb','bullet_player','bullet_player_homing','bullet_enemy','bullet_enemy_homing'): continue
        if key.split('/')[1] not in ('idle','flight'): continue
        audit[key]={}
        for color in ('blue','orange'):
            path=ROOT/info['path'].replace('res://','').replace('{color}',color)
            w,h=info['cell']; image=Image.open(path).convert('RGBA'); audit[key][color]=[]
            for i in range(info['frames']):
                frame=image.crop((i*w,info['row']*h,(i+1)*w,(info['row']+1)*h))
                groups=components(frame)
                audit[key][color].append([{'pixels':len(g),'bounds':[int(min(x for x,y in g)),int(min(y for x,y in g)),int(max(x for x,y in g)),int(max(y for x,y in g))]} for g in groups])
                if key=='bullet_enemy_homing/flight': check(len(groups)==1,'guided enemy shot has no detached debris '+color+' '+str(i))
    (QA/'components.json').write_text(json.dumps(audit,indent=2)+'\n',encoding='utf-8')
    from build_art import tile_hash
    periods={}
    for divisor in (3,4):
        for dx,dy in ((4,0),(0,4),(4,4)):
            rate=sum(tile_hash(x,y,37)%divisor==tile_hash(x+dx,y+dy,37)%divisor for y in range(16) for x in range(16))/256
            periods[f'{divisor}:{dx},{dy}']=rate
            check(abs(rate-1/divisor)<.12,'no four-cell period '+str((divisor,dx,dy,rate)))
    report={'checks':checks,'failures':failures,'deterministic_png':before==after,
            'new_generations_this_stage':1,'reused_generations':5,'period_match_rates':periods,'hashes':data['hashes']}
    (QA/'verification.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'checks':checks,'failures':failures}))
    return bool(failures)


if __name__=='__main__': sys.exit(main())
