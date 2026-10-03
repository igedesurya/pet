#!/usr/bin/env python3
"""Build Friday's home activity loops from local artwork and her approved face.

Requires the isolated ComfyUI Python runtime (Pillow, NumPy, SciPy).
Motion uses local displacement rigs rather than regenerating the character per frame.
"""
import json, math
from pathlib import Path
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFilter, ImageFont
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'artwork/friday-activities'
REFERENCE=ROOT/'artwork/friday-character'
PACK=ROOT/'Resources/characters/friday'
CANVAS=(960,1040)
LABELS={'home_waking_up':'Bangun tidur','home_cooking_stir':'Memasak','home_sweeping':'Menyapu','home_watering_plants':'Menyiram tanaman','home_hanging_laundry':'Menjemur pakaian'}

def face_patch(image, target_eyes, closed=False):
    reference=Image.open(REFERENCE/('approved-reference-closed.png' if closed else 'approved-reference.png')).convert('RGB')
    # Source and target eye anchors define a similarity transform, preserving identity.
    s1=np.array([169.,166.]);s2=np.array([222.,160.]);t1,t2=map(lambda p:np.array(p,dtype=float),target_eyes)
    source_delta=s2-s1;target_delta=t2-t1
    a=float(np.dot(source_delta,target_delta)/np.dot(source_delta,source_delta))
    b=float((source_delta[0]*target_delta[1]-source_delta[1]*target_delta[0])/np.dot(source_delta,source_delta))
    matrix=np.array([[a,-b],[b,a]]);offset=t1-matrix@s1;inv=np.linalg.inv(matrix);translate=-inv@offset
    coeff=(inv[0,0],inv[0,1],translate[0],inv[1,0],inv[1,1],translate[1])
    warped=reference.transform(image.size,Image.Transform.AFFINE,coeff,Image.Resampling.BICUBIC)
    mask=Image.new('L',reference.size,0);d=ImageDraw.Draw(mask)
    d.polygon([(165,119),(194,104),(219,103),(235,113),(241,139),(242,164),(235,197),(224,227),(211,245),(195,245),(170,226),(145,207),(135,189),(123,180),(120,168),(136,157),(145,140)],fill=255)
    mask=mask.filter(ImageFilter.GaussianBlur(3.0)).transform(image.size,Image.Transform.AFFINE,coeff,Image.Resampling.BICUBIC)
    return Image.composite(warped,image,mask)

def cutout(image, spec):
    arr=np.asarray(image).astype(float)
    # Remove only neutral backdrop connected to the canvas perimeter.
    neutral=(arr.max(axis=2)-arr.min(axis=2)<19)&(arr.mean(axis=2)>spec.get('white_threshold',230))
    labels,_=ndimage.label(neutral)
    edge_ids=np.unique(np.concatenate([labels[0],labels[-1],labels[:,0],labels[:,-1]]));edge_ids=edge_ids[edge_ids!=0]
    outside=np.isin(labels,edge_ids)
    inside=~outside
    # Manual silhouette bounds preserve pale clothing/props while removing room corners.
    if spec.get('silhouette'):
        region=Image.new('L',image.size);ImageDraw.Draw(region).polygon(spec['silhouette'],fill=255)
        inside &= np.asarray(region)>0
    components,n=ndimage.label(inside);sizes=np.bincount(components.ravel());inside &= sizes[components]>25
    alpha=Image.fromarray((inside*255).astype('uint8')).filter(ImageFilter.GaussianBlur(.45))
    rgba=image.convert('RGBA');rgba.putalpha(alpha);return rgba

def warped_frame(base, spec, phase):
    data=np.asarray(base).astype(np.float32);h,w=data.shape[:2]
    y,x=np.mgrid[:h,:w].astype(np.float32);dx=np.zeros_like(x);dy=np.zeros_like(y)
    for anchor in spec.get('motion',[]):
        cx,cy,rx,ry,ax,ay,*rest=anchor
        lag=rest[0] if rest else 0
        envelope=np.exp(-((x-cx)/rx)**2-((y-cy)/ry)**2)
        wave=math.sin(phase+lag)
        dx+=envelope*ax*wave;dy+=envelope*ay*wave
    coords=[y-dy,x-dx]
    # Premultiplied alpha avoids dark fringes when a limb or prop moves.
    premult=data.copy();premult[:,:,:3]*=premult[:,:,3:4]/255
    mapped=np.stack([ndimage.map_coordinates(premult[:,:,c],coords,order=1,mode='constant',cval=0) for c in range(4)],axis=2)
    alpha=mapped[:,:,3:4];mapped[:,:,:3]=np.divide(mapped[:,:,:3]*255,alpha,out=np.zeros_like(mapped[:,:,:3]),where=alpha>0.1)
    return Image.fromarray(np.clip(mapped,0,255).astype('uint8'),'RGBA')

def effects(frame,pose,spec,index):
    layer=Image.new('RGBA',frame.size);draw=ImageDraw.Draw(layer)
    if pose=='home_cooking_stir' and spec.get('steam'):
        cx,cy=spec['steam']
        for k in range(3):
            t=(index/30+k/3)%1;opacity=int(100*math.sin(math.pi*t));yy=cy-50*t
            xx=cx+(k-1)*14+math.sin(t*7+k)*5
            draw.arc((xx-6,yy-13,xx+6,yy+13),80,280,fill=(200,207,205,opacity),width=2)
    if pose=='home_watering_plants' and spec.get('water'):
        start,end=map(np.array,spec['water'])
        for k in range(9):
            t=(index/30*3+k/9)%1;pos=start+(end-start)*t
            draw.ellipse((pos[0]-1,pos[1]-2,pos[0]+1.5,pos[1]+2),fill=(92,169,205,155))
    frame.alpha_composite(layer)
    return frame

def build(pose,spec):
    directory=ART/pose
    source=Image.open(directory/'base-generated.png').convert('RGB')
    if spec.get('prepare')=='extend_broom':
        # Extend the short generated broom to touch the floor; keep the hand in place.
        broom=source.crop((103,417,211,630));source.paste((245,245,245),(103,417,211,631))
        broom=broom.resize((108,314),Image.Resampling.LANCZOS);source.paste(broom,(103,417))
    if spec.get('beige_shorts'):
        polygon=spec['beige_shorts'];mask=Image.new('L',source.size);ImageDraw.Draw(mask).polygon(polygon,fill=255)
        arr=np.asarray(source).copy();gray=arr.mean(axis=2)
        # Preserve fabric detail while giving the generated denim a neutral beige palette.
        changed=np.stack([gray*1.03+19,gray*.98+10,gray*.87+5],axis=2).clip(0,255).astype('uint8')
        source=Image.composite(Image.fromarray(changed),source,mask.filter(ImageFilter.GaussianBlur(1)))
    opened=face_patch(source,spec['eyes']);closed=face_patch(source,spec['eyes'],True)
    opened.save(directory/'identity-reference.png')
    open_cut=cutout(opened,spec);closed_cut=closed.convert('RGBA');closed_cut.putalpha(open_cut.getchannel('A'))
    open_cut.save(directory/'cutout.png')
    frames=[];previews=[];folder=PACK/pose;folder.mkdir(parents=True,exist_ok=True)
    for i in range(30):
        blink={24:.45,25:1,26:.45}.get(i,0)
        state=Image.blend(open_cut,closed_cut,blink) if blink else open_cut
        frame=effects(warped_frame(state,spec,2*math.pi*i/30),pose,spec,i)
        bounds=spec.get('bounds',frame.size)
        scale=min(900/source.width,1000/source.height)
        resized=frame.resize((round(source.width*scale),round(source.height*scale)),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',CANVAS);canvas.alpha_composite(resized,((CANVAS[0]-resized.width)//2,CANVAS[1]-resized.height))
        canvas.save(folder/f'{i+1:02}.png');frames.append(canvas)
        preview=Image.new('RGBA',CANVAS,(237,239,242,255));preview.alpha_composite(canvas)
        previews.append(preview.resize((300,325),Image.Resampling.LANCZOS).convert('RGB'))
    previews[0].save(directory/'preview.gif',save_all=True,append_images=previews[1:],duration=[167,167,166]*10,loop=0)
    print(pose,len(frames),CANVAS,flush=True)
    return frames[0],previews

def main():
    specs=json.loads((ART/'rig-settings.json').read_text());results={}
    for pose,spec in specs.items():results[pose]=build(pose,spec)
    path=PACK/'pack.json';meta=json.loads(path.read_text())
    existing=[mode for mode in meta['modes'] if mode['id'] not in ['pagi','rumah']]
    meta['modes']=existing+[{'id':'pagi','label':'Bangun tidur','clips':['home_waking_up']},{'id':'rumah','label':'Kegiatan rumah','clips':['home_cooking_stir','home_sweeping','home_watering_plants','home_hanging_laundry']}]
    meta['description']='Friday semi-realistis dengan enam kegiatan rumahan: mandi, bangun tidur, memasak, menyapu, menyiram tanaman, dan menjemur pakaian.'
    path.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    # A compact contact sheet and synchronized preview make all five activities reviewable.
    sheet=Image.new('RGB',(1500,365),(237,239,242));d=ImageDraw.Draw(sheet)
    for j,(pose,(frame,preview)) in enumerate(results.items()):
        sheet.paste(preview[0],(j*300,35));d.text((j*300+14,12),LABELS[pose],fill=(35,42,49))
    sheet.save(ART/'friday-five-activities.png')
    preview_frames=[]
    for i in range(30):
        card=sheet.copy()
        for j,(_,(_,frames)) in enumerate(results.items()):card.paste(frames[i],(j*300,35))
        preview_frames.append(card)
    preview_frames[0].save(ART/'friday-five-activities.gif',save_all=True,append_images=preview_frames[1:],duration=[167,167,166]*10,loop=0)

if __name__=='__main__':main()
