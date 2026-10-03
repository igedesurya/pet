from PIL import Image,ImageDraw,ImageFilter
from scipy.ndimage import gaussian_filter
import numpy as np
from pathlib import Path
out=Path('/Users/surya/pet/artwork/friday-activities-v2');im=Image.open(out/'home_watering_plants-first-pass-v2.png').convert('RGB');a=np.asarray(im).astype(float)
m=Image.new('L',im.size);d=ImageDraw.Draw(m)
d.polygon([(43,282),(65,283),(112,337),(140,350),(235,343),(263,299),(280,339),(283,473),(271,539),(291,591),(316,768),(0,768),(0,641),(38,604),(71,541),(76,478),(89,403),(57,352)],fill=255);d.polygon([(73,280),(94,287),(132,365),(110,389)],fill=255)
d.polygon([(172,586),(218,577),(247,596),(263,614),(291,602),(320,643),(315,667),(287,701),(260,715),(222,700),(179,658),(172,633)],fill=0);d.line([(255,604),(296,551),(337,505),(375,473),(403,454),(432,438)],fill=0,width=14)
ma=np.asarray(m).astype(float)/255;skin=(a[:,:,0]-a[:,:,1]>23)&(a[:,:,0]-a[:,:,2]>38);ma*=1-gaussian_filter(skin.astype(float),.55)
y,x=np.mgrid[:768,:512];hair=(y<344)&(x>98)&(x<256)&(a.mean(axis=2)<90)&(a[:,:,0]-a[:,:,1]>5);ma[hair]=0
lum=100+np.sqrt(a.mean(axis=2)/255)*125;fabric=np.stack([lum*1.025,lum,lum*.94],axis=2);result=a*(1-ma[:,:,None])+fabric*ma[:,:,None];im=Image.fromarray(result.clip(0,255).astype('uint8'))
strap=Image.new('L',im.size);sd=ImageDraw.Draw(strap);sd.polygon([(44,287),(58,283),(81,325),(92,354),(80,374),(65,349),(48,311)],fill=255);strap=strap.filter(ImageFilter.GaussianBlur(2))
ref=Image.open('/Users/surya/pet/artwork/friday-character/approved-reference.png').convert('RGB');skin_patch=ref.crop((69,350,126,414)).resize((62,100),Image.Resampling.BICUBIC);skin_canvas=im.copy();skin_canvas.paste(skin_patch,(34,279));im=Image.composite(skin_canvas,im,strap)
patch=im.crop((328,325,416,416));erase=Image.new('L',(88,91));ed=ImageDraw.Draw(erase);ed.polygon([(15,38),(73,9),(87,20),(87,57),(42,81),(26,70)],fill=255);erase=erase.filter(ImageFilter.GaussianBlur(5));im.paste(patch,(424,325),erase)
layer=Image.new('RGBA',im.size);ld=ImageDraw.Draw(layer);pts=[]
for k in range(40):
 t=k/39;pts.append(((1-t)**2*436+2*(1-t)*t*482+t*t*459,(1-t)**2*436+2*(1-t)*t*460+t*t*516))
ld.line(pts,fill=(155,214,224,165),width=2);im=Image.alpha_composite(im.convert('RGBA'),layer).convert('RGB')
bodymask=Image.new('L',im.size);bd=ImageDraw.Draw(bodymask);bd.polygon([(263,714),(289,698),(312,670),(319,733),(304,768)],fill=255);bodymask=bodymask.filter(ImageFilter.GaussianBlur(1));im=Image.composite(Image.fromarray(fabric.clip(0,255).astype('uint8')),im,bodymask);im.save(out/'home_watering_plants-draft-v2.png')
