"""Designs and validates the frontier cluster patterns (spacing, no crossing lines, 2-7
notables, >= 2 orthogonal exits), then exports mods-unpacked/blard-SkillTree/patterns.gd.
Only exports if every pattern passes."""
import math, json
import os
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
MOD = os.path.join(HERE, "..", "mods-unpacked", "blard-SkillTree")
os.makedirs(OUT, exist_ok=True)

P=[]
# node: [x, y, kind, role, heading]; roles: "", "exit", "orbit" (heading +-90 gives side), "port"
def pat(name,tiers,weight,nodes,edges,split=False):
    P.append(dict(name=name,tiers=tiers,weight=weight,nodes=nodes,edges=edges,split=split))
def R(v,n=3): return round(v,n)

# 1 Twin Gate (6)
pat("Twin Gate",[1,2],3,
 [[0,1,"s","",0],[-1,1.6,"s","",0],[1,1.6,"s","",0],[-1.9,2.3,"n","orbit",-90],[1.9,2.3,"n","orbit",90],[0,2.2,"n","exit",0]],
 [[0,1],[0,2],[1,3],[2,4],[0,5]])
# 2 Cross (9)
pat("Cross",[1,2],3,
 [[0,1,"s","",0],[0,2.2,"n","",0],[0,3.4,"n","exit",0],[-1.2,2.2,"s","",0],[-2.4,2.2,"n","orbit",-90],[1.2,2.2,"s","",0],[2.4,2.2,"n","orbit",90],[-1.0,1.15,"s","",0],[1.0,1.15,"s","",0]],
 [[0,1],[1,2],[1,3],[3,4],[1,5],[5,6],[0,7],[7,3],[0,8],[8,5]])
# 3 Hex Cell (10)
c=(0,2.2); r=1.2
hexp=[(R(r*math.cos(math.radians(-90+60*k))), R(c[1]+r*math.sin(math.radians(-90+60*k)))) for k in range(6)]
pat("Hex Cell",[1,2,3],3,
 [[hexp[0][0],hexp[0][1],"s","",0],[hexp[1][0],hexp[1][1],"s","",0],[hexp[2][0],hexp[2][1],"s","",0],[hexp[3][0],hexp[3][1],"s","",0],[hexp[4][0],hexp[4][1],"s","",0],[hexp[5][0],hexp[5][1],"s","",0],
  [0,2.2,"n","",0],[0,4.4,"n","exit",0],[2.25,3.1,"n","orbit",90],[-2.25,3.1,"n","orbit",-90]],
 [[0,1],[1,2],[2,3],[3,4],[4,5],[5,0],[6,0],[6,2],[6,4],[3,7],[2,8],[4,9]])
# 4 Orbit Arc (8), turns right
cx,cy,rr=2.5,1.0,2.5
arc=[(R(cx+rr*math.cos(math.radians(a))),R(cy+rr*math.sin(math.radians(a)))) for a in [180,157.5,135,112.5,90,67.5]]
pat("Orbit Arc",[1,2,3],3,
 [[arc[0][0],arc[0][1],"s","",0],[arc[1][0],arc[1][1],"s","",0],[arc[2][0],arc[2][1],"n","",0],[arc[3][0],arc[3][1],"s","",0],[arc[4][0],arc[4][1],"s","",0],[arc[5][0],arc[5][1],"n","orbit",90],
  [2.0,2.25,"n","port",0],[1.75,4.45,"n","exit",0]],
 [[0,1],[1,2],[2,3],[3,4],[4,5],[3,6],[6,4],[3,7]])
# 5 Fork Web (10)
pat("Fork Web",[1,2],2,
 [[0,1,"s","",0],[0,2,"n","",0],[-0.85,2.75,"s","",0],[0.85,2.75,"s","",0],[-1.6,3.5,"s","",0],[1.6,3.5,"s","",0],[0,3.35,"s","",0],[-2.3,4.3,"n","exit",-45],[2.3,4.3,"n","exit",45],[0,4.45,"s","port",0]],
 [[0,1],[1,2],[1,3],[2,4],[3,5],[2,6],[6,3],[4,7],[5,8],[6,9]], split=True)
# 6 Return Hook (9)
pat("Return Hook",[2,3],2,
 [[0,1,"s","",0],[0.45,1.95,"s","",0],[1.25,2.6,"n","",0],[2.25,2.75,"s","",0],[3.1,2.25,"s","",0],[3.45,1.25,"n","exit",160],[2.1,1.65,"s","port",0],[1.35,3.75,"n","orbit",-90],[3.9,3.1,"s","orbit",90]],
 [[0,1],[1,2],[2,3],[3,4],[4,5],[3,6],[2,7],[4,8]])
# 7 Bastion (14): 3x3 grid + exits
g=[(-1.1,1.0),(0,1.0),(1.1,1.0),(-1.1,2.1),(0,2.1),(1.1,2.1),(-1.1,3.2),(0,3.2),(1.1,3.2)]
order=[1,0,2,3,4,5,6,7,8]
gn=[[g[i][0],g[i][1],"s","",0] for i in order]
idx={i:k for k,i in enumerate(order)}
gn[idx[4]][2]="n"; gn[idx[6]][2]="n"; gn[idx[8]][2]="n"
ge=[[idx[0],idx[1]],[idx[1],idx[2]],[idx[3],idx[4]],[idx[4],idx[5]],[idx[6],idx[7]],[idx[7],idx[8]],[idx[0],idx[3]],[idx[3],idx[6]],[idx[1],idx[4]],[idx[4],idx[7]],[idx[2],idx[5]],[idx[5],idx[8]]]
gn+= [[0,4.35,"n","exit",0],[-2.25,2.1,"n","orbit",-90],[2.25,2.1,"n","orbit",90],[-2.0,3.95,"s","port",0],[2.0,3.95,"s","port",0]]
ge+= [[idx[7],9],[idx[3],10],[idx[5],11],[idx[6],12],[idx[8],13]]
pat("Bastion",[2,3],2,gn,ge)
# 8 Spiral (12)
pts=[];ang=-90.0;rad=1.5;cx,cy=0,2.5
for i in range(10):
    pts.append((R(cx+rad*math.cos(math.radians(ang))),R(cy+rad*math.sin(math.radians(ang)))))
    step=1.08/rad; ang+=math.degrees(step); rad+=0.085
sp=[[x,y,"s","",0] for x,y in pts]
sp[3][2]="n"; sp[6][2]="n"; sp[-1][2]="n"; sp[-1][3]="orbit"; sp[-1][4]=90
sp.append([0,2.5,"c","",0])
se=[[i,i+1] for i in range(9)]
_d=sorted(range(10),key=lambda i: math.dist((sp[i][0],sp[i][1]),(0,2.5)))
_links=[]
for i in _d:
    if all(abs(i-j)>2 for j in _links) and math.dist((sp[i][0],sp[i][1]),(0,2.5))<1.75: _links.append(i)
    if len(_links)==2: break
se+=[[10,i] for i in _links]
k=6; vx,vy=sp[k][0]-cx, sp[k][1]-cy; L=math.hypot(vx,vy)
sp.append([R(sp[k][0]+vx/L*1.15),R(sp[k][1]+vy/L*1.15),"n","exit",0]); se.append([k,len(sp)-1])
pat("Spiral",[2,3],2,sp,se)
# 9 Crossroads (13)
pat("Crossroads",[2,3],2,
 [[0,1,"s","",0],[0,2,"s","",0],[0,3.2,"c","",0],[0,4.4,"s","",0],[0,5.5,"n","exit",0],
  [-1.2,3.2,"s","",0],[-2.4,3.2,"n","orbit",-90],[1.2,3.2,"s","",0],[2.4,3.2,"n","orbit",90],
  [-0.95,2.25,"s","",0],[0.95,2.25,"s","",0],[-0.95,4.15,"s","port",0],[0.95,4.15,"s","port",0]],
 [[0,1],[1,2],[2,3],[3,4],[2,5],[5,6],[2,7],[7,8],[1,9],[9,5],[1,10],[10,7],[5,11],[11,3],[7,12],[12,3]])
# honeycomb builder
def honey(cells, r=1.15):
    # pointy-top hex cells; returns vertices list and edges
    import itertools
    V=[];E=set()
    def vid(p):
        for i,q in enumerate(V):
            if math.dist(p,q)<0.05: return i
        V.append(p); return len(V)-1
    centers=[]
    w=math.sqrt(3)*r
    for (q,s) in cells:
        cxh=w*(q+s/2); cyh=1.5*r*s
        centers.append((cxh,cyh))
        ids=[vid((cxh+r*math.cos(math.radians(90+60*k)), cyh+r*math.sin(math.radians(90+60*k)))) for k in range(6)]
        for k in range(6): E.add(tuple(sorted((ids[k],ids[(k+1)%6]))))
    return V,list(E),centers
def honey_pattern(name,tiers,weight,cells,exits,ports,extra_n=()):
    V,E,C=honey(cells)
    # place so lowest vertex is entry at (0,1)
    low=min(range(len(V)),key=lambda i:(V[i][1],abs(V[i][0])))
    ox,oy=V[low]
    V=[(R(x-ox),R(y-oy+1)) for x,y in V]; C=[(R(x-ox),R(y-oy+1)) for x,y in C]
    order=[low]+[i for i in range(len(V)) if i!=low]
    m={i:k for k,i in enumerate(order)}
    nodes=[[V[i][0],V[i][1],"s","",0] for i in order]
    edges=[[m[a],m[b]] for a,b in E]
    for k,(x,y) in enumerate(C):
        nodes.append([x,y,"n" if k%2==0 else "c","",0]); ci=len(nodes)-1
        # hub links to 3 alternate vertices of its cell
        cand=sorted([j for j in range(len(order)) if abs(math.dist((nodes[j][0],nodes[j][1]),(x,y))-1.15)<0.05],key=lambda j: math.atan2(nodes[j][1]-y,nodes[j][0]-x))
        for j in cand[0::2]: edges.append([j,ci])
    for (vx,vy,role,hd,kind) in exits+ports:
        # attach to nearest existing vertex
        best=min(range(len(nodes)),key=lambda j: math.dist((nodes[j][0],nodes[j][1]),(vx,vy)))
        nodes.append([vx,vy,kind,role,hd]); edges.append([best,len(nodes)-1])
    pat(name,tiers,weight,nodes,edges)

def honey_auto(name,tiers,weight,cells):
    V,E,C=honey(cells)
    low=min(range(len(V)),key=lambda i:(V[i][1],abs(V[i][0])))
    ox,oy=V[low]
    V=[(R(x-ox),R(y-oy+1)) for x,y in V]
    top=max(V,key=lambda p:(p[1],-abs(p[0]))); left=min(V,key=lambda p:(p[0],-p[1])); right=max(V,key=lambda p:(p[0],p[1]))
    ul=min(V,key=lambda p:(p[0]-p[1])); ur=max(V,key=lambda p:(p[0]+p[1]))
    exits=[(top[0],R(top[1]+1.15),"exit",0,"n"),(R(left[0]-1.15),left[1],"orbit",-90,"n"),(R(right[0]+1.15),right[1],"orbit",90,"n")]
    ports=[]
    for p,sx in ((ul,-1),(ur,1)):
        q=(R(p[0]+sx*0.81),R(p[1]+0.81))
        ports.append((q[0],q[1],"port",0,"s"))
    honey_pattern(name,tiers,weight,cells,exits,ports)
honey_auto("Honeycomb",[3],2,[(0,0),(-1,1),(0,1)])
honey_auto("Hive",[3],1,[(0,0),(-1,1),(0,1),(-1,2)])
# Ladder Loop (12): rails with rungs, exits orthogonal
pat("Ladder Loop",[2,3],2,
 [[0,1,"s","",0],[-0.9,1.7,"s","",0],[0.9,1.7,"s","",0],[-0.9,2.8,"s","",0],[0.9,2.8,"s","",0],[0,2.8,"n","",0],[-0.9,3.9,"s","",0],[0.9,3.9,"s","",0],
  [0,4.6,"n","exit",0],[-2.05,2.8,"n","orbit",-90],[2.05,2.8,"n","orbit",90],[0,1.9,"s","port",0]],
 [[0,1],[0,2],[1,3],[2,4],[3,5],[5,4],[3,6],[4,7],[6,8],[7,8],[3,9],[4,10],[0,11]], split=True)
# Diamond Gate (7)
pat("Diamond Gate",[1],2,
 [[0,1,"s","",0],[-0.9,1.9,"s","",0],[0.9,1.9,"s","",0],[0,2.8,"n","exit",0],[-1.9,2.3,"n","orbit",-90],[1.9,2.3,"s","orbit",90]],
 [[0,1],[0,2],[1,3],[2,3],[1,4],[2,5]])

# ---- validation
def cross(a,b,c,d):
    def o(p,q,r): return (q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
    return o(c,d,a)*o(c,d,b)<0 and o(a,b,c)*o(a,b,d)<0
def psd(p,a,b):
    dx,dy=b[0]-a[0],b[1]-a[1]; L=dx*dx+dy*dy
    t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/L)) if L else 0
    return math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)
allok=True
for p in P:
    pts=[(0,0)]+[(n[0],n[1]) for n in p['nodes']]
    E=[(0,1)]+[(a+1,b+1) for a,b in p['edges']]
    md=min(math.dist(pts[i],pts[j]) for i in range(len(pts)) for j in range(i+1,len(pts)))
    bad=[]
    for i,(a,b) in enumerate(E):
        for (c,d) in E[i+1:]:
            if len({a,b,c,d})==4 and cross(pts[a],pts[b],pts[c],pts[d]): bad.append(('X',a-1,b-1,c-1,d-1))
        for k in range(len(pts)):
            if k not in (a,b) and psd(pts[k],pts[a],pts[b])<0.4: bad.append(('near',k-1,a-1,b-1))
        if math.dist(pts[a],pts[b])>1.75: bad.append(('long',a-1,b-1))
    nb=sum(1 for n in p['nodes'] if n[2] in 'nc')
    ex=[n for n in p['nodes'] if n[3] in ('exit','orbit')]
    hs=[n[4] for n in ex]
    orth=any(abs(a-b)>=80 for a in hs for b in hs)
    # every node reachable
    adj={i:[] for i in range(len(p['nodes']))}
    for a,b in p['edges']: adj[a].append(b); adj[b].append(a)
    seen={0};st=[0]
    while st:
        c=st.pop()
        for n in adj[c]:
            if n not in seen: seen.add(n); st.append(n)
    if len(seen)!=len(p['nodes']): bad.append('disconnected')
    if not(2<=nb<=7): bad.append(('notables',nb))
    if len(ex)<2 or not orth: bad.append(('exits',hs))
    if md<0.85: bad.append(('mindist',round(md,2)))
    if bad: allok=False
    print(f"{p['name']:13s} n={len(p['nodes']):2d} big={nb} exits={hs} md={md:.2f}", bad if bad else "ok")
json.dump(P,open(os.path.join(OUT,'patterns.json'),'w'))

# ---- export to GDScript
def gd(x):
    if isinstance(x,bool): return "true" if x else "false"
    if isinstance(x,str): return json.dumps(x)
    if isinstance(x,float): return repr(round(x,3))
    if isinstance(x,int): return str(x)
    if isinstance(x,list): return "["+", ".join(gd(e) for e in x)+"]"
if allok:
    src=open(os.path.join(MOD,'patterns.gd')).read()
    head=src[:src.index('const PATTERNS := [')]
    out=[head+"const PATTERNS := ["]
    for p in P:
        out.append("\t{")
        out.append(f'\t\t"name": {gd(p["name"])}, "tiers": {gd(p["tiers"])}, "weight": {p["weight"]}, "split": {gd(p["split"])},')
        out.append('\t\t"nodes": [')
        for n in p['nodes']:
            out.append("\t\t\t"+gd([float(n[0]),float(n[1]),n[2],n[3],int(n[4])])+",")
        out.append("\t\t],")
        out.append(f'\t\t"edges": {gd(p["edges"])},')
        out.append("\t},")
    out.append("]")
    open(os.path.join(MOD,'patterns.gd'),'w').write("\n".join(out)+"\n")
    print("wrote patterns.gd")
print("ALL OK" if allok else "PROBLEMS")
