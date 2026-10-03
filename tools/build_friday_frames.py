#!/usr/bin/env python3
"""Assemble Friday's approved bathing artwork and locally generated blink into a pack."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'artwork/friday-character'
PACK=ROOT/'Resources/characters/friday'
CANVAS=(960,1040)

def main():
    source=Image.open(ART/'approved-reference.png').convert('RGB')
    face=Image.open(ART/'face-closed.png').convert('RGB').resize((170,170),Image.Resampling.LANCZOS)
    eyes=Image.open(ART/'eyes-mask.png').convert('L').resize((170,170),Image.Resampling.LANCZOS)
    closed=source.copy()
    closed.paste(Image.composite(face,source.crop((110,90,280,260)),eyes),(110,90))
    closed.save(ART/'approved-reference-closed.png')
    alpha=Image.new('L',source.size,0)
    d=ImageDraw.Draw(alpha)
    d.polygon([(177,30),(204,30),(226,43),(244,70),(256,100),(264,139),(260,196),
      (257,245),(271,283),(291,305),(301,314),(365,319),(429,330),(474,343),(512,355),
      (512,696),(498,747),(486,767),(100,767),(53,744),(22,690),(0,615),(0,443),
      (27,418),(46,403),(49,352),(52,298),(49,262),(60,217),(77,160),(91,118),
      (105,89),(133,54),(151,40)],fill=255)
    # Refine the head outline from dark hair pixels; keep the interior face intact.
    pixels=source.load()
    for y in range(0,270):
        hair=[x for x in range(35,285) if sum(pixels[x,y])/3 < 110]
        d.line((0,y,source.width,y),fill=0)
        if hair:
            d.line((min(hair),y,max(hair),y),fill=255)
    # Clear the remaining neutral bathroom tile beside the left silhouette.
    for y in range(270,410):
        for x in range(0,100):
            r,g,b=pixels[x,y]
            if (r+g+b)/3>125 and max(r,g,b)-min(r,g,b)<12:
                d.point((x,y),fill=0)
    alpha=alpha.filter(ImageFilter.GaussianBlur(0.7))
    alpha.save(ART/'cutout-alpha.png')
    states={}
    for name,img in [('open',source),('half',Image.blend(source,closed,0.5)),('closed',closed)]:
        rgba=img.convert('RGBA');rgba.putalpha(alpha)
        rgba.thumbnail(CANVAS,Image.Resampling.LANCZOS)
        # Scale together to the full canvas height, preserving their common alignment.
        scale=min(CANVAS[0]/source.width,CANVAS[1]/source.height)
        rgba=rgba.resize((round(source.width*scale),round(source.height*scale)),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',CANVAS,(0,0,0,0))
        canvas.alpha_composite(rgba,((CANVAS[0]-rgba.width)//2,CANVAS[1]-rgba.height))
        states[name]=canvas
        canvas.save(ART/f'friday-{name}.png')
    sequence=['open']*24+['half','closed','half']+['open']*3
    frames=PACK/'home_bathing';frames.mkdir(parents=True,exist_ok=True)
    for i,name in enumerate(sequence,1):states[name].save(frames/f'{i:02}.png')
    metadata_path=PACK/'pack.json'
    metadata=json.loads(metadata_path.read_text()) if metadata_path.exists() else {'label':'Friday','modes':[],
              'description':'Karakter semi-realistis terpisah. Paket awal kegiatan mandi dengan kedipan lembut.'}
    metadata['modes']=[{'id':'mandi','label':'Mandi santai','clips':['home_bathing']}]+[
        mode for mode in metadata.get('modes',[]) if mode.get('id')!='mandi']
    (PACK/'pack.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
    previews=[]
    for name in sequence:
        canvas=Image.new('RGBA',CANVAS,(235,237,240,255));canvas.alpha_composite(states[name])
        canvas=canvas.resize((360,390),Image.Resampling.LANCZOS).convert('RGB');previews.append(canvas)
    # Match the runtime's five-second home_ animation loop.
    previews[0].save(ART/'friday-bathing-preview.gif',save_all=True,append_images=previews[1:],duration=167,loop=0)
    print(f'Friday: {len(sequence)} frames, {CANVAS}, pose home_bathing')

if __name__=='__main__':main()
