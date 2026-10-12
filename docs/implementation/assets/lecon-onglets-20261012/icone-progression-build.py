import math
def capsule(x1,y1,x2,y2,w):
    r=w/2; dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy); nx,ny=-dy/L*r,dx/L*r
    f=lambda v:f"{v:.2f}".rstrip('0').rstrip('.')
    return (f"M{f(x1+nx)} {f(y1+ny)}L{f(x2+nx)} {f(y2+ny)}A{f(r)} {f(r)} 0 0 0 {f(x2-nx)} {f(y2-ny)}"
            f"L{f(x1-nx)} {f(y1-ny)}A{f(r)} {f(r)} 0 0 0 {f(x1+nx)} {f(y1+ny)}Z")
def circle(cx,cy,r):
    return f"M{cx-r} {cy}A{r} {r} 0 1 0 {cx+r} {cy}A{r} {r} 0 1 0 {cx-r} {cy}Z"
d=" ".join([capsule(7,58,25,7,4.5),capsule(57,58,39,7,4.5),capsule(32,57,32,42.5,4.5),
            circle(32,30,7),circle(32,18,2.25),circle(32,10,2)])
for name,size,fill in [("c-route-final.svg",256,"#000"),("progress.svg",26,"#000")]:
    open(name,"w",encoding="utf-8").write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 64 64" role="img"><title>Progression — route parcourue</title><path fill="{fill}" d="{d}"/></svg>\n')
