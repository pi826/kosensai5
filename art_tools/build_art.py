"""Deterministic source extraction, articulated baking and atlas production.
Run with Python containing Pillow and numpy. No generator/network calls.
"""
from pathlib import Path
import hashlib
import json
import math
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'assets/art/source'
OUT = ROOT / 'assets/art'
QA = ROOT / 'builds/qa/art/stage1'
CELL = (96, 96)
STATES = {'idle': (4, 6), 'run': (8, 12), 'jump': (2, 8),
          'fall': (2, 6), 'land': (2, 12), 'dash': (3, 16),
          'glide': (3, 8), 'wall': (3, 8), 'hurt': (2, 12),
          'death': (6, 12), 'switch': (3, 12)}
ENEMY_STATES = {'idle': (4, 6), 'move': (8, 10), 'windup': (3, 10),
                'fire': (3, 16), 'hurt': (2, 12), 'death': (6, 12)}
manifest = {'version': 1, 'new_generations': 0, 'reused_sources':
            ['player.png', 'enemies.png', 'terrain.png', 'hud.png'], 'sheets': {}}


def clean(im):
    """Dilate bright subject seeds 2 source px, fill ENCLOSED holes only.
    Unlike scanline filling, gaps between limbs/wings stay transparent.
    """
    a = np.array(im.convert('RGB')).astype(np.int16)
    seed = (a.max(2) > 70) | ((a[:, :, 0] > 47) & (a[:, :, 0] > a[:, :, 2] * 1.35))
    mask = np.array(Image.fromarray((seed * 255).astype('uint8')).filter(ImageFilter.MaxFilter(5))) > 0
    h, w = mask.shape
    outside = np.zeros_like(mask)
    q = deque([(x, y) for y in range(h) for x in (0, w-1)] +
              [(x, y) for x in range(w) for y in (0, h-1)])
    while q:
        x, y = q.popleft()
        if not (0 <= x < w and 0 <= y < h) or mask[y, x] or outside[y, x]:
            continue
        outside[y, x] = True
        q.extend(((x-1, y), (x+1, y), (x, y-1), (x, y+1)))
    result = im.convert('RGBA')
    result.putalpha(Image.fromarray((~outside * 255).astype('uint8')))
    return result


def piece(im, polygon, name):
    mask = Image.new('L', im.size)
    ImageDraw.Draw(mask).polygon(polygon, fill=255)
    p = im.copy()
    p.putalpha(Image.fromarray(np.minimum(np.array(im.getchannel('A')), np.array(mask))))
    p.save(SRC / 'parts' / (name + '.png'))
    return p


def box_piece(im, box, name):
    x, y, r, b = box
    return piece(im, [(x,y),(r,y),(r,b),(x,b)], name)


def recolor(im):
    a = np.array(im)
    r, g, b = [a[:, :, i].astype(float) for i in range(3)]
    mask = (b > r * 1.3) & (g > r * 1.2) & (b > 65)
    v = np.maximum(g, b)
    # Preserve shading of cyan accents in the ONE mechanical body.
    a[:, :, 0][mask] = v[mask]
    a[:, :, 1][mask] = (v[mask] * .57).astype('uint8')
    a[:, :, 2][mask] = (v[mask] * .22).astype('uint8')
    return Image.fromarray(a)


def polarity_clean(im, color):
    """Remove opposing elemental hues; metal remains neutral and legible."""
    a=np.array(im); rgb=a[:,:,:3].astype(float)/255
    r,g,bl=rgb.transpose(2,0,1); hi=rgb.max(2); lo=rgb.min(2); diff=hi-lo
    safe=np.maximum(diff,1e-8); hue=np.zeros_like(hi)
    hue=np.where(hi==r,((g-bl)/safe)%6,hue)
    hue=np.where(hi==g,(bl-r)/safe+2,hue)
    hue=np.where(hi==bl,(r-g)/safe+4,hue)/6
    sat=diff/np.maximum(hi,1e-8)
    opposing=((hue>=.46)&(hue<=.72)) if color=='orange' else ((hue<=.14)|(hue>=.96))
    mask=opposing&(sat>=.28)&(hi>=.16)&(a[:,:,3]>0)
    if color=='orange':
        a[:,:,0][mask]=(hi[mask]*255).astype('uint8')
        a[:,:,1][mask]=((lo[mask]+diff[mask]*.45)*255).astype('uint8')
        a[:,:,2][mask]=(lo[mask]*255).astype('uint8')
    else:
        neutral=np.rint(rgb.mean(2)*255).astype('uint8')
        for k in range(3): a[:,:,k][mask]=neutral[mask]
    return Image.fromarray(a)


def transform(im, pivot, angle=0, offset=(0,0), scale=(1,1)):
    # Inverse affine about a fixed source joint. The source stays high resolution.
    t = math.radians(angle)
    c, s = math.cos(t), math.sin(t)
    px, py = pivot
    dx, dy = offset
    aa, bb, dd, ee = c/scale[0], s/scale[0], -s/scale[1], c/scale[1]
    cc = px-aa*(px+dx)-bb*(py+dy)
    ff = py-dd*(px+dx)-ee*(py+dy)
    return im.transform(im.size, Image.Transform.AFFINE, (aa,bb,cc,dd,ee,ff), Image.Resampling.NEAREST)


def native(im, scale, base, flip=False):
    s = im.resize((round(im.width*scale),round(im.height*scale)), Image.Resampling.BOX)
    s.putalpha(s.getchannel('A').point(lambda a: 255 if a >= 128 else 0))
    out = Image.new('RGBA', CELL)
    out.alpha_composite(s, (48-round(base[0]*scale),88-round(base[1]*scale)))
    return ImageOps.mirror(out) if flip else out


def align_feet(images, squash=1.0):
    bottom=max(im.getbbox()[3] if im.getbbox() else 0 for im in images)
    result=[]
    for im in images:
        fixed=Image.new('RGBA',CELL); fixed.alpha_composite(im,(0,88-bottom))
        if squash != 1.0:
            fixed=fixed.transform(CELL,Image.Transform.AFFINE,(1,0,0,0,1/squash,88-88/squash),Image.Resampling.NEAREST)
        result.append(fixed)
    return result


def palette_sheet(frames, rows, path):
    sheet = Image.new('RGBA', (8*96, rows*96))
    for row, images in enumerate(frames):
        for i, im in enumerate(images): sheet.alpha_composite(im, (i*96,row*96))
    return quantize(sheet, path)


def quantize(im, path):
    # Transparent pixels have a single canonical RGB. 63 RGB colors + transparent.
    a = np.array(im)
    a[a[:,:,3] == 0] = 0
    im = Image.fromarray(a)
    rgb = im.convert('RGB').quantize(63, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert('RGBA')
    rgb.putalpha(im.getchannel('A'))
    a = np.array(rgb); a[a[:,:,3] == 0] = 0
    result = Image.fromarray(a)
    path.parent.mkdir(parents=True, exist_ok=True)
    result.save(path, optimize=False, compress_level=9)
    return result


def record(kind, state, path, row, count, fps, pivot=(48,88)):
    manifest['sheets'][kind+'/'+state] = dict(path='res://'+path.relative_to(ROOT).as_posix().replace('blue','{color}').replace('orange','{color}'),
        row=row, frames=count, fps=fps, cell=list(CELL), pivot=list(pivot),
        loop=state not in ('land','hurt','death','switch','fire'))


def player_parts():
    im = clean(Image.open(SRC/'player.png').crop((16,195,163,440)))
    # Coordinates relative to this one canonical idle body.
    parts = {}
    polygons = {
        'head': [(28,56),(124,56),(124,122),(27,122)],
        'torso': [(42,120),(102,120),(113,174),(45,178)],
        'back_arm': [(15,112),(47,112),(48,145),(43,165),(43,197),(16,197)],
        'front_arm': [(101,128),(132,128),(133,199),(111,199),(105,173)],
        'back_leg': [(39,170),(78,170),(78,194),(65,213),(65,243),(25,243),(26,227),(40,204)],
        'front_leg': [(78,173),(112,173),(111,207),(130,231),(131,243),(88,243),(88,215),(76,199)],
        'crown': [(45,0),(117,0),(117,56),(45,56)],
        'core': [(84,130),(101,130),(110,150),(101,172),(84,170),(77,152)]}
    for name, poly in polygons.items(): parts[name] = piece(im,poly,'player-'+name)
    # Remove core from shared torso before replacing its shape.
    a = np.array(parts['torso']); a[np.array(parts['core'])[:,:,3] > 0] = 0
    parts['torso'] = Image.fromarray(a); parts['torso'].save(SRC/'parts/player-torso.png')
    orange = clean(Image.open(SRC/'player.png').crop((16,567,163,812)))
    crown = box_piece(orange,(45,0,117,57),'player-orange-crown')
    core = piece(orange,polygons['core'],'player-orange-core')
    # Reuse the firing arm from source, translated to the canonical shoulder.
    gun_raw = clean(Image.open(SRC/'player.png').crop((1210,313,1327,356)))
    gun = Image.new('RGBA',im.size)
    gun.alpha_composite(gun_raw,(91,131))
    gun.save(SRC/'parts/player-gun.png')
    return parts, crown, core, gun


def bake_player():
    parts, flame, flame_core, gun = player_parts()
    contacts = []
    for color in ('blue','orange'):
        p = {k: (recolor(v) if color == 'orange' else v) for k,v in parts.items()}
        if color == 'orange': p['crown'],p['core'] = flame,flame_core
        body_rows, arm_rows = [], []
        for row,(state,(count,fps)) in enumerate(STATES.items()):
            bodies, arms = [], []
            for i in range(count):
                phase = i/count*math.tau
                swing = math.sin(phase)
                bob = round(3*math.sin(phase)) if state in ('idle','glide','switch') else 0
                lean = 0; leg_a = leg_b = arm_angle = 0
                if state == 'run': leg_a,leg_b,arm_angle,bob = 32*swing,-32*swing,-22*swing,-abs(round(6*swing))
                if state == 'jump': leg_a,leg_b,arm_angle = -28+i*8,35-i*8,-25+i*8
                if state == 'fall': leg_a,leg_b,arm_angle = 18,-16,25+i*8
                if state == 'land': bob,leg_a,leg_b = 9-i*5,15,-15
                if state == 'dash': lean,leg_a,leg_b,arm_angle = 12+i*3,55+6*swing,30-6*swing,-45+5*swing
                if state == 'glide': leg_a,leg_b,arm_angle = 18,-18,-100+5*swing
                if state == 'wall': leg_a,leg_b,arm_angle,bob = -35+4*swing,60+6*swing,-90+6*swing,round(3*swing)
                if state == 'hurt': lean,leg_a,arm_angle = 9-i*5,-15,30
                body = Image.new('RGBA',p['head'].size)
                front = Image.new('RGBA',body.size)
                order = ('back_arm','back_leg','front_leg','torso','core','head','crown')
                for index,name in enumerate(order+('front_arm',)):
                    part = p[name]
                    pivot = (95,181) if name == 'front_leg' else ((58,181) if name == 'back_leg' else (102,132) if name == 'front_arm' else (40,125) if name == 'back_arm' else (78,177))
                    angle = leg_a if name == 'back_leg' else leg_b if name == 'front_leg' else arm_angle if name == 'front_arm' else -arm_angle if name == 'back_arm' else 0
                    offset = (0,bob)
                    if state in ('idle','switch') and name in ('back_leg','front_leg'): offset=(0,0)
                    if state == 'death':
                        angle += (index-3)*i*8
                        offset = ((index%3-1)*i*11, bob-i*7+(index%2)*i*9)
                    if state == 'switch' and name in ('crown','core'): offset = (0,bob-5*math.sin(i*math.pi/2))
                    target = front if name == 'front_arm' else body
                    target.alpha_composite(transform(part,pivot,angle+lean,offset))
                rendered=[native(body,.26,(78,243)),native(front,.26,(78,243))]
                if state in ('idle','run','land','hurt','switch'):
                    rendered=align_feet(rendered,.92+i*.08 if state=='land' else 1)
                bodies.append(rendered[0]); arms.append(rendered[1])
            body_rows.append(bodies); arm_rows.append(arms)
            record('player',state,OUT/'player'/f'{color}.png',row,count,fps)
            record('player_arm',state,OUT/'player'/f'{color}-arm.png',row,count,fps)
        for state,angle in [('shoot_front',0),('shoot_up',-60),('shoot_down',60)]:
            row = len(arm_rows)
            images = []
            for i in range(2):
                arm = recolor(gun) if color == 'orange' else gun
                images.append(native(transform(arm,(101,141),angle,(-i*5,0)),.26,(78,243)))
            arm_rows.append(images)
            record('player_arm',state,OUT/'player'/f'{color}-arm.png',row,2,16)
        body_sheet = palette_sheet(body_rows,len(body_rows),OUT/'player'/f'{color}.png')
        arm_sheet = palette_sheet(arm_rows,len(arm_rows),OUT/'player'/f'{color}-arm.png')
        # One shared palette for body AND replacement arm (one visible sprite).
        combined=Image.new('RGBA',(768,body_sheet.height+arm_sheet.height))
        combined.alpha_composite(body_sheet,(0,0)); combined.alpha_composite(arm_sheet,(0,body_sheet.height))
        combined=quantize(combined,OUT/'player'/f'{color}.png')
        body_sheet=combined.crop((0,0,768,body_sheet.height))
        arm_sheet=combined.crop((0,body_sheet.height,768,combined.height))
        body_sheet.save(OUT/'player'/f'{color}.png',compress_level=9)
        arm_sheet.save(OUT/'player'/f'{color}-arm.png',compress_level=9)
        for row,(state,(count,fps)) in enumerate(STATES.items()):
            frames=[]
            for i in range(count):
                rect=(i*96,row*96,(i+1)*96,(row+1)*96)
                f=body_sheet.crop(rect); f.alpha_composite(arm_sheet.crop(rect)); frames.append(f)
            preview_gif(frames,QA/(f'run-{color}.gif' if state=='run' else f'{state}-{color}.gif'),fps)
            contacts.append((color+' '+state,frames))
        for direction in ('front','up','down'):
            row=manifest['sheets']['player_arm/shoot_'+direction]['row']
            frames=[]
            for i in range(2):
                f=body_sheet.crop((0,0,96,96)); f.alpha_composite(arm_sheet.crop((i*96,row*96,(i+1)*96,(row+1)*96))); frames.append(f)
            preview_gif(frames,QA/f'shoot-{direction}-{color}.gif',16)
            contacts.append((color+' shoot '+direction,frames))
    contact(contacts,QA/'contact-player.png',4)


def preview_gif(frames,path,fps):
    panels=[]
    for im in frames:
        bg=Image.new('RGBA',CELL,'#233244'); bg.alpha_composite(im)
        panels.append(bg.convert('RGB').resize((384,384),Image.Resampling.NEAREST))
    panels[0].save(path,save_all=True,append_images=panels[1:],duration=round(1000/fps),loop=0,disposal=2,optimize=False)


def contact(rows,path,scale=2):
    im=Image.new('RGB',(8*96*scale, len(rows)*(96*scale+24)),'#233244')
    d=ImageDraw.Draw(im)
    for row,(label,frames) in enumerate(rows):
        y=row*(96*scale+24); d.text((8,y+3),label,fill='white')
        for i,f in enumerate(frames): im.paste(f.resize((96*scale,96*scale),Image.Resampling.NEAREST),(i*96*scale,y+24),f.resize((96*scale,96*scale),Image.Resampling.NEAREST))
    im.save(path)


def bake_enemies():
    rows_preview=[]
    for kind in ('walker','flyer'):
        source=Image.open(SRC/'enemies.png')
        x0=0 if kind=='walker' else 1024
        im=clean(source.crop((x0,160,x0+256,432)))
        if kind=='walker':
            specs={'body':(15,83,243,159),'back_leg':(155,155,251,265),
                   'front_leg':(72,155,164,265),'crown':(171,12,239,96),'core':(176,101,218,146)}
        else:
            specs={'body':(48,79,213,179),'back_leg':(90,177,162,265),
                   'front_leg':(90,177,162,265),'left_wing':(25,13,91,141),
                   'right_wing':(187,10,247,145),'core':(88,98,133,144)}
        p={name:box_piece(im,box,kind+'-'+name) for name,box in specs.items()}
        if kind=='flyer': p.pop('front_leg')
        # Body is shared between colors; the central core is a separate piece.
        a=np.array(p['body']); a[np.array(p['core'])[:,:,3]>0]=0
        if kind=='walker': a[np.array(p['crown'])[:,:,3]>0]=0
        p['body']=Image.fromarray(a); p['body'].save(SRC/'parts'/f'{kind}-body.png')
        orange=clean(source.crop((x0,595,x0+256,867)))
        replacements={}
        if kind=='walker': replacements['crown']=box_piece(orange,(171,9,239,97),kind+'-orange-crown')
        else:
            replacements['left_wing']=box_piece(orange,(25,9,91,141),kind+'-orange-left-wing')
            replacements['right_wing']=box_piece(orange,(187,9,247,145),kind+'-orange-right-wing')
        replacements['core']=box_piece(orange,specs['core'],kind+'-orange-core')
        for color in ('blue','orange'):
            parts={name:recolor(v) if color=='orange' else v for name,v in p.items()}
            if color=='orange': parts.update(replacements)
            frames_rows=[]
            for row,(state,(count,fps)) in enumerate(ENEMY_STATES.items()):
                frames=[]
                for i in range(count):
                    phase=i/count*math.tau; wave=math.sin(phase)
                    frame=Image.new('RGBA',im.size)
                    for k,(name,part) in enumerate(parts.items()):
                        angle=0; offset=(0,round(wave*3))
                        pivot=(128,148)
                        if name in ('back_leg','front_leg'):
                            if kind=='walker' and state=='idle': offset=(0,0)
                            pivot=(180,165) if name=='back_leg' else (120,165)
                            if kind=='walker' and state=='move': angle=(1 if name=='back_leg' else -1)*wave*24
                        if 'wing' in name:
                            pivot=(80,116) if name=='left_wing' else (196,116)
                            angle=(1 if name=='left_wing' else -1)*wave*14
                        if state=='windup': offset=(i*3, i*2)
                        if state=='fire': offset=(7-i*4,0)
                        if state=='hurt': angle=(-1 if i==0 else 1)*7
                        if state=='death': offset=((k%3-1)*i*13,-i*7+k%2*i*10); angle=(k-2)*i*12
                        frame.alpha_composite(transform(part,pivot,angle,offset))
                    # Canonical forward direction is right (walker raw faces left).
                    rendered=native(frame,.26,(128,263),kind=='walker')
                    if kind=='walker' and state!='death': rendered=align_feet([rendered])[0]
                    frames.append(rendered)
                frames_rows.append(frames)
                record(kind,state,OUT/'enemies'/f'{kind}-{color}.png',row,count,fps)
            frames_rows=[[polarity_clean(f,color) for f in frames] for frames in frames_rows]
            sheet=palette_sheet(frames_rows,len(frames_rows),OUT/'enemies'/f'{kind}-{color}.png')
            for row,(state,(count,fps)) in enumerate(ENEMY_STATES.items()):
                frames=[sheet.crop((i*96,row*96,(i+1)*96,(row+1)*96)) for i in range(count)]
                rows_preview.append((kind+' '+color+' '+state,frames))
                preview_gif(frames,QA/f'{kind}-{state}-{color}.gif',fps)
    contact(rows_preview,QA/'enemies.png')


def bake_hud():
    im=Image.open(SRC/'hud.png')
    out=Image.new('RGBA',(64,32))
    for i,rect in enumerate(((1272,220,1520,488),(1272,559,1520,829))):
        s=clean(im.crop(rect)); s=s.crop(s.getbbox()); s.thumbnail((28,30),Image.Resampling.BOX)
        s.putalpha(s.getchannel('A').point(lambda a:255 if a>=128 else 0))
        out.alpha_composite(s,(i*32+(32-s.width)//2,32-s.height))
    quantize(out,OUT/'hud/colors.png')


def bake_terrain():
    raw=Image.open(SRC/'terrain.png').convert('RGB')
    # Large texture field: adjacent native patches preserve the source's scale.
    field=raw.crop((322,16,607,309)).resize((96,96),Image.Resampling.BOX)
    # Keep the source masonry, wet joints and moss: a narrow grayscale ramp
    # erased their relief. Contrast preserves both the teal stone and green moss.
    common_field=ImageOps.colorize(ImageOps.grayscale(field),'#172e32','#4d6860').convert('RGBA')
    field=ImageEnhance.Brightness(ImageEnhance.Contrast(field).enhance(1.3)).enhance(.9).convert('RGBA')
    surface=raw.crop((18,48,302,135)).resize((96,20),Image.Resampling.BOX).convert('RGBA')
    platform=raw.crop((933,38,1214,98)).resize((96,16),Image.Resampling.BOX).convert('RGBA')
    # Quiet shared edge pixels avoid repeating miniature moss patterns.
    common=np.array(common_field.resize((32,32),Image.Resampling.BOX)).astype(float)
    # Shared periodic edge texture, not a straight grid line.
    common[:,0]=(common[:,0]+common[:,-1])/2; common[:,-1]=common[:,0]
    common[0,:]=(common[0,:]+common[-1,:])/2; common[-1,:]=common[0,:]
    atlas=Image.new('RGBA',(256*32,4*32))
    for variant in range(4):
        for mask in range(256):
            tile=Image.new('RGBA',(32,32))
            # Native 3x3 source patch plus four large-field offsets, not repeated tiny noise.
            ox=(variant*19)%64; oy=(variant*29)%64
            tile.paste(field.crop((ox,oy,ox+32,oy+32)))
            a=np.array(tile).astype(float)
            yy,xx=np.mgrid[:32,:32]
            edge=np.minimum.reduce([xx,31-xx,yy,31-yy])
            mix=np.clip(edge/2,0,1)[:,:,None]
            tile=Image.fromarray((a*mix+common*(1-mix)).astype('uint8'))
            # Interior just beneath a surface catches light. Filled interiors
            # retain identical shared edges, independent of the variant.
            if mask&1 and mask&64 and mask&4 and mask&16 and mask != 255:
                a=np.array(tile).astype(float)
                light=(np.sin(np.pi*xx/31)*np.sin(np.pi*yy/31)*.17)[:,:,None]
                a[:,:,:3]=np.minimum(255,a[:,:,:3]*(1+light))
                tile=Image.fromarray(a.astype('uint8'))
            if not mask&1:
                top=surface.crop((variant*21%64,0,variant*21%64+32,9)); tile.paste(top,(0,0))
            # Exposed sides have dark broken stone and irregular moss drips.
            # Do not draw straight bright outlines or diagonal-neighbor Ls.
            d=ImageDraw.Draw(tile)
            if not mask&16: d.line((0,31,31,31),fill='#10262b')
            for side,bit in ((0,64),(31,4)):
                if mask&bit: continue
                for y in range(32):
                    width=1+int((y+side*3)%11 in (0,1,4))
                    x0=side if side==0 else side-width+1
                    d.line((x0,y,x0+width-1,y),fill='#142a2e')
                if not mask&1:
                    for y in range(2,8+(variant*3+side)%9):
                        x=side+(1 if side==0 else -1)*(1+(y+variant)%3)
                        d.point((x,y),fill='#668b6b' if y%3 else '#344e3e')
            atlas.alpha_composite(tile,(mask*32,variant*32))
    quantize(atlas,OUT/'terrain/waterway.png')
    special=Image.new('RGBA',(128,32))
    for i in range(3): special.paste(platform.crop((i*32,0,i*32+32,16)),(i*32,0))
    block=field.crop((16,16,48,48)); d=ImageDraw.Draw(block)
    d.rectangle((1,1,30,30),outline='#adad86',width=2)
    d.line((11,4,19,12,14,20,24,28),fill='#0b2028',width=3)
    special.paste(block,(96,0)); quantize(special,OUT/'terrain/special.png')
    # Demonstration is separate from the full atlas (8192px wide).
    scene=Image.new('RGBA',(1280,720),'#101e22')
    atlas=Image.open(OUT/'terrain/waterway.png')
    for y in range(416,720,32):
        for x in range(0,1280,32):
            v=tile_hash(x//32,y//32,37)%4; m=253 if y==416 else 255
            if y==416: m=124 # N missing, E/S/W and lower diagonals.
            scene.paste(atlas.crop((m*32,v*32,m*32+32,v*32+32)),(x,y))
    sp=Image.open(OUT/'terrain/special.png')
    for x in range(192,512,32): scene.alpha_composite(sp.crop((0,0,32,16)),(x,280))
    scene.save(QA/'tiles.png')
    atlas.resize((8192,128),Image.Resampling.NEAREST).save(QA/'tile-atlas.png')


def tile_hash(x,y,seed):
    h=((x*73856093)^(y*19349663)^(seed*83492791)) & 0x7fffffff
    h ^= h >> 15
    h = (h * 1103515245) & 0x7fffffff
    h ^= h >> 13
    return h


def imports():
    for path in sorted(OUT.rglob('*.png')):
        if SRC in path.parents: continue
        # Editor import can fill cache paths; keep project-level nearest/lossless settings.
        dest=Path(str(path)+'.import')
        if not dest.exists():
            res='res://'+path.relative_to(ROOT).as_posix()
            digest=hashlib.md5(res.encode()).hexdigest()
            dest.write_text(f'[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\npath="res://.godot/imported/{path.name}-{digest}.ctex"\n\n[deps]\n\nsource_file="{res}"\ndest_files=["res://.godot/imported/{path.name}-{digest}.ctex"]\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=false\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\n',encoding='utf-8')


def main():
    (SRC/'parts').mkdir(parents=True,exist_ok=True); QA.mkdir(parents=True,exist_ok=True)
    bake_player(); bake_enemies(); bake_hud(); bake_terrain()
    import build_stage2
    # When invoked as a script this module is named __main__; pass this actual
    # module so the stage-2 records join the same manifest.
    import sys
    build_stage2.b = sys.modules[__name__]
    build_stage2.main()
    import build_stage3
    build_stage3.b = sys.modules[__name__]
    build_stage3.main()
    imports()
    manifest['hashes']={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in sorted(OUT.rglob('*.png')) if SRC not in p.parents}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print(json.dumps({'outputs':len(manifest['hashes']),'entries':len(manifest['sheets']),'new_generations':manifest['new_generations']}))


if __name__=='__main__': main()
