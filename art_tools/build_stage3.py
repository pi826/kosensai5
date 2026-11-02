"""Stage 3: saved AI atlas, deterministic cutouts, animation, tiles and UI.
No generator/network calls. Invoked by build_art.py; paths are project relative.
"""
import math
import json
import numpy as np
from PIL import Image, ImageDraw, ImageOps, ImageEnhance
import build_art as b

QA = b.ROOT/'builds/qa/art/stage3'
BOXES = {
    'heart':(50,45,234,208), 'crystal':(302,20,427,217),
    'key':(502,22,640,222), 'potion':(723,9,880,222),
    'chest':(963,32,1220,222), 'chest_open':(1250,2,1510,226),
    'rapid':(25,260,249,404), 'triple':(264,247,499,412),
    'pierce':(509,268,773,408), 'shell':(796,238,1030,426),
    'cushion':(1041,240,1288,426), 'invincible':(1300,231,1510,428),
    'homing':(21,454,177,701), 'absorb':(226,460,368,704),
    'boots':(396,468,621,693), 'merchant':(636,392,894,724),
    'target':(956,431,1164,718), 'panel':(1202,425,1514,711),
}

def cut(name):
    im=Image.open(b.SRC/'stage3.png').convert('RGBA').crop(BOXES[name])
    a=np.array(im); a[:,:,3]=np.where(a[:,:,3]>=210,255,0); a[a[:,:,3]==0]=0
    im=Image.fromarray(a); return im.crop(im.getbbox())

def fit(im,size):
    im=im.copy(); im.thumbnail(size,Image.Resampling.BOX)
    im.putalpha(im.getchannel('A').point(lambda a:255 if a>=128 else 0))
    return im

def sheet(kind, states, cell=(48,48), pivot=(24,24), category='items'):
    out=Image.new('RGBA',(8*cell[0],len(states)*cell[1])); previews=[]
    path=b.OUT/category/(kind+'.png')
    for row,(state,frames) in enumerate(states.items()):
        for i,im in enumerate(frames): out.alpha_composite(im,(i*cell[0],row*cell[1]))
        b.manifest['sheets'][kind+'/'+state]=dict(path='res://'+path.relative_to(b.ROOT).as_posix(),
            row=row,frames=len(frames),fps=8,cell=list(cell),pivot=list(pivot),loop=state not in ('opening','open'))
    out=b.quantize(out,path)
    for row,(state,frames) in enumerate(states.items()):
        frames=[out.crop((i*cell[0],row*cell[1],(i+1)*cell[0],(row+1)*cell[1])) for i in range(len(frames))]
        previews.append((kind+'/'+state,frames))
        if len(frames)>1:
            from build_stage2 import preview
            preview(frames,QA/(kind+'-'+state+'.gif'),8)
    return previews

def items():
    previews=[]
    for name in BOXES:
        if name in ('panel','chest_open'): continue
        source=cut(name); source.save(b.SRC/'parts'/('stage3-'+name+'.png'))
        large=name in ('merchant','target'); cell=(96,96) if large else (48,48)
        pivot=(48,88) if large else (24,24)
        p=fit(source,(55,76) if large else ((40,34) if name=='chest' else (31,31)))
        frames=[]
        for i in range(4):
            out=Image.new('RGBA',cell); dy=(0,-1,-2,-1)[i]
            if large:
                # Stable feet; upper cloak/head breathe as a separate source part.
                split=p.height*2//3
                out.alpha_composite(p.crop((0,split,p.width,p.height)),((96-p.width)//2,88-p.height+split))
                out.alpha_composite(p.crop((0,0,p.width,split)),((96-p.width)//2,88-p.height+(0,-1,0,1)[i]))
            else:
                out.alpha_composite(p,((48-p.width)//2,(48-p.height)//2+dy))
                if i in (1,3):
                    d=ImageDraw.Draw(out); x,y=(35,9) if i==1 else (10,34)
                    d.line((x-2,y,x+2,y),fill='#fff1c8'); d.line((x,y-2,x,y+2),fill='#fff1c8')
            frames.append(out)
        states={'idle':frames}
        if name=='chest':
            opened=fit(cut('chest_open'),(40,35)); opening=[]
            for i in range(4):
                out=Image.new('RGBA',cell)
                if i==0: out=frames[0].copy()
                else:
                    # Animate the original lid around the rear hinge; shared base.
                    split=int(p.height*.42); base=p.crop((0,split,p.width,p.height))
                    out.alpha_composite(base,((48-p.width)//2,(48-p.height)//2+split))
                    lid=p.crop((0,0,p.width,split)).rotate(i*13,Image.Resampling.NEAREST,expand=True)
                    out.alpha_composite(lid,((48-lid.width)//2,8-i))
                opening.append(out)
            final=Image.new('RGBA',cell); final.alpha_composite(opened,((48-opened.width)//2,24-opened.height//2))
            opening[-1]=final; states.update(locked=frames,opening=opening,open=[final])
        previews+=sheet(name,states,cell,pivot)
    # GUI icons share the actual object silhouettes and retain the 9 equipment IDs.
    for name,source_name in {'weapon':'rapid','armor':'shell','charm':'homing','missile':'homing','map_key':'key',
                             'map_chest':'chest','map_merchant':'merchant','map_player':None,'map_boss':None}.items():
        if source_name: p=fit(cut(source_name),(26,26))
        else:
            path=b.OUT/('player/blue.png' if name=='map_player' else 'bosses/guardian-blue.png')
            sz=96 if name=='map_player' else 320
            p=Image.open(path).crop((0,0,sz,sz)); p=fit(p.crop(p.getbbox()),(26,26))
        out=Image.new('RGBA',(32,32)); out.alpha_composite(p,((32-p.width)//2,(32-p.height)//2))
        previews+=sheet(name,{'idle':[out]},(32,32),(16,16),'ui')
    from build_stage2 import contact
    contact(previews,QA/'items.png',('#172435','#dbdecf'),cell=96)

def terrain():
    raw=Image.open(b.SRC/'terrain.png').convert('RGBA')
    for region,name in ((1,'crystal'),(2,'ash')):
        y=region*316
        field=raw.crop((322,16+y,607,309+y)).resize((96,96),Image.Resampling.BOX)
        surface=raw.crop((18,48+y,302,135+y)).resize((96,20),Image.Resampling.BOX)
        platform=raw.crop((933,38+y,1214,98+y)).resize((96,16),Image.Resampling.BOX)
        common=np.array(field.resize((32,32),Image.Resampling.BOX)).astype(float)
        common[:,0]=(common[:,0]+common[:,-1])/2; common[:,-1]=common[:,0]
        common[0,:]=(common[0,:]+common[-1,:])/2; common[-1,:]=common[0,:]
        yy,xx=np.mgrid[:32,:32]; mix=np.clip(np.minimum.reduce([xx,31-xx,yy,31-yy])/5,0,1)[:,:,None]
        out=Image.new('RGBA',(8192,128))
        for v in range(4):
            patch=np.array(field.crop((v*19%64,v*29%64,v*19%64+32,v*29%64+32))).astype(float)
            for mask in range(256):
                tile=Image.fromarray((patch*mix+common*(1-mix)).astype('uint8'))
                if not mask&1: tile.paste(surface.crop((v*21%64,0,v*21%64+32,9)),(0,0))
                d=ImageDraw.Draw(tile)
                if not mask&16: d.line((0,31,31,31),fill='#171421' if region==1 else '#211819')
                for side,bit in ((0,64),(31,4)):
                    if mask&bit: continue
                    for j in range(32):
                        width=1+int((j+side*3)%11 in (0,1,4)); x=side if side==0 else side-width+1
                        d.line((x,j,x+width-1,j),fill='#211d32' if region==1 else '#292528')
                out.paste(tile,(mask*32,v*32))
        b.quantize(out,b.OUT/'terrain'/(name+'.png'))
        special=Image.new('RGBA',(128,32))
        for v in range(3): special.paste(platform.crop((v*32,0,v*32+32,16)),(v*32,0))
        block=field.crop((16,16,48,48)); d=ImageDraw.Draw(block)
        d.rectangle((1,1,30,30),outline='#b8a3d1' if region==1 else '#bca18b',width=2)
        d.line((11,4,19,12,14,20,24,28),fill='#171421',width=3)
        special.paste(block,(96,0)); b.quantize(special,b.OUT/'terrain'/('special-'+name+'.png'))

def backgrounds():
    raw=Image.open(b.SRC/'stage3.png').convert('RGB')
    for region,box in enumerate(((8,731,508,1008),(523,731,1014,1008),(1030,731,1527,1008))):
        im=raw.crop(box).resize((512,320),Image.Resampling.BOX)
        # Quiet, stepped regional colors. Keep source lighting, never broad
        # checkerboard alpha: that reads as sand instead of distant shadow.
        value=np.array(ImageOps.grayscale(im)).astype(float)*.24
        value=np.floor(value/4)*4
        ramps=((.36,.92,.92,4,13,15),(.77,.48,1.1,17,12,24),(1.1,.55,.35,23,14,11))
        r,g,bl,ro,go,bo=ramps[region]
        rgb=np.stack((value*r+ro,value*g+go,value*bl+bo),axis=-1)
        im=Image.fromarray(np.clip(rgb,0,255).astype('uint8'))
        if region==0:
            # Sparse water reflections below the arches, in the same dark ramp.
            d=ImageDraw.Draw(im)
            for x,y,w in ((22,264,53),(112,283,76),(237,271,42),(354,299,81),(66,310,35)):
                d.line((x,y,x+w,y),fill='#14383d',width=2)
        if region==2:
            d=ImageDraw.Draw(im)
            for x,y in ((35,211),(116,294),(221,253),(316,228),(422,302)):
                d.rectangle((x,y,x+2,y+3),fill='#622217')
                d.point((x+1,y+1),fill='#8e3921')
        # Mirrored second half guarantees exactly matching texture borders.
        im=im.resize((256,320),Image.Resampling.BOX)
        tile=Image.new('RGB',(512,320)); tile.paste(im,(0,0)); tile.paste(ImageOps.mirror(im),(256,0))
        for layer in range(2):
            base=np.array(((6,16,19),(23,16,32),(32,19,14))[region])
            canvas=Image.new('RGBA',(512,1024),tuple(base)+(255,))
            art=tile.convert('RGBA')
            # Fade to the same opaque top/bottom color, safe for arbitrary camera y.
            arr=np.array(art).astype(float); yy=np.arange(320)
            fade=np.minimum(np.clip(yy/48,0,1),np.clip((319-yy)/48,0,1))[:,None,None]
            arr[:,:,:3]=arr[:,:,:3]*fade+base*(1-fade)
            art=Image.fromarray(arr.astype('uint8'))
            if layer==0:
                full=tile.resize((512,512),Image.Resampling.NEAREST).convert('RGBA')
                canvas.paste(full,(0,0)); canvas.paste(ImageOps.flip(full),(0,512))
            else: canvas.paste(art,(0,528))
            if layer==1:
                # Mid-distance layer exposes distant arches between foreground masonry.
                a=np.array(canvas); yy,xx=np.indices(a.shape[:2])
                # Quantized color bands fade the silhouette without alpha dots.
                edge=16*np.sin(xx/511*math.tau*2)+7*np.sin(xx/511*math.tau*5)
                coverage=np.minimum(np.clip((yy-528-edge)/88,0,1),np.clip((848-yy+edge*.25)/72,0,1))
                bands=(np.floor(coverage*6)/6)[:,:,None]
                a[:,:,:3]=a[:,:,:3]*bands+base*(1-bands)
                a[:,:,3]=np.where(coverage>0,255,0)
                # Identical endpoints retain seamless repeated sampling.
                a[:,-1]=a[:,0]; canvas=Image.fromarray(a)
            b.quantize(canvas,b.OUT/'backdrops'/f'{region}-{layer}.png')

def ui():
    panel=fit(cut('panel'),(64,64)).resize((64,64),Image.Resampling.NEAREST)
    # Preserve AI riveted corners; provide a quiet opaque center for readable text.
    ImageDraw.Draw(panel).rectangle((10,10,53,53),fill='#101b29')
    b.quantize(panel,b.OUT/'ui/panel.png')
    grabber=fit(cut('absorb'),(16,20)); out=Image.new('RGBA',(20,24)); out.alpha_composite(grabber,((20-grabber.width)//2,(24-grabber.height)//2))
    b.quantize(out,b.OUT/'ui/grabber.png')
    for state,color in (('normal','#1d3041'),('selected','#3c5060'),('pressed','#172635'),('focus',None)):
        button=panel.copy(); d=ImageDraw.Draw(button)
        d.rectangle((9,9,54,54),fill=color or (0,0,0,0))
        if state=='selected': d.rectangle((5,5,58,58),outline='#e4bd77',width=2)
        if state=='focus':
            button=Image.new('RGBA',(64,64)); ImageDraw.Draw(button).rectangle((2,2,61,61),outline='#ffe9a6',width=2)
        b.quantize(button,b.OUT/'ui'/('button-'+state+'.png'))
    # Animated arrow cursor and shooting direction use existing AI arrow.
    arrow=Image.open(b.OUT/'hud/boss_arrow-blue.png').crop((0,0,48,48))
    frames=[]
    for i in range(4):
        f=Image.new('RGBA',(48,48)); f.alpha_composite(arrow,((0,2,4,2)[i],0)); frames.append(f)
    sheet('cursor',{'idle':frames},category='ui')
    # Scripted 5x7 pixel typography: no AI lettering.
    glyphs={'C':['01111','11000','10000','10000','10000','11000','01111'],
      'H':['10001','10001','10001','11111','10001','10001','10001'],
      'R':['11110','10001','10001','11110','10100','10010','10001'],
      'O':['01110','10001','10001','10001','10001','10001','01110'],
      'M':['10001','11011','10101','10101','10001','10001','10001'],
      'A':['01110','10001','10001','11111','10001','10001','10001'],
      'S':['01111','10000','10000','01110','00001','00001','11110'],
      'I':['11111','00100','00100','00100','00100','00100','11111'],
      'F':['11111','10000','10000','11110','10000','10000','10000'],
      'T':['11111','00100','00100','00100','00100','00100','00100']}
    logo=Image.new('RGBA',(540,64)); d=ImageDraw.Draw(logo)
    for j,c in enumerate('CHROMA SHIFT'):
        if c==' ': continue
        for y,row in enumerate(glyphs[c]):
            for x,v in enumerate(row):
                if v=='1':
                    px=6+j*44+x*6; py=6+y*7
                    d.rectangle((px+3,py+3,px+8,py+9),fill='#070d17')
                    d.rectangle((px,py,px+5,py+6),fill=('#a3e4f2' if j<6 else '#ffc17e') if y<3 else ('#5399b5' if j<6 else '#c27d50'))
    b.quantize(logo,b.OUT/'ui/logo.png')
    # Title composition from canonical robot + ice/fire parts, no new identity.
    title=Image.new('RGBA',(256,512))
    for idx,color in enumerate(('blue','orange')):
        p=Image.open(b.OUT/'player'/(color+'.png')).crop((0,0,96,96)).resize((192,192),Image.Resampling.NEAREST)
        title.alpha_composite(p,(32,idx*240+20))
    b.quantize(title,b.OUT/'ui/title-robot.png')

def main():
    QA.mkdir(parents=True,exist_ok=True)
    items(); terrain(); backgrounds(); ui()
    b.manifest.update(version=3,new_generations=2,new_sources=['stage2.png','stage3.png'])
    (QA/'generation.json').write_text(json.dumps({'new_generations_this_stage':1,'source':'assets/art/source/stage3.png','prompt':'assets/art/source/stage3-prompt.txt'},indent=2)+'\n',encoding='utf-8')
