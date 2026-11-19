"""Generates the fixed 105-node tree: writes mods-unpacked/blard-SkillTree/tree_data.gd and
tools/out/tree.json (used by the preview/simulation scripts)."""
import math, json
import os
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
MOD = os.path.join(HERE, "..", "mods-unpacked", "blard-SkillTree")
os.makedirs(OUT, exist_ok=True)

T = {"max_hp":3,"hp_regeneration":2,"armor":1,"melee_damage":2,"percent_damage":5,"lifesteal":1,
     "crit_chance":3,"attack_speed":5,"ranged_damage":1,"range":15,"elemental_damage":1,"engineering":2,
     "harvesting":5,"luck":5,"speed":3,"dodge":3,"xp_gain":5,"explosion_damage":10,"explosion_size":5,
     "structure_attack_speed":5,"structure_percent_damage":5,"structure_range":15,"knockback":1,"piercing":1,
     "burning_spread":1,"chance_double_gold":5,"items_price":-3}
FLAT={"piercing","burning_spread","knockback"}
PRIMARY={"max_hp","hp_regeneration","armor","melee_damage","percent_damage","lifesteal","crit_chance","attack_speed","ranged_damage","range","elemental_damage","engineering","harvesting","luck","speed","dodge"}
def full(s): return "stat_"+s if s in PRIMARY else s
def v(stat,m):
    if stat in FLAT: return int(m)
    x=T[stat]*m
    r=int(math.floor(abs(x)+0.5))*(1 if x>=0 else -1)
    if r==0: r=1 if x>0 else -1
    return r
# sector: name, primary, secondary, r3 notable, L (stats r4,r5, notable), R, r7, keystone
S=[
 ("Vitality","max_hp","hp_regeneration",
   ("Iron Heart",[("max_hp",4),("armor",1.5)]),
   ("hp_regeneration","max_hp",("Regenerator",[("hp_regeneration",3),("max_hp",2)])),
   ("armor","max_hp",("Bulwark",[("armor",3),("max_hp",2)])),
   "max_hp",
   ("Colossus",[("max_hp",14),("armor",4),("speed",-5),("attack_speed",-3)])),
 ("Melee","melee_damage","percent_damage",
   ("Brawler",[("melee_damage",3),("percent_damage",1.5)]),
   ("lifesteal","melee_damage",("Vampiric Edge",[("lifesteal",3),("melee_damage",2)])),
   ("percent_damage","melee_damage",("Crushing Blows",[("melee_damage",4),("knockback",2)])),
   "melee_damage",
   ("Berserker",[("melee_damage",10),("percent_damage",5),("armor",-5),("dodge",-4)])),
 ("Precision","crit_chance","attack_speed",
   ("Keen Eye",[("crit_chance",2.5),("attack_speed",1.5)]),
   ("crit_chance","crit_chance",("Assassin",[("crit_chance",3),("percent_damage",1.5)])),
   ("attack_speed","attack_speed",("Quickdraw",[("attack_speed",3),("speed",1)])),
   "attack_speed",
   ("Deadeye",[("crit_chance",8),("attack_speed",4),("max_hp",-5),("armor",-3)])),
 ("Ranged","ranged_damage","range",
   ("Marksman",[("ranged_damage",3),("range",1.5)]),
   ("ranged_damage","ranged_damage",("Sharpshooter",[("ranged_damage",5),("percent_damage",1)])),
   ("range","range",("Long Shot",[("range",3),("piercing",1)])),
   "ranged_damage",
   ("Artillery",[("ranged_damage",12),("range",6),("speed",-5),("attack_speed",-3)])),
 ("Elemental","elemental_damage","explosion_damage",
   ("Pyromancer",[("elemental_damage",3),("explosion_damage",1)]),
   ("elemental_damage","elemental_damage",("Inferno",[("elemental_damage",5),("burning_spread",1)])),
   ("explosion_damage","explosion_size",("Demolitionist",[("explosion_damage",2.5),("explosion_size",3)])),
   "elemental_damage",
   ("Elemental Overload",[("elemental_damage",12),("explosion_damage",3),("melee_damage",-4),("ranged_damage",-6)])),
 ("Engineering","engineering","structure_attack_speed",
   ("Tinkerer",[("engineering",2.5),("structure_attack_speed",1.5)]),
   ("engineering","engineering",("Master Builder",[("engineering",3.5),("structure_percent_damage",2)])),
   ("structure_percent_damage","structure_range",("Overclock",[("structure_attack_speed",3),("structure_percent_damage",2)])),
   "engineering",
   ("Mechanist",[("engineering",9),("structure_percent_damage",5),("percent_damage",-2),("attack_speed",-2)])),
 ("Fortune","harvesting","luck",
   ("Prospector",[("harvesting",2),("luck",1.5)]),
   ("luck","luck",("Lucky Charm",[("luck",3),("chance_double_gold",2)])),
   ("harvesting","xp_gain",("Scholar",[("xp_gain",3),("harvesting",1.5)])),
   "luck",
   ("Midas",[("harvesting",6),("luck",5),("items_price",3),("percent_damage",-3)])),
 ("Agility","speed","dodge",
   ("Fleet Foot",[("speed",2),("dodge",1.5)]),
   ("speed","speed",("Windrunner",[("speed",3),("attack_speed",1)])),
   ("dodge","dodge",("Evasion",[("dodge",3),("speed",1)])),
   "speed",
   ("Phantom",[("dodge",7),("speed",5),("max_hp",-5),("hp_regeneration",-1.5)])),
]
nodes=[]; edges=[]
def add(id,ang,r,kind,name,stats,sector):
    a=math.radians(ang)
    nodes.append({"id":id,"x":round(r*math.cos(a)),"y":round(r*math.sin(a)),"kind":kind,"name":name,
                  "stats":[[full(s),v(s,m)] for s,m in stats],"sector":sector})
nodes.append({"id":"start","x":0,"y":0,"kind":0,"name":"Origin","stats":[],"sector":-1})
R=[0,170,290,410,530,640,760,880,1010]
BR=12
for k,(nm,p,s,(n3,st3),L,Rb,p7,(kn,kst)) in enumerate(S):
    base=-90+45*k
    add(f"s{k}_1",base,R[1],1,"",[(p,1.5)],k)
    add(f"s{k}_2",base,R[2],1,"",[(s,1.5)],k)
    add(f"s{k}_3",base,R[3],2,n3,st3,k)
    for side,(a4,a5,(n6,st6)),off in (("L",L,-BR),("R",Rb,BR)):
        add(f"s{k}_{side}4",base+off,R[4],1,"",[(a4,2)],k)
        add(f"s{k}_{side}5",base+off,R[5],1,"",[(a5,2)],k)
        add(f"s{k}_{side}6",base+off,R[6],2,n6,st6,k)
        edges+= [[f"s{k}_3",f"s{k}_{side}4"],[f"s{k}_{side}4",f"s{k}_{side}5"],[f"s{k}_{side}5",f"s{k}_{side}6"],[f"s{k}_{side}6",f"s{k}_7"]]
    add(f"s{k}_7",base,R[7],1,"",[(p7,2.5)],k)
    add(f"s{k}_8",base,R[8],3,kn,kst,k)
    edges+= [["start",f"s{k}_1"],[f"s{k}_1",f"s{k}_2"],[f"s{k}_2",f"s{k}_3"],[f"s{k}_7",f"s{k}_8"]]
for k in range(8):
    j=(k+1)%8; base=-90+45*k+22.5
    pk=S[k][1]; pj=S[j][1]
    add(f"ri{k}",base,R[2]+15,1,"",[(pk,1),(pj,1)],-1)
    edges+= [[f"s{k}_2",f"ri{k}"],[f"ri{k}",f"s{j}_2"]]
    add(f"ro{k}",base,R[5]+20,1,"",[(S[k][5][1],1.5),(S[j][4][1],1.5)],-1)
    edges+= [[f"s{k}_R5",f"ro{k}"],[f"ro{k}",f"s{j}_L5"]]
SECT=[s[0] for s in S]
json.dump({"nodes":nodes,"edges":edges,"sectors":SECT},open(os.path.join(OUT,'tree.json'),'w'),indent=1)
print(len(nodes),"nodes",len(edges),"edges")
# GDScript
def gd(x):
    if isinstance(x,str): return json.dumps(x)
    if isinstance(x,bool): return "true" if x else "false"
    if isinstance(x,(int,float)): return str(x)
    if isinstance(x,list): return "["+", ".join(gd(e) for e in x)+"]"
    if isinstance(x,dict): return "{"+", ".join(f'"{k}": {gd(v)}' for k,v in x.items())+"}"
out=["extends Reference","# Generated by gen_tree.py: node layout and stats of the passive tree.","# kind: 0 = start, 1 = small, 2 = notable, 3 = keystone. Stat values are base values (x Power option).","",
     "const SECTORS := "+gd(SECT),"","const NODES := ["]
for n in nodes: out.append("\t"+gd(n)+",")
out+=["]","","const EDGES := ["]
for e in edges: out.append("\t"+gd(e)+",")
out.append("]")
open(os.path.join(MOD,'tree_data.gd'),'w').write("\n".join(out)+"\n")
