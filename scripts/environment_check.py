#!/usr/bin/env python3
"""Check environment response, exposure, missing resources, and Pack unload."""
import json
from pathlib import Path
import sys
import tempfile

from bridge_check import binary_suffix, check, project, run_game
import bridge


def patch(path, scene, world):
    width, height, pixels = bridge.png_rgba(Path(path).read_bytes())
    x, y = project(scene['camera'], dict(zip(('x','y','z'), world)), (width, height))
    return [sum(pixels[(py*width+px)*4+k] for py in range(y-2,y+3) for px in range(x-2,x+3))/25 for k in range(3)]


def peak(path, scene, world):
    width, height, pixels = bridge.png_rgba(Path(path).read_bytes())
    x, y = project(scene['camera'], dict(zip(('x','y','z'), world)), (width, height))
    edge, _ = project(scene['camera'], {'x': world[0]+.55, 'y': world[1], 'z': world[2]}, (width, height))
    radius=abs(edge-x)
    return max(sum(pixels[(py*width+px)*4:(py*width+px)*4+3])/3
               for py in range(y-radius,y+radius+1) for px in range(x-radius,x+radius+1)
               if (px-x)**2+(py-y)**2<=radius**2)


# The mean of a 5 by 5 patch at a share of the width and height.
def screen_patch(path, fx, fy):
    width, height, pixels = bridge.png_rgba(Path(path).read_bytes())
    x, y = int(fx*width), int(fy*height)
    return [sum(pixels[(py*width+px)*4+k] for py in range(y-2,y+3) for px in range(x-2,x+3))/25 for k in range(3)]


def warmth(rgb):
    return rgb[0]-rgb[2]


def drive(b, out):
    b.hello()
    b.step(1)
    scene=b.scene()['scene']
    check(scene['nodes'][0]['Draw']['mesh']!=0,'reference surfaces loaded')
    root=Path(out).parent
    def shot(name):
        path=str(root/(name+'.png')); b.screenshot(path); return path
    warm=shot('warm')
    b.step(1,tap=['S']); cool=shot('cool')
    points=[((col-1.5)*1.7,1.6-row*1.7,.6) for row in range(2) for col in range(4)]
    changes=[]
    for point in points:
        a,c=patch(warm,scene,point),patch(cool,scene,point)
        check(a[0]>a[2]+8 and c[2]>c[0]+8,'both material rows follow the cubemap colour')
        changes.append(max(abs(x-y) for x,y in zip(a,c)))
    peaks=[peak(warm,scene,((col-1.5)*1.7,-.1,0)) for col in range(4)]
    check(all(a>b+15 for a,b in zip(peaks,peaks[1:])),'roughness reduces the metal reflection peak')
    reference=(-3,-1.1,0)
    check(patch(warm,scene,reference)==patch(cool,scene,reference),'unlit reference keeps its authored colour')
    b.step(1,tap=['E']); exposed=shot('exposure')
    check(sum(patch(exposed,scene,reference))>sum(patch(cool,scene,reference))+30,'exposure applies after lighting')
    b.step(1,tap=['E']); b.step(1,tap=['N']); none=shot('none')
    for point in points:
        check(max(patch(none,scene,point))<2,'absent sky contributes no lighting')
    b.step(1,tap=['S']); b.step(1,tap=['U']); unloaded=shot('unloaded')
    check(Path(none).read_bytes()==Path(unloaded).read_bytes(),'unloaded sky removes background and lighting together')
    b.step(1,tap=['R']); restored=shot('restored')
    check(Path(warm).read_bytes()==Path(restored).read_bytes(),'Pack reload restores the complete environment')
    b.step(1,tap=['B']); half=shot('blend-half')
    for point in points:
        w,h,c=(warmth(patch(path,scene,point)) for path in (warm,half,cool))
        check(min(w,c)+5<h<max(w,c)-5,f'a lit surface at {point} blends between the skies: {w:.0f}, {h:.0f}, {c:.0f}')
    sky=[warmth(screen_patch(path,0.05,0.02)) for path in (warm,half,cool)]
    check(sky[0]>30 and sky[2]<-30 and abs(sky[1])<20,f'the background blends with the light: {sky}')
    b.step(1,tap=['B']); full=shot('blend-full')
    check(Path(full).read_bytes()==Path(cool).read_bytes(),'a blend of 1 draws the second sky alone')
    b.step(1,tap=['B']); b.step(1,tap=['F']); fogged=shot('sky-fog')
    horizon=max(abs(x-y) for x,y in zip(screen_patch(fogged,0.05,0.5),screen_patch(warm,0.05,0.5)))
    top=max(abs(x-y) for x,y in zip(screen_patch(fogged,0.05,0.02),screen_patch(warm,0.05,0.02)))
    check(horizon>100 and top<horizon/2,f'sky fog is strongest at the horizon: {horizon:.0f} there, {top:.0f} at the top')
    b.quit()
    (root/'environment-evidence.json').write_text(json.dumps({'material_colour_changes':changes,'reference':patch(warm,scene,reference),'metal_reflection_peaks':peaks,'result':'passed'},indent=2)+'\n')


def main():
    out=Path(sys.argv[1] if len(sys.argv)>1 else 'build/environment-check/reference.png').resolve()
    out.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        run_game('environment-lighting',drive,str(out),tmp,binary_suffix())
        log=Path(tmp,'environment-lighting.log').read_text(errors='replace')
        out.with_name('environment-native.log').write_text(log)
        check('[sg][error]' not in log and '[sg][panic]' not in log,'the graphics log has no errors')

if __name__=='__main__':main()
