"""Python mirror of the frontier placement in skill_tree.gd: follows orbit exits from a
keystone and renders tools/out/orbit_simulation.png. Run gen_tree.py and gen_patterns.py first."""
import json, math, random
import os
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
MOD = os.path.join(HERE, "..", "mods-unpacked", "blard-SkillTree")
os.makedirs(OUT, exist_ok=True)

from PIL import Image, ImageDraw
t=json.load(open(os.path.join(OUT,'tree.json'))); P=json.load(open(os.path.join(OUT,'patterns.json')))
S=160; MIN=130; CLEAR=55; LINK=300
nodes={n['id']:dict(n) for n in t['nodes']}; edges=[tuple(e) for e in t['edges']]
for n in nodes.values():
    if n['kind']==3: n['heading']=math.atan2(n['y'],n['x']); n['pd']=0
def V(i): return (nodes[i]['x'],nodes[i]['y'])
def cross(a,b,c,d):
    def o(p,q,r): return (q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
    return o(c,d,a)*o(c,d,b)<0 and o(a,b,c)*o(a,b,d)<0
def psd(p,a,b):
    dx,dy=b[0]-a[0],b[1]-a[1]; L=dx*dx+dy*dy
    tt=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/L)) if L else 0
    return math.hypot(p[0]-a[0]-tt*dx,p[1]-a[1]-tt*dy)
cnt=[0]; expanded=set()
def edge_ok(a,b,npts,nedges,skip_ids):
    for (c,d) in nedges:
        if a in (c,d) or b in (c,d): continue
        if cross(a,b,c,d): return False
    for q in npts:
        if q==a or q==b: continue
        if psd(q,a,b)<CLEAR: return False
    return True
def expand(pid,rng):
    expanded.add(pid)
    par=nodes[pid]; pp=V(pid); h=par.get('heading',math.atan2(pp[1],pp[0])); pd=par.get('pd',0)+1
    if par.get('orbit'): h=math.atan2(pp[1],pp[0])+par['orbit']*math.pi/2
    tier=1 if pd<=2 else (2 if pd<=4 else 3)
    R=8*S
    near_pts=[V(i) for i in nodes if math.dist(V(i),pp)<R+200]
    near_edges=[(V(a),V(b)) for a,b in edges if min(math.dist(V(a),pp),math.dist(V(b),pp))<R+400]
    pool=[p for p in P if tier in p['tiers']]
    order=[]
    w=pool[:]
    while w:
        tot=sum(p['weight'] for p in w); r=rng.uniform(0,tot)
        for p in w:
            r-=p['weight']
            if r<=0: order.append(p); w.remove(p); break
    order+= [p for p in P if p not in order]
    for p in order:
        for off in [0,15,-15,30,-30,45,-45,60,-60,90,-90]:
            for mir in ([1,-1] if rng.random()<.5 else [-1,1]):
                a=h+math.radians(off); f=(math.cos(a),math.sin(a)); rt=(-f[1],f[0])
                W=[(pp[0]+(n[0]*mir*rt[0]+n[1]*f[0])*S, pp[1]+(n[0]*mir*rt[1]+n[1]*f[1])*S) for n in p['nodes']]
                if any(math.dist(w2,q)<MIN for w2 in W for q in near_pts): continue
                E=[(pp,W[0])]+[(W[i],W[j]) for i,j in p['edges']]
                if not all(edge_ok(a2,b2,near_pts,near_edges,None) for a2,b2 in E): continue
                ids=[]
                for k,n in enumerate(p['nodes']):
                    cnt[0]+=1; gid=f"g{cnt[0]}"; ids.append(gid)
                    hd=a+math.radians(n[4]*mir)
                    nodes[gid]={'id':gid,'x':W[k][0],'y':W[k][1],'kind':{'s':1,'n':2,'c':3}[n[2]],'role':n[3],'heading':hd,'pd':pd,'gen':True,'frontier':n[3] in ('exit','orbit'),'orbit':(1 if n[4]*mir>0 else -1) if n[3]=='orbit' else 0}
                edges.append((pid,ids[0]))
                for i,j in p['edges']: edges.append((ids[i],ids[j]))
                # links
                adj={}
                for x,y in edges: adj.setdefault(x,[]).append(y); adj.setdefault(y,[]).append(x)
                hops={pid:0};q=[pid]
                while q:
                    c=q.pop(0)
                    if hops[c]>=4: continue
                    for nb in adj.get(c,[]):
                        if nb not in hops: hops[nb]=hops[c]+1; q.append(nb)
                links=0
                allpts=[V(i) for i in nodes]; alledges=[(V(x),V(y)) for x,y in edges]
                for k,n in sorted(enumerate(p['nodes']),key=lambda kn: 0 if kn[1][3]=='port' else 1):
                    if links>=2 or n[3]=='': continue
                    me=ids[k]; best=None;bd=LINK
                    for oid,o in nodes.items():
                        if oid in ids or oid in hops: continue
                        dd=math.dist(V(me),V(oid))
                        if dd<bd and edge_ok(V(me),V(oid),allpts,alledges,None): bd=dd;best=oid
                    if best: edges.append((me,best)); links+=1; nodes[me]['link']=True
                return p['name'],off
    return None
rng=random.Random(3)
log=[]
# player goes deep from s1_8 repeatedly taking first exit, also from s2_8 and s0_8
cur='s1_8'
for it in range(10):
    r=expand(cur,rng); log.append((cur,r))
    if not r: break
    ex=[i for i in nodes if nodes[i].get('frontier') and i not in expanded and nodes[i].get('gen') and nodes[i]['pd']==it+1]
    orb=[i for i in ex if nodes[i].get('orbit')==1] or ex
    cur=orb[0]
for k in ['s5_8']: log.append((k,expand(k,rng)))
print(log, cnt[0])
xs=[n['x'] for n in nodes.values()]; ys=[n['y'] for n in nodes.values()]
mn=min(min(xs),min(ys))-200; mx=max(max(xs),max(ys))+200
SZ=1600; sc=SZ/(mx-mn); T=lambda p:((p[0]-mn)*sc,(p[1]-mn)*sc)
img=Image.new('RGB',(SZ,SZ),(10,10,14)); d=ImageDraw.Draw(img)
for a,b in edges:
    link=nodes[a].get('link') or nodes[b].get('link')
    d.line([T(V(a)),T(V(b))],fill=(90,90,105),width=2)
for n in nodes.values():
    r={0:30,1:15,2:25,3:36}[n['kind']]*sc; x,y=T((n['x'],n['y']))
    c=(150,150,160)
    if n.get('gen'): c={'exit':(196,140,255),'orbit':(120,230,255),'port':(255,200,90),'':(140,200,255)}[n['role']]
    d.ellipse([x-r,y-r,x+r,y+r],outline=c,width=2)
img.save(os.path.join(OUT,'orbit_simulation.png'))
