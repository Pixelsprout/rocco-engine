#!/usr/bin/env python3
"""Check runtime Surface packages, slot changes, wind, shadows, and Pack invalidation."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

import bridge
from bridge_check import binary_suffix, check, project


def pixels(path):
    return bridge.png_rgba(Path(path).read_bytes())[2]


def green(path):
    data = pixels(path)
    return sum(g > r * 1.3 and g > b * 1.2 and g > 30 for r, g, b in zip(data[0::4], data[1::4], data[2::4]))


def dark_shadow(path):
    data = pixels(path)
    return sum(max(r,g,b)-min(r,g,b)<35 and 20<(r+g+b)/3<90 for r,g,b in zip(data[0::4],data[1::4],data[2::4]))


def patch(path, scene, point):
    width,height,data=bridge.png_rgba(Path(path).read_bytes())
    x,y=project(scene['camera'],dict(zip(('x','y','z'),point)),(width,height))
    return bytes(data[(py*width+px)*4+k] for py in range(y-2,y+3) for px in range(x-2,x+3) for k in range(3))


def run(label, args, output, drive, expected_failure=False):
    port=bridge.free_port()
    binary=Path('examples/surface/surface'+binary_suffix()).resolve()
    log_path=output/(label+'.log')
    command=shlex.split(os.environ.get('RUN_PREFIX',''))+[str(binary),*args]
    with log_path.open('w') as log:
        process=subprocess.Popen(command,cwd=binary.parent,env=dict(os.environ,ROCCO_BRIDGE=str(port)),stdout=log,stderr=subprocess.STDOUT)
        try:
            with bridge.Bridge.connect(port,wait=60) as driver:
                driver.hello()
                result=drive(driver,lambda name: shot(driver,output/(label+'-'+name+'.png')))
                driver.quit()
            check(process.wait(timeout=20)==0,'Surface game exits after quit')
        finally:
            if process.poll() is None:
                process.terminate();process.wait(timeout=20)
    text=log_path.read_text(errors='replace')
    check('[sg][error]' not in text and '[sg][panic]' not in text and 'VALIDATION_FAILED' not in text,'Surface native graphics validation')
    if expected_failure:
        check('incompatible shader contract' in text,'invalid version logs the contract failure')
    else:
        check('failed GPU' not in text and 'pipeline creation' not in text,'Surface variants and pipelines load')
    return result


def shot(driver,path):
    driver.screenshot(str(path))
    return path


def wind(driver,shot):
    driver.step(1);a=shot('1')
    driver.step(59);b=shot('60')
    driver.step(60);c=shot('120')
    check(green(a)>1000,'named leaf slot keeps imported material and cutouts')
    check(pixels(a)!=pixels(b) and pixels(b)!=pixels(c),'simulation steps change the wind pose')
    return [hashlib.sha256(pixels(p)).hexdigest() for p in (a,b,c)]


def controls(driver,shot):
    driver.step(1);base=shot('base');scene=driver.scene()['scene']
    driver.step(1,tap=['C']);red=shot('red')
    check(green(red)<green(base)/4,'generated leaf values change only the named Surface')
    check(patch(base,scene,(0,.4,.13))==patch(red,scene,(0,.4,.13)),'the unassigned bark material stays unchanged')
    driver.step(1,tap=['C']);normal=shot('normal')
    check(pixels(base)==pixels(normal),'equal material values restore the frame')
    driver.step(1,tap=['N']);no_shadow=shot('no-shadow')
    check(green(no_shadow)>1000,'a non-casting Surface stays in colour rendering')
    check(dark_shadow(base)>100 and dark_shadow(no_shadow)<dark_shadow(base)/3,'per-Draw casting removes the cutout shadow')
    driver.step(1,tap=['N']);driver.step(1,tap=['U']);unloaded=shot('unloaded')
    check(green(unloaded)==0,'Shader Pack unload omits the affected leaf part')
    check(patch(base,scene,(0,.4,.13))==patch(unloaded,scene,(0,.4,.13)),'Shader Pack unload preserves the separate Mesh Pack')
    driver.step(1,tap=['U']);restored=shot('restored')
    check(pixels(base)==pixels(restored),'Shader Pack reload restores the complete material generation')
    return dict(base_green=green(base),unloaded_green=green(unloaded),shadow_pixels=dark_shadow(base),noncasting_shadow_pixels=dark_shadow(no_shadow))


def single(driver,shot):
    driver.step(1)
    return shot('frame')


def main():
    out=Path(sys.argv[1] if len(sys.argv)>1 else 'build/surface-check').resolve();out.mkdir(parents=True,exist_ok=True)
    a=run('wind-a',[],out,wind);b=run('wind-b',[],out,wind)
    check(a==b,'equal Bridge steps reproduce equal Surface poses and shadows')
    instances_a=run('instances-a',['--instances'],out,wind);instances_b=run('instances-b',['--instances'],out,wind)
    check(instances_a==instances_b,'compatible transforms and tints repeat with separate Draw phase values')
    result=run('controls',['--no-wind'],out,controls)
    builtin=run('builtin',['--builtin','--no-wind'],out,single)
    default=run('default',['--default-shader','--no-wind'],out,single)
    x,y=pixels(builtin),pixels(default)
    differences=[abs(a-b) for i,(a,b) in enumerate(zip(x,y)) if i%4!=3]
    mean=sum(differences)/len(differences)
    check(mean<.2 and sum(d>2 for d in differences)<len(differences)*.005,'empty Surface hooks retain built-in PBR')
    broken_path=Path('examples/surface/assets/shaders/Broken.shaderpack')
    data=bytearray(Path('examples/surface/assets/shaders/Foliage.shaderpack').read_bytes());data[10:12]=(2).to_bytes(2,'little')
    broken_path.write_bytes(data)
    try:
        broken=run('invalid-version',['--broken','--no-wind'],out,single,expected_failure=True)
        check(green(broken)==0,'invalid first-load versions omit the leaf Surface')
        data=pixels(broken)
        check(not any(r>200 and b>200 and g<30 for r,g,b in zip(data[0::4],data[1::4],data[2::4])),'failed shaders never select a fallback material')
    finally:
        broken_path.unlink()
    result.update(result='passed',wind_hashes=a,instance_wind_hashes=instances_a,default_pbr_mean_difference=mean,binary_sha256=hashlib.sha256(Path('examples/surface/surface'+binary_suffix()).read_bytes()).hexdigest(),packages={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in Path('examples/surface/assets/shaders').glob('*.shaderpack')})
    (out/'surface-evidence.json').write_text(json.dumps(result,indent=2)+'\n')


if __name__=='__main__':main()
