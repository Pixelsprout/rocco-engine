#!/usr/bin/env python3
"""Prepare the environment reference without external asset tools."""
import json
import math
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
FACES = {'px': lambda u,v:(1,-v,-u), 'nx':lambda u,v:(-1,-v,u),
         'py':lambda u,v:(u,1,v), 'ny':lambda u,v:(u,-1,-v),
         'pz':lambda u,v:(u,-v,1), 'nz':lambda u,v:(-u,-v,-1)}

def png(path, side, pixels):
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    raw=b''.join(b'\0'+pixels[y*side*3:(y+1)*side*3] for y in range(side))
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',side,side,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))

for theme in ('warm','cool'):
    for face,direction in FACES.items():
        pixels=bytearray()
        for y in range(256):
            for x in range(256):
                d=direction(2*(x+.5)/256-1,2*(y+.5)/256-1)
                norm=math.sqrt(sum(c*c for c in d)); d=[c/norm for c in d]
                up=max(0,d[1]); disc=max(0,1-((d[0]-.4)**2+(d[1]-.6)**2+(d[2]-.7)**2)/.06)
                rgb=[.07+.22*up+.65*disc,.045+.16*up+.65*disc,.025+.08*up+.65*disc]
                if theme=='cool': rgb=rgb[::-1]
                pixels.extend(round(255*(12.92*c if c<=.0031308 else 1.055*c**(1/2.4)-.055)) for c in rgb)
        png(ROOT/'sky'/theme/(face+'.png'),256,pixels)

blob=bytearray(); views=[]; accessors=[]; primitives=[]; materials=[]
def accessor(data, components, kind, component_type):
    while len(blob)%4:blob.append(0)
    offset=len(blob);blob.extend(data)
    views.append({'buffer':0,'byteOffset':offset,'byteLength':len(data)})
    accessors.append({'bufferView':len(views)-1,'componentType':component_type,'count':len(data)//(components*(2 if component_type==5123 else 4)),'type':kind})
    return len(accessors)-1
for row in range(2):
    for col,roughness in enumerate((.05,.25,.5,1)):
        positions=[];normals=[];indices=[]
        for lat in range(25):
            theta=math.pi*lat/24
            for lon in range(49):
                phi=2*math.pi*lon/48
                n=(math.sin(theta)*math.cos(phi),math.cos(theta),math.sin(theta)*math.sin(phi))
                positions.extend((n[0]*.65+(col-1.5)*1.7,n[1]*.65+1.6-row*1.7,n[2]*.65))
                normals.extend(n)
        for lat in range(24):
            for lon in range(48):
                a=lat*49+lon;b=a+49
                indices.extend((a,a+1,b,a+1,b+1,b))
        p=accessor(struct.pack('<%sf'%len(positions),*positions),3,'VEC3',5126)
        n=accessor(struct.pack('<%sf'%len(normals),*normals),3,'VEC3',5126)
        i=accessor(struct.pack('<%sH'%len(indices),*indices),1,'SCALAR',5123)
        materials.append({'name':f'{"metal" if row else "diffuse"}_{roughness}','pbrMetallicRoughness':{'baseColorFactor':[.65,.65,.65,1],'metallicFactor':row,'roughnessFactor':roughness}})
        primitives.append({'attributes':{'POSITION':p,'NORMAL':n},'indices':i,'material':len(materials)-1})
# Unlit white reference keeps exposure independent of the selected environment.
materials.append({'name':'unlit_reference','extensions':{'KHR_materials_unlit':{}},'pbrMetallicRoughness':{'baseColorFactor':[.5,.5,.5,1]}})
p=accessor(struct.pack('<12f',-3.2,-1.3,0,-2.8,-1.3,0,-2.8,-.9,0,-3.2,-.9,0),3,'VEC3',5126)
n=accessor(struct.pack('<12f',*(0,0,1)*4),3,'VEC3',5126)
i=accessor(struct.pack('<6H',0,1,2,0,2,3),1,'SCALAR',5123)
primitives.append({'attributes':{'POSITION':p,'NORMAL':n},'indices':i,'material':8})
doc={'asset':{'version':'2.0'},'extensionsUsed':['KHR_materials_unlit'],'buffers':[{'byteLength':len(blob)}],'bufferViews':views,'accessors':accessors,'materials':materials,'meshes':[{'primitives':primitives}],'nodes':[{'mesh':0}],'scenes':[{'nodes':[0]}],'scene':0}
metadata=json.dumps(doc,separators=(',',':')).encode();metadata+=b' '*((-len(metadata))%4);blob+=b'\0'*((-len(blob))%4)
out=struct.pack('<III',0x46546c67,2,28+len(metadata)+len(blob))+struct.pack('<II',len(metadata),0x4e4f534a)+metadata+struct.pack('<II',len(blob),0x004e4942)+blob
(ROOT/'meshes').mkdir(exist_ok=True)
(ROOT/'meshes'/'reference.glb').write_bytes(out)
