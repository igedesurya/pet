import sys
sys.path.insert(0,'/Users/surya/.codex/plugins/cache/openai-curated-remote/work-pets/0.1.6/skills/create-pet/scripts')
from despill_chroma_edges import decontaminate_image
from pathlib import Path
from PIL import Image,ImageDraw,ImageSequence
root=Path('work/nori-adult/gestures'); out=Path('outputs/nori-adult')
names=['kiss','hug','sitting','okay-smile','talking','laughing','sad','seated-split','hand-on-knee']
labels=['Kiss','Hug','Duduk','OK / senyum','Bicara','Ketawa','Sedih','Duduk split / peregangan','Duduk tangan di lutut']
seq=[]
for name in names:
 if name=='sad':
  frames=[f.copy().convert('RGBA') for f in ImageSequence.Iterator(Image.open(out/'gestures/sad.gif'))]
 else:
  paths=sorted(p for p in (root/name/'qa').rglob('*.png') if p.parent.parent.name=='frames')
  frames=[]
  for p in paths:
   src=decontaminate_image(Image.open(p),chroma_key=(255,0,255))[0]; bg=Image.new('RGBA',(256,250),'#edf1f5');bg.alpha_composite(src,((256-src.width)//2,8));frames.append(bg)
 frames=[f.convert('RGB') for f in frames]
 frames[0].save(out/'gestures'/f'{name}.gif',save_all=True,append_images=frames[1:],duration=160,loop=0,disposal=2)
 seq.append(frames)
gallery=[]
for t in range(24):
 im=Image.new('RGB',(768,750),'#edf1f5');d=ImageDraw.Draw(im)
 for i,frames in enumerate(seq):
  x=(i%3)*256;y=(i//3)*250; im.paste(frames[t%len(frames)],(x,y));d.rectangle((x,y+224,x+255,y+249),fill='#edf1f5');d.text((x+10,y+230),labels[i],fill='#172030')
 gallery.append(im)
gallery[0].save(out/'gesture-gallery.gif',save_all=True,append_images=gallery[1:],duration=160,loop=0,disposal=2)
gallery[2].save(out/'gesture-gallery.png')
print('Rendered nine gesture previews from extracted transparent frames')
