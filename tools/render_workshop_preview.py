"""Renders the Workshop preview image to tools/out/workshop_preview.png."""
import json, math
import os
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
MOD = os.path.join(HERE, "..", "mods-unpacked", "blard-SkillTree")
os.makedirs(OUT, exist_ok=True)

from PIL import Image, ImageDraw, ImageFont
t=json.load(open(os.path.join(OUT,'tree.json'))); N={n['id']:n for n in t['nodes']}
S=2048; img=Image.new('RGB',(S,S),(8,8,12)); d=ImageDraw.Draw(img)
sc=0.86; c=(S/2,S/2+60)
P=lambda n:(c[0]+n['x']*sc,c[1]+n['y']*sc)
alloc={"start","s1_1","s1_2","s1_3","s1_R4","s1_R5","s1_R6","s1_7","s1_8","s0_1","ri0","s2_1","s2_2","s2_3","s2_L4"}
col=[(224,87,79),(240,138,60),(242,209,90),(111,209,111),(255,106,43),(111,168,245),(230,194,64),(127,230,216)]
gold=(255,213,96)
for a,b in t['edges']:
    on=a in alloc and b in alloc
    d.line([P(N[a]),P(N[b])],fill=gold if on else (60,60,72),width=12 if on else 6)
fb=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',26)
for n in t['nodes']:
    r={0:30,1:15,2:25,3:36}[n['kind']]*1.1; x,y=P(n)
    cc=col[n['sector']] if n['sector']>=0 else ((255,213,96) if n['kind']==0 else (185,185,200))
    on=n['id'] in alloc
    if n['kind']==3: d.ellipse([x-r-10,y-r-10,x+r+10,y+r+10],fill=tuple(int(v*.6) for v in (gold if on else cc)))
    d.ellipse([x-r-6,y-r-6,x+r+6,y+r+6],fill=gold if on else tuple(int(v*.75) for v in cc))
    d.ellipse([x-r,y-r,x+r,y+r],fill=tuple(int(v*.75) for v in cc) if on else (22,22,30))
    if n['kind']>=2: d.text((x,y+r+24),n['name'],fill=(240,240,240) if on else (170,170,180),font=fb,anchor='mm')
ft=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',120)
d.text((S/2,110),"SKILL TREE",fill=gold,font=ft,anchor='mm',stroke_width=6,stroke_fill=(0,0,0))
img.resize((1024,1024),Image.LANCZOS).save(os.path.join(OUT,'workshop_preview.png'))
