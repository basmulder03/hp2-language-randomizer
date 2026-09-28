"""Generate the language-settings menu icon (idle + rollover) for FEInGamePage.

Drawn to match the stock HP2_Menu.Icons style (64x64 RGBA, art in the
top-left 48x48: gold ring around a
dark navy disc, symbol overlapping the rim, soft drop shadow): two overlapping
speech bubbles. Output goes to assets/build/icons/, which is deployed to
$GAMEDIR/HGame/Textures/LangPicker/ and imported by MenuIcons.uc.

Usage: python3 tools/scripts/generate_menu_icons.py
"""
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT_DIR = REPO / "assets/build/icons"

from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math
S=8; N=64*S
def radial(size, stops, center, radius):
    im=Image.new('RGBA',(size,size))
    px=im.load(); cx,cy=center
    for y in range(size):
        for x in range(size):
            t=min(1.0,math.hypot(x-cx,y-cy)/radius)
            for (t0,c0),(t1,c1) in zip(stops,stops[1:]):
                if t0<=t<=t1:
                    f=(t-t0)/(t1-t0) if t1>t0 else 0
                    px[x,y]=tuple(int(c0[i]+(c1[i]-c0[i])*f) for i in range(3))+(255,)
                    break
    return im
def lin(w,h,c0,c1):
    im=Image.new('RGBA',(w,h)); d=ImageDraw.Draw(im)
    for y in range(h):
        f=y/(h-1); d.line([(0,y),(w,y)],fill=tuple(int(c0[i]+(c1[i]-c0[i])*f) for i in range(3))+(255,))
    return im
def build(bright=1.0):
    out=Image.new('RGBA',(N,N),(0,0,0,0))
    c=N/2; R=26*S; r=21*S
    # drop shadow
    sh=Image.new('L',(N,N),0); ImageDraw.Draw(sh).ellipse([c-R+2*S,c-R+3*S,c+R+2*S,c+R+3*S],fill=170)
    sh=sh.filter(ImageFilter.GaussianBlur(2*S))
    out.paste(Image.new('RGBA',(N,N),(0,0,0,255)),(0,0),sh)
    # gold ring: lit from top-left
    m=Image.new('L',(N,N),0); ImageDraw.Draw(m).ellipse([c-R-S,c-R-S,c+R+S,c+R+S],fill=255)
    out.paste(Image.new('RGBA',(N,N),(40,24,4,255)),(0,0),m)
    gold=lin(N,N,(255,226,120),(120,78,16))
    m=Image.new('L',(N,N),0); ImageDraw.Draw(m).ellipse([c-R,c-R,c+R,c+R],fill=255)
    out.paste(gold,(0,0),m)
    # inner bevel: dark rim then navy disc
    m=Image.new('L',(N,N),0); ImageDraw.Draw(m).ellipse([c-r-S,c-r-S,c+r+S,c+r+S],fill=255)
    out.paste(lin(N,N,(90,60,10),(230,190,90)),(0,0),m)
    navy=radial(N,[(0,(58,70,120)),(0.6,(30,36,70)),(1,(12,14,32))],(c-6*S,c-8*S),r*1.4)
    m=Image.new('L',(N,N),0); ImageDraw.Draw(m).ellipse([c-r,c-r,c+r,c+r],fill=255)
    out.paste(navy,(0,0),m)
    d=ImageDraw.Draw(out)
    def bubble(box,tail,fill_top,fill_bot,outline):
        x0,y0,x1,y1=box
        mk=Image.new('L',(N,N),0); md=ImageDraw.Draw(mk)
        md.rounded_rectangle(box,radius=5*S,fill=255); md.polygon(tail,fill=255)
        # outline by dilating
        ol=mk.filter(ImageFilter.MaxFilter(2*S+1))
        out.paste(Image.new('RGBA',(N,N),outline+(255,)),(0,0),ol)
        out.paste(lin(N,N,fill_top,fill_bot),(0,0),mk)
    # back bubble (gold, right), front bubble (parchment, left)
    bubble((30*S,12*S,56*S,34*S),[(46*S,33*S),(52*S,42*S),(40*S,33*S)],(255,222,110),(190,140,40),(60,38,6))
    bubble((8*S,24*S,38*S,48*S),[(15*S,47*S),(11*S,56*S),(23*S,47*S)],(250,244,220),(214,196,150),(60,38,6))
    # text lines on the parchment bubble, and dots on the gold one
    for i,y in enumerate((31,36,41)):
        d.rounded_rectangle([13*S,y*S,(33-(i==2)*7)*S,(y+2)*S],radius=S,fill=(120,95,60,255))
    for x in (37,43,49):
        d.ellipse([x*S,21*S,(x+3)*S,24*S],fill=(90,60,10,255))
    # Stock HP2_Menu icons only use the top-left 48x48 of their 64x64
    # texture (HGameButton draws that region into its 48x48 button), so
    # scale the art to 48x48 and leave the rest transparent.
    im=Image.new('RGBA',(64,64),(0,0,0,0))
    im.paste(out.resize((48,48),Image.LANCZOS),(0,0))
    if bright!=1.0:
        r,g,b,a=im.split()
        r,g,b=[ch.point(lambda v:min(255,int(v*bright+18))) for ch in (r,g,b)]
        im=Image.merge('RGBA',(r,g,b,a))
    return im

def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    build().save(OUT_DIR / "HP2MenuLanguages.png")
    build(1.18).save(OUT_DIR / "HP2MenuLanguagesOver.png")
    print(f"wrote {OUT_DIR}")


if __name__ == "__main__":
    main()
