"""Four-connected opaque component inspection, no external image dependencies."""
from collections import deque
import numpy as np
from PIL import Image

def components(im):
    mask=np.array(im.convert('RGBA'))[:,:,3]>0
    seen=np.zeros_like(mask); result=[]; h,w=mask.shape
    for y,x in zip(*np.where(mask)):
        if seen[y,x]: continue
        queue=deque([(x,y)]); seen[y,x]=True; pixels=[]
        while queue:
            px,py=queue.popleft(); pixels.append((px,py))
            for xx,yy in ((px-1,py),(px+1,py),(px,py-1),(px,py+1)):
                if 0<=xx<w and 0<=yy<h and mask[yy,xx] and not seen[yy,xx]:
                    seen[yy,xx]=True; queue.append((xx,yy))
        result.append(pixels)
    return sorted(result,key=len,reverse=True)

def largest(im):
    groups=components(im)
    if not groups: return im
    a=np.array(im); keep=np.zeros(a.shape[:2],dtype=bool)
    for x,y in groups[0]: keep[y,x]=True
    a[~keep]=0
    return Image.fromarray(a)
