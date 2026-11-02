"""Stage 2: saved AI originals -> masked parts -> deterministic articulated sheets.
No network, generators or absolute Python paths. Invoked by build_art.py.
"""
import math
import json
import hashlib
import numpy as np
from PIL import Image, ImageOps, ImageFilter, ImageDraw
import build_art as b

QA = b.ROOT/'builds/qa/art/stage2'
ENEMIES = ('turret', 'laser', 'breaker', 'builder', 'shifter', 'enhancer')
BOSSES = ('guardian', 'final', 'secret')
STATES = dict(b.ENEMY_STATES, windup_switch=(4, 10), switch=(4, 12))
BOSS_STATES = dict(STATES, windup_special=(4, 10), fire_special=(4, 16))
BOSS_STATES['death'] = (8, 8)


def cut_new(box):
    im = Image.open(b.SRC/'stage2.png').convert('RGBA').crop(box)
    a = np.array(im)
    # Discard transparent bloom. This source has real alpha, no chroma key.
    a[:, :, 3] = np.where(a[:, :, 3] >= 210, 255, 0)
    im = Image.fromarray(a)
    return im.crop(im.getbbox())


def fitted(im, size):
    im = im.copy()
    im.thumbnail(size, Image.Resampling.BOX)
    im.putalpha(im.getchannel('A').point(lambda a: 255 if a >= 128 else 0))
    return im


def source_actor(kind):
    if kind in BOSSES:
        box = {'guardian':(0,0,390,525), 'final':(390,0,731,525),
               'secret':(733,0,1143,535)}[kind]
        im = cut_new(box)
    elif kind == 'turret':
        im=b.clean(Image.open(b.SRC/'enemies.png').crop((1282,285,1527,438)))
        from art_components import largest
        im=largest(im)
        im=im.crop(im.getbbox())
    elif kind == 'enhancer':
        im = cut_new((1150,0,1448,535))
    else:
        x0, x1 = {'laser':(284,518), 'breaker':(522,773),
                  'builder':(779,1029), 'shifter':(1300,1493)}[kind]
        bottom = 267 if kind == 'shifter' else 435
        im = b.clean(Image.open(b.SRC/'enemies.png').crop((x0,105 if kind=='shifter' else 155,x1,bottom)))
        im = im.crop(im.getbbox())
    # Work on a padded high-resolution canonical canvas. Disjoint masks leave
    # no duplicate body pixels underneath moving arms, core or crown.
    im = fitted(im, (360,410))
    canvas = Image.new('RGBA',(512,512))
    x=(512-im.width)//2; y=460-im.height
    canvas.alpha_composite(im,(x,y))
    crown_end = y+int(im.height*.23)
    core_box=(256-int(im.width*.14), y+int(im.height*.36),
              256+int(im.width*.14), y+int(im.height*.63))
    labels = np.zeros((512,512), dtype=np.uint8)
    labels[y:crown_end,:]=1
    labels[crown_end:460,:x+int(im.width*.28)]=2
    labels[crown_end:460,x+int(im.width*.72):]=3
    labels[y+int(im.height*.75):460,x+int(im.width*.28):x+int(im.width*.72)]=4
    labels[core_box[1]:core_box[3],core_box[0]:core_box[2]]=5
    parts={}
    for i,name in enumerate(('body','crown','left_arm','right_arm','feet','core')):
        a=np.array(canvas); a[labels!=i]=0
        p=Image.fromarray(a); p.save(b.SRC/'parts'/f'{kind}-{name}.png')
        parts[name]=p
    # Orange crown/core use the existing FLAME source, never another body.
    flame=b.clean(Image.open(b.SRC/'enemies.png').crop((172,595,244,698)))
    flame=flame.crop(flame.getbbox())
    replacements={}
    for name,box in [('crown',(256-int(im.width*.25),y,256+int(im.width*.25),crown_end)),('core',core_box)]:
        layer=Image.new('RGBA',canvas.size)
        f=fitted(flame,(box[2]-box[0],box[3]-box[1]))
        layer.alpha_composite(f,((box[0]+box[2]-f.width)//2,box[3]-f.height))
        layer.save(b.SRC/'parts'/f'{kind}-orange-{name}.png')
        replacements[name]=layer
    return parts,replacements,im.height


def save_rows(kind, color, rows, states, cell, pivot, category):
    path=b.OUT/category/f'{kind}-{color}.png'
    sheet=Image.new('RGBA',(cell[0]*8,cell[1]*len(rows)))
    for y,frames in enumerate(rows):
        state=list(states)[y]
        for x,im in enumerate(frames):
            if state not in ('windup_switch','switch') and (kind in ENEMIES+BOSSES or category=='projectiles'):
                im=b.polarity_clean(im,color)
            sheet.alpha_composite(im,(x*cell[0],y*cell[1]))
    sheet=b.quantize(sheet,path)
    if kind in ENEMIES+BOSSES or category=='projectiles':
        # A palette shared with switch rows contains BOTH polarities. MEDIANCUT
        # may choose an opposite-color entry for a neutral normal-state pixel.
        # Remap such pixels to the closest allowed entry of THAT SAME palette.
        a=np.array(sheet); palette=np.array(sorted(value for count,value in sheet.getcolors(64)),dtype=np.uint8)
        probe=Image.fromarray(palette.reshape(1,-1,4))
        permitted=np.all(np.array(b.polarity_clean(probe,color)).reshape(-1,4)==palette,axis=1)
        allowed=palette[permitted & (palette[:,3]>0)]
        for y,state in enumerate(states):
            if state in ('windup_switch','switch'): continue
            row=a[y*cell[1]:(y+1)*cell[1]]
            for value in palette[~permitted]:
                closest=allowed[np.argmin(((allowed[:,:3].astype(float)-value[:3])**2).sum(1))]
                row[np.all(row==value,axis=2)]=closest
        sheet=Image.fromarray(a); sheet.save(path,optimize=False,compress_level=9)
    result=[]
    for row,(state,(count,fps)) in enumerate(states.items()):
        relative=path.relative_to(b.ROOT).as_posix()
        if kind not in ('wall','boss_arrow'): relative=relative.replace(color,'{color}')
        b.manifest['sheets'][kind+'/'+state]=dict(path='res://'+relative,
            cell=list(cell),pivot=list(pivot),row=row,frames=count,fps=fps,
            loop=state in ('idle','move','warning','beam'))
        frames=[sheet.crop((i*cell[0],row*cell[1],(i+1)*cell[0],(row+1)*cell[1])) for i in range(count)]
        result.append((kind+' '+color+' '+state,frames))
        if kind in ENEMIES+BOSSES or state in ('flight','bomb','defeat','absorb','switch'):
            preview(frames,QA/f'{kind}-{state}-{color}.gif',fps)
    return result


def preview(frames,path,fps):
    panels=[]
    for im in frames:
        bg=Image.new('RGBA',im.size,'#1c2935'); bg.alpha_composite(im)
        factor=2 if im.width<=128 else 1
        panels.append(bg.convert('RGB').resize((im.width*factor,im.height*factor),Image.Resampling.NEAREST))
    panels[0].save(path,save_all=True,append_images=panels[1:],duration=round(1000/fps),loop=0,disposal=2,optimize=False)


def contact(rows,path,backgrounds=('#172435',),cell=128):
    width=cell*8
    height=len(rows)*(cell+24)*len(backgrounds)
    im=Image.new('RGB',(width,height))
    d=ImageDraw.Draw(im)
    for k,bg in enumerate(backgrounds):
        d.rectangle((0,k*len(rows)*(cell+24),width,(k+1)*len(rows)*(cell+24)),fill=bg)
        for j,(label,frames) in enumerate(rows):
            y=(k*len(rows)+j)*(cell+24)
            d.text((5,y+3),label,fill='white' if k==0 else '#172435')
            for i,f in enumerate(frames):
                p=f.resize((cell,cell),Image.Resampling.NEAREST); im.paste(p,(i*cell,y+24),p)
    im.save(path)


def actors():
    enemies=[]; bosses=[]
    for kind in ENEMIES+BOSSES:
        parts,orange,source_height=source_actor(kind)
        is_boss=kind in BOSSES
        cell=(320,320) if is_boss else (96,96)
        pivot=(160,275) if is_boss else (48,88)
        height={'guardian':151,'final':182,'secret':214,'turret':39}.get(kind,65)
        scale=height/source_height
        states=BOSS_STATES if is_boss else STATES
        for color in ('blue','orange'):
            base={k:b.recolor(v) if color=='orange' else v for k,v in parts.items()}
            if color=='orange': base.update(orange)
            other={k:v if color=='orange' else b.recolor(v) for k,v in parts.items()}
            if color=='blue': other.update(orange)
            rows=[]
            for state,(count,fps) in states.items():
                frames=[]
                for i in range(count):
                    phase=i/count*math.tau; wave=math.sin(phase); progress=i/max(1,count-1)
                    frame=Image.new('RGBA',(512,512))
                    for k,(name,part) in enumerate(base.items()):
                        offset=(0,round(3*wave)); angle=0
                        joint=(256,300)
                        if name=='feet':
                            offset=(0,0)
                            if state=='move': angle=wave*5; offset=(round(wave*8),0)
                        if name in ('left_arm','right_arm'):
                            side=-1 if name=='left_arm' else 1
                            joint=(256+side*90,270); angle=side*wave*5
                            if state.startswith('windup'): angle=side*(10+progress*22)
                            if state.startswith('fire'): angle=-side*(10-progress*8); offset=(-8+progress*8,0)
                        if name=='core':
                            angle=wave*9 if kind=='shifter' else wave*3
                        if state in ('switch','windup_switch') and name in ('core','crown'):
                            if state=='switch' or name=='crown' or i>=count//2: part=other[name]
                            angle=progress*40-20; offset=(0,-round(12*math.sin(progress*math.pi)))
                        if state=='hurt': offset=(10 if i==0 else -4,0)
                        if state=='death':
                            spread=78 if is_boss else 26
                            offset=((k%3-1)*progress*spread,-progress*20+(k%2)*progress*30)
                            angle=(k-2)*progress*(65 if is_boss else 20)
                            if kind=='shifter': angle=0
                        frame.alpha_composite(b.transform(part,joint,angle,offset))
                    if kind=='enhancer':
                        # Pulsing reactor uses physical size, no fractional alpha.
                        core=base['core']; pulse=1+0.08*math.sin(phase)
                        frame.alpha_composite(b.transform(core,(256,300),0,(0,0),(pulse,pulse)))
                    small=frame.resize((round(512*scale),round(512*scale)),Image.Resampling.BOX)
                    small.putalpha(small.getchannel('A').point(lambda a:255 if a>=128 else 0))
                    out=Image.new('RGBA',cell)
                    out.alpha_composite(small,(pivot[0]-round(256*scale),pivot[1]-round(460*scale)))
                    # Source enemies face left; boss and lantern art face forward.
                    if kind not in BOSSES+('enhancer','shifter'): out=ImageOps.mirror(out)
                    frames.append(out)
                rows.append(frames)
            result=save_rows(kind,color,rows,states,cell,pivot,'bosses' if is_boss else 'enemies')
            (bosses if is_boss else enemies).extend(result)
    contact(enemies,QA/'contact-enemies.png')
    contact(bosses,QA/'contact-bosses.png',cell=320)


def small_art():
    raw=[cut_new(box) for box in ((0,540,393,775),(400,540,752,775),(757,540,1115,775),(1120,535,1448,775))]
    from art_components import largest
    # The projectile crops may include a neighbor's detached crystal. Casing
    # and fins belong to the single connected canonical shot, never that debris.
    raw=[largest(im) for im in raw]
    flame=cut_new((400,780,753,1086))
    shard=cut_new((0,780,365,1086))
    bomb=cut_new((776,780,1020,1086))
    arrow=cut_new((1120,805,1448,1070))
    all_projectiles=[]
    for faction in ('player','enemy'):
        for homing in (False,True):
            kind='bullet_'+faction+('_homing' if homing else '')
            index=(0 if faction=='player' else 2)+int(homing)
            for color in ('blue','orange'):
                frames=[]
                for i in range(4):
                    out=Image.new('RGBA',(48,48))
                    source=raw[index] if color=='blue' else flame
                    size=(27 if homing else 22,19 if homing else 13)
                    p=fitted(source,(size[0]+i%2*2,size[1]+i%2*2))
                    # Retain source casing/fins for the ORANGE player missile;
                    # fire tongue replaces its crystalline nose, not just hue.
                    if color=='orange' and (homing or faction=='player'):
                        casing=fitted(b.recolor(raw[index]),size)
                        out.alpha_composite(casing,((48-casing.width)//2,(48-casing.height)//2))
                        p=fitted(flame,(13+i%2*2,13 if homing else 9))
                    at=(24-p.width//2,24-p.height//2)
                    if color=='orange' and (homing or faction=='player'): at=(25,24-p.height//2)
                    # A 1px dark silhouette keeps ice/fire readable on light backdrops.
                    mask=Image.new('L',out.size); mask.paste(p.getchannel('A'),at)
                    border=Image.new('RGBA',out.size,'#091326'); border.putalpha(mask.filter(ImageFilter.MaxFilter(3)))
                    out=Image.alpha_composite(border,out); out.alpha_composite(p,at)
                    # No detached shard: this used to add BLUE debris to orange shots.
                    frames.append(out)
                result=save_rows(kind,color,[frames],{'flight':(4,16)},(48,48),(24,24),'projectiles')
                all_projectiles.extend(result)
    contact(all_projectiles,QA/'projectiles.png',('#172435','#dbdecf'))
    for color in ('blue','orange'):
        source=shard if color=='blue' else flame
        rows=[]; states={k:(6,6/.45) for k in ('defeat','hit','absorb','switch','land','jump','bomb','dash')}
        for state,(count,fps) in states.items():
            frames=[]
            for i in range(count):
                out=Image.new('RGBA',(256,256)); t=i/(count-1)
                for j in range(8):
                    angle=j*math.tau/8
                    radius=(8+(1-t if state=='absorb' else t)*46)
                    if state=='bomb': radius=12+t*90
                    p=fitted(source,(max(3,round(23*(1-t*.7))),)*2).rotate(j*45+i*11,resample=Image.Resampling.NEAREST,expand=True)
                    dx=math.cos(angle)*radius; dy=math.sin(angle)*radius
                    if state in ('jump','land','dash'): dy=-abs(dy)*.24; dx*=1.2
                    out.alpha_composite(p,(128+round(dx)-p.width//2,128+round(dy)-p.height//2))
                frames.append(out)
            rows.append(frames)
        save_rows('burst',color,rows,states,(256,256),(128,128),'effects')
        frames=[]
        for i in range(4):
            out=Image.new('RGBA',(48,48)); p=fitted(bomb if color=='blue' else b.recolor(bomb),(24+i%2*3,30+i%2*3))
            out.alpha_composite(p,((48-p.width)//2,(48-p.height)//2)); frames.append(out)
        save_rows('bomb',color,[frames],{'flight':(4,12)},(48,48),(24,24),'projectiles')
        # Texture strip sampled with scrolling UVs by the curved beam renderer.
        rows=[]
        for state in ('warning','beam'):
            frames=[]
            for i in range(4):
                out=Image.new('RGBA',(64,24)); p=fitted(source,(20,5 if state=='warning' else 15))
                for x in range(-32,96,16): out.alpha_composite(p,(x+i*4,12-p.height//2))
                frames.append(out)
            rows.append(frames)
        save_rows('laser',color,rows,{'warning':(4,12),'beam':(4,20)},(64,24),(0,12),'projectiles')
    p=fitted(arrow,(32,20)); frame=Image.new('RGBA',(48,48)); frame.alpha_composite(p,((48-p.width)//2,(48-p.height)//2))
    save_rows('boss_arrow','blue',[[frame]],{'idle':(1,1)},(48,48),(24,24),'hud')
    # Source builder's held block, neutral sand color retains original wall meaning.
    block=b.clean(Image.open(b.SRC/'enemies.png').crop((800,273,845,314)))
    block=ImageOps.colorize(ImageOps.grayscale(block),'#30251b','#dbbd84').convert('RGBA')
    tile=block.resize((32,32),Image.Resampling.BOX)
    rows=[]
    for state in ('idle','appear','vanish'):
        frames=[]
        for i in range(4):
            out=Image.new('RGBA',(32,32)); height=32 if state=='idle' else (8+i*8 if state=='appear' else 32-i*8)
            out.alpha_composite(tile.resize((32,height),Image.Resampling.NEAREST),(0,32-height)); frames.append(out)
        rows.append(frames)
    save_rows('wall','blue',rows,{'idle':(4,12),'appear':(4,20),'vanish':(4,20)},(32,32),(0,0),'terrain')


def main():
    QA.mkdir(parents=True,exist_ok=True)
    actors(); small_art()
    for name in ('tiles.png','tile-atlas.png'):
        Image.open(b.QA/name).save(QA/name)
    b.manifest['version']=2
    b.manifest['new_generations']=1
    b.manifest['new_sources']=['stage2.png']
    (QA/'generation.json').write_text(json.dumps({'new_generations':1,'prompt':'assets/art/source/stage2-prompt.txt','source':'assets/art/source/stage2.png'},indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    raise SystemExit('Run build_art.py, which builds both stages and one manifest.')
