#!/usr/bin/env python3
"""Animate approved Friday illustrations with small local action rigs.

Source pixels and native Vision alpha mattes are retained. No identity/outfit is
regenerated. Stages sixty frames, validates them, then installs only new clips.
Use the ComfyUI Python runtime (Pillow, NumPy, SciPy).
"""
from __future__ import annotations
import argparse, hashlib, json, math, shutil
from pathlib import Path
import numpy as np
from scipy.ndimage import map_coordinates
from PIL import Image, ImageDraw, ImageFilter, ImageFont
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'artwork/friday-animation'
SOURCE=ROOT/'artwork/friday-activities-natural'
MATTES=ROOT/'artwork/friday-animation-masks/masks'
PACK=ROOT/'Resources/characters/friday'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def soft_polygon(points, size, scale, feather):
    mask=Image.new('L',size)
    ImageDraw.Draw(mask).polygon([(x*scale,y*scale) for x,y in points],fill=255)
    if feather: mask=mask.filter(ImageFilter.GaussianBlur(feather*scale))
    return np.asarray(mask,dtype=np.float32)/255


class Rig:
    def __init__(self, source, alpha, spec, size):
        self.spec=spec;self.size=size;self.scale=size[0]/source.width
        rgba=source.convert('RGBA');rgba.putalpha(alpha)
        rgba=rgba.resize(size,Image.Resampling.LANCZOS)
        self.data=np.asarray(rgba,dtype=np.float32)
        self.data[:,:,:3]*=self.data[:,:,3:4]/255
        self.y,self.x=np.mgrid[:size[1],:size[0]].astype(np.float32)
        self.anchors=[]
        for cx,cy,rx,ry,ax,ay,freq,lag in spec.get('anchors',[]):
            s=self.scale
            field=np.exp(-((self.x-cx*s)/(rx*s))**2-((self.y-cy*s)/(ry*s))**2)
            self.anchors.append((field,ax*s,ay*s,freq,lag))
        self.regions=[]
        for region in spec.get('regions',[]):
            mask=soft_polygon(region['polygon'],size,self.scale,region.get('feather',8))
            self.regions.append((region,mask))
        left,top,right,bottom=spec['face']
        # Inside the face the displacement is a single translation: no facial morph.
        self.face=soft_polygon([(left,top),(right,top),(right,bottom),(left,bottom)],size,self.scale,7)
        self.breath=np.exp(-((self.x-(left+right)/2*self.scale)/(340*self.scale))**2-((self.y-650*self.scale)/(550*self.scale))**2)

    def displacement(self, phase):
        dx=np.zeros_like(self.x);dy=np.zeros_like(self.y)
        for field,ax,ay,freq,lag in self.anchors:
            wave=math.sin(phase*freq+lag)-math.sin(lag)
            dx+=field*ax*wave;dy+=field*ay*wave
        for region,mask in self.regions:
            p=phase*region.get('frequency',1)
            wave=(1-math.cos(p))/2 if region.get('wave')=='stretch' else math.sin(p)
            kind=region['kind'];s=self.scale
            if kind=='rotate':
                px,py=region['pivot'];angle=math.radians(region['degrees'])*wave
                u=self.x-px*s;v=self.y-py*s
                dx+=mask*((math.cos(angle)-1)*u-math.sin(angle)*v)
                dy+=mask*(math.sin(angle)*u+(math.cos(angle)-1)*v)
            else:
                ramp=1
                if kind=='cloth' or region.get('wave')=='sweep':
                    ramp=np.clip((self.y-region['pivot'][1]*s)/(region['reach']*s),0,1)
                yy=math.cos(p)-1 if region.get('ellipse') else wave
                dx+=mask*ramp*region.get('x',0)*s*wave
                dy+=mask*ramp*region.get('y',0)*s*yy
        hx,hy=self.spec['head_shift'];headwave=math.sin(phase)
        dx=dx*(1-self.face)+hx*self.scale*headwave*self.face
        dy=dy*(1-self.face)+hy*self.scale*headwave*self.face
        return dx,dy

    def frame(self, phase, i, count):
        dx,dy=self.displacement(phase)
        coords=[self.y-dy,self.x-dx]
        mapped=np.stack([map_coordinates(self.data[:,:,c],coords,order=1,mode='constant',cval=0) for c in range(4)],axis=2)
        a=mapped[:,:,3:4]
        mapped[:,:,:3]=np.divide(mapped[:,:,:3]*255,a,out=np.zeros_like(mapped[:,:,:3]),where=a>.01)
        frame=Image.fromarray(np.clip(mapped,0,255).astype('uint8'))
        effects=Image.new('RGBA',self.size);draw=ImageDraw.Draw(effects)
        s=self.scale
        if 'steam' in self.spec:
            cx,cy=self.spec['steam']
            for k in range(4):
                t=(i/count+k/4)%1
                opacity=round(70*math.sin(math.pi*t))
                base_x=(cx+(k-1.5)*20)*s
                pts=[]
                for j in range(14):
                    r=j/13
                    pts.append((base_x+math.sin(r*6+phase+k)*7*s,(cy-45*t-60*r)*s))
                draw.line(pts,fill=(239,239,232,opacity),width=max(1,round(2*s)))
            effects=effects.filter(ImageFilter.GaussianBlur(1.2*s))
        if 'water' in self.spec:
            start,control,end=[np.array(p,dtype=float)*s for p in self.spec['water']]
            ix,iy=map(lambda z:round(z),start)
            start+=np.array([dx[iy,ix],dy[iy,ix]])
            for k in range(12):
                t=(i/count*6+k/12)%1
                point=(1-t)**2*start+2*(1-t)*t*control+t*t*end
                r=.85*s
                draw.ellipse((point[0]-r,point[1]-r,point[0]+r,point[1]+2*r),fill=(225,241,246,180))
        frame.alpha_composite(effects)
        return frame


def gif(path, images, milliseconds):
    # A shared palette eliminates artificial color flicker between motion frames.
    palette=images[0].convert('RGB').quantize(colors=192)
    sequence=[im.convert('RGB').quantize(palette=palette,dither=Image.Dither.FLOYDSTEINBERG) for im in images]
    sequence[0].save(path,save_all=True,append_images=sequence[1:],duration=milliseconds,loop=0,optimize=False,disposal=2)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--install',action='store_true');parser.add_argument('--clips',nargs='*');args=parser.parse_args()
    config=json.loads((ART/'rig.json').read_text());canvas_size=tuple(config['canvas']);size=tuple(config['working_size']);count=config['frames']
    frames_dir=ART/'frames';previews_dir=ART/'previews';frames_dir.mkdir(exist_ok=True);previews_dir.mkdir(exist_ok=True)
    keys=args.clips or list(config['clips']);results={};reports=[]
    # GIF duration has 10ms units. Runtime uses exact5s/count per frame.
    milliseconds=[80,80,90]*(count//3)
    for name in keys:
        spec=config['clips'][name];source_path=SOURCE/(name+'.png');matte_path=MATTES/(name+'.png')
        source=Image.open(source_path).convert('RGB');alpha=Image.open(matte_path).convert('L')
        assert source.size==alpha.size,(name,source.size,alpha.size)
        rig=Rig(source,alpha,spec,size);directory=frames_dir/name;directory.mkdir(exist_ok=True)
        previews=[];hashes=[];measurements=[]
        for i in range(count):
            frame=rig.frame(2*math.pi*i/count,i,count)
            canvas=Image.new('RGBA',canvas_size)
            canvas.alpha_composite(frame,((canvas_size[0]-size[0])//2,canvas_size[1]-size[1]-24))
            file=directory/f'{i+1:02}.png';canvas.save(file,compress_level=4)
            hashes.append(digest(file))
            if i in (0,7,15,22,30,37,45,52):
                canvas.save(previews_dir/f'{name}-key-{i:02}.png')
            preview=Image.new('RGBA',canvas_size,(234,237,240,255));preview.alpha_composite(canvas)
            previews.append(preview.resize((288,312),Image.Resampling.LANCZOS).convert('RGB'))
            if i>0: measurements.append(float(np.abs(np.asarray(previews[-1],dtype=float)-np.asarray(previews[-2],dtype=float)).mean()))
        unique=len(set(hashes));assert unique>count*.9,(name,unique)
        files=sorted(directory.glob('*.png'));assert len(files)==count,(name,len(files))
        for file in files:
            with Image.open(file) as im:
                assert im.mode=='RGBA' and im.size==canvas_size
                assert im.getchannel('A').getextrema()==(0,255)
        seam=float(np.abs(np.asarray(previews[0],dtype=float)-np.asarray(previews[-1],dtype=float)).mean())
        mean_delta=float(np.mean(measurements));assert seam<max(mean_delta*3,.15),(name,'loop seam',seam,mean_delta)
        gif(previews_dir/(name+'.gif'),previews,milliseconds)
        results[name]=previews
        report={'clip':name,'label':spec['label'],'frames':count,'unique_frames':unique,'canvas':list(canvas_size),'duration_seconds':config['duration'],'source_sha256':digest(source_path),'matte_sha256':digest(matte_path),'mean_adjacent_delta':round(mean_delta,4),'seam_delta':round(seam,4)}
        reports.append(report);print(json.dumps(report),flush=True)
    # Preview is landscape so every approved activity is visible at once.
    font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',17)
    combined=[]
    for i in range(count):
        card=Image.new('RGB',(len(keys)*288,348),(234,237,240));draw=ImageDraw.Draw(card)
        for j,name in enumerate(keys):
            draw.text((j*288+14,10),config['clips'][name]['label'],fill=(36,41,47),font=font);card.paste(results[name][i],(j*288,36))
        combined.append(card)
    gif(previews_dir/'friday-five-activities.gif',combined,milliseconds)
    combined[0].save(previews_dir/'friday-five-activities.png')
    (ART/'validation.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2)+'\n')
    if args.install:
        for name in keys:
            target=PACK/name;staging=PACK/(name+'.staging')
            if staging.exists():shutil.rmtree(staging)
            shutil.copytree(frames_dir/name,staging)
            if target.exists():shutil.rmtree(target)
            staging.rename(target)
        metadata=json.loads((PACK/'pack.json').read_text())
        keep=[mode for mode in metadata.get('modes',[]) if mode['id'] not in ('pagi','rumah')]
        metadata['modes']=keep+[{'id':'pagi','label':'Bangun tidur','clips':['home_waking_up']},{'id':'rumah','label':'Kegiatan rumah','clips':['home_cooking_stir','home_sweeping','home_watering_plants','home_hanging_laundry']}]
        metadata['description']='Friday dengan enam kegiatan: mandi, bangun tidur, memasak, menyapu, menyiram tanaman, dan menjemur pakaian.'
        (PACK/'pack.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
        print('Installed only new activity clips; home_bathing retained.',flush=True)

if __name__=='__main__':main()
