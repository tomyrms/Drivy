import math
def f(v): return f"{v:.2f}".rstrip('0').rstrip('.')
def pt(cx,cy,r,a):
    t=math.radians(a); return cx+r*math.sin(t), cy-r*math.cos(t)
def arc_band(cx,cy,r,w,a0,a1,caps=True):
    """Bande d'arc épaisse w, centrée sur le rayon r, de a0 à a1 (degrés, sens horaire depuis le haut)."""
    ro,ri=r+w/2,r-w/2; large=1 if (a1-a0)%360>180 else 0
    x0,y0=pt(cx,cy,ro,a0); x1,y1=pt(cx,cy,ro,a1); x2,y2=pt(cx,cy,ri,a1); x3,y3=pt(cx,cy,ri,a0)
    c=w/2
    d=f"M{f(x0)} {f(y0)}A{f(ro)} {f(ro)} 0 {large} 1 {f(x1)} {f(y1)}"
    d+= f"A{f(c)} {f(c)} 0 0 1 {f(x2)} {f(y2)}" if caps else f"L{f(x2)} {f(y2)}"
    d+=f"A{f(ri)} {f(ri)} 0 {large} 0 {f(x3)} {f(y3)}"
    d+= f"A{f(c)} {f(c)} 0 0 1 {f(x0)} {f(y0)}Z" if caps else "Z"
    return d
def circle(cx,cy,r,ccw=False):
    s=0 if ccw else 1
    return f"M{f(cx-r)} {f(cy)}A{f(r)} {f(r)} 0 1 {s} {f(cx+r)} {f(cy)}A{f(r)} {f(r)} 0 1 {s} {f(cx-r)} {f(cy)}Z"
def capsule(x1,y1,x2,y2,w):
    r=w/2; dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy); nx,ny=-dy/L*r,dx/L*r
    return (f"M{f(x1+nx)} {f(y1+ny)}L{f(x2+nx)} {f(y2+ny)}A{f(r)} {f(r)} 0 0 0 {f(x2-nx)} {f(y2-ny)}"
            f"L{f(x1-nx)} {f(y1-ny)}A{f(r)} {f(r)} 0 0 0 {f(x1+nx)} {f(y1+ny)}Z")
def svg(name,d,size=256,title=""):
    open(name,"w",encoding="utf-8").write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 64 64"><title>{title}</title><path fill="#000" fill-rule="nonzero" d="{d}"/></svg>\n')

# A — Volant-anneau : le volant dont la jante est un anneau de progression (deux tiers pleins, le reste en fin rail).
cx,cy=32,32
A=[arc_band(cx,cy,25,7,-10,220),            # jante parcourue, épaisse
   arc_band(cx,cy,25,2.6,232,338),          # reste du tour, rail fin
   circle(cx,cy,6.5),                        # moyeu
   capsule(cx-6,cy+1,cx-21,cy+1,5.2), capsule(cx+6,cy+1,cx+21,cy+1,5.2), capsule(cx,cy+6,cx,cy+21,5.2)]
svg("v2/a-volant.svg"," ".join(A),title="Volant-anneau")

# B — Jauge : un compteur en trois paliers (découverte, accompagnement, autonomie), l’aiguille sur le deuxième.
cx,cy=32,38
segs=[(-118,-46),(-36,36),(46,118)]
B=[arc_band(cx,cy,23,8,*segs[0]),arc_band(cx,cy,23,8,*segs[1])]
# troisième palier évidé : contour d’épaisseur 2.6
a0,a1=segs[2]; B.append(arc_band(cx,cy,26.7,2.6,a0+3,a1-3)); B.append(arc_band(cx,cy,19.3,2.6,a0+5,a1-5,))
nx,ny=pt(cx,cy,17,20)
B.append(capsule(cx,cy,nx,ny,4.6)); B.append(circle(cx,cy,5.6))
svg("v2/b-jauge.svg"," ".join(B),title="Jauge en trois paliers")

# C — Drapeau d’arrivée : une route qui monte en virage jusqu’au drapeau à damier.
C=[]
# mât
C.append(capsule(41,10,41,34,3.6))
# drapeau 2x3 damier : cases pleines alternées dans un cadre
fx,fy,cw,ch=42.5,9.5,5.5,4.6
C.append(f"M{fx} {fy}h{3*cw}v{2*ch}h{-3*cw}Z")  # cadre plein
holes=[(1,0),(0,1),(2,1)]
for (i,j) in holes:
    x=fx+i*cw; y=fy+j*ch
    C.append(f"M{f(x)} {f(y)}v{ch}h{cw}v{-ch}Z")  # sens inverse = trou (nonzero)
# route : bande courbe épaisse de bas-gauche vers le pied du mât
road="M8 56C18 56 18 42 28 40S38 36 40 35.5"
open("v2/c-road.d","w").write(road)
svg("v2/c-drapeau-flag.svg"," ".join(C),title="Drapeau d’arrivée")
import math, sys
sys.path.insert(0,"v2")
from build import arc_band, circle, capsule, pt, f
def svg(name,shapes,size=256,title=""):
    body="".join(f'<path d="{d}"/>' for d in shapes)
    open(name,"w",encoding="utf-8").write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 64 64"><title>{title}</title><g fill="#000">{body}</g></svg>\n')
W, RAIL = 6.5, 2.8   # poids plein (atteint) et rail (à venir)

# A — Volant-anneau
cx,cy,r=32,32,24.5
A=[arc_band(cx,cy,r,RAIL,0,360,caps=False) if False else "",
   arc_band(cx,cy,r,RAIL,95,205), arc_band(cx,cy,r,W,205,455)]
A=[a for a in A if a]
A+= [capsule(cx-r+2,cy+2,cx+r-2,cy+2,5.6), capsule(cx,cy+2,cx,cy+r-2,5.6), circle(cx,cy+2,7.5)]
svg("v2/a-volant.svg",A,title="Volant-anneau")

# B — Jauge en trois paliers
cx,cy,r=32,40,22
B=[arc_band(cx,cy,r,W+1,-120,-52), arc_band(cx,cy,r,W+1,-34,34), arc_band(cx,cy,r,RAIL,52,120)]
nx,ny=pt(cx,cy,15.5,22)
B+= [capsule(cx,cy,nx,ny,4.2), circle(cx,cy,5.5)]
svg("v2/b-jauge.svg",B,title="Jauge en trois paliers")

# C — Chevrons : trois rangs, deux atteints, le dernier à venir
def chevron(y,w,half=17,h=11):
    return [capsule(32-half,y,32,y-h,w), capsule(32,y-h,32+half,y,w)]
C= chevron(54,W)+chevron(39,W)+chevron(24,RAIL)
svg("v2/c-chevrons.svg",C,title="Trois rangs")
import sys; sys.path.insert(0,"v2")
from build import arc_band, circle, capsule
from build2 import svg, W, RAIL
cx,cy,r=32,32,24.5
A=[arc_band(cx,cy,r,3.4,58,165), arc_band(cx,cy,r,W,196,402),
   capsule(cx-r+2,cy,cx+r-2,cy,5.4), capsule(cx,cy,cx,cy+r-2,5.4), circle(cx,cy,7)]
svg("v2/a-volant-v2.svg",A,title="Volant-anneau")
svg("v2/a-volant-26.svg",A,size=26,title="Progression — volant-anneau")
