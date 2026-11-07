#!/usr/bin/env python3
"""Build the small two-slot Surface fixture without external asset tools."""
import json
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
binary = bytearray()
views, accessors = [], []
def data(values, kind, shape, target=None):
    while len(binary) % 4: binary.append(0)
    start = len(binary)
    binary.extend(struct.pack('<' + kind * len(values), *values))
    view = dict(buffer=0, byteOffset=start, byteLength=len(binary)-start)
    if target: view['target'] = target
    views.append(view)
    count = {'VEC2':2, 'VEC3':3, 'VEC4':4, 'SCALAR':1}[shape]
    accessors.append(dict(bufferView=len(views)-1, componentType=5126 if kind=='f' else 5123, count=len(values)//count, type=shape))
    return len(accessors)-1

def primitive(vertices, normals, uv, colours, indices, material):
    return dict(attributes=dict(POSITION=data(vertices,'f','VEC3',34962), NORMAL=data(normals,'f','VEC3',34962), TEXCOORD_0=data(uv,'f','VEC2',34962), COLOR_0=data(colours,'f','VEC4',34962)), indices=data(indices,'H','SCALAR',34963), material=material)

pos, normal, uv, colour, indices = [], [], [], [], []
for n, corners in [((0,0,1),[(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]), ((0,0,-1),[(1,-1,-1),(-1,-1,-1),(-1,1,-1),(1,1,-1)]), ((1,0,0),[(1,-1,1),(1,-1,-1),(1,1,-1),(1,1,1)]), ((-1,0,0),[(-1,-1,-1),(-1,-1,1),(-1,1,1),(-1,1,-1)]), ((0,1,0),[(-1,1,1),(1,1,1),(1,1,-1),(-1,1,-1)]), ((0,-1,0),[(-1,-1,-1),(1,-1,-1),(1,-1,1),(-1,-1,1)])]:
    at=len(pos)//3
    for x,y,z in corners: pos.extend((x*.12,(y+1)*.9,z*.12)); normal.extend(n); colour.extend((1,1,1,1))
    uv.extend((0,1,1,1,1,0,0,0)); indices.extend(at+i for i in (0,1,2,0,2,3))
trunk=primitive(pos,normal,uv,colour,indices,0)
pos, normal, uv, colour, indices = [], [], [], [], []
for axis in (0,1):
    at=len(pos)//3
    for x,y in [(-1,1),(1,1),(1,3),(-1,3)]:
        pos.extend((x if axis==0 else 0,y,x if axis==1 else 0)); normal.extend((0,0,1) if axis==0 else (1,0,0)); colour.extend(((y-1)/2,1,1,1))
    uv.extend((0,1,1,1,1,0,0,0)); indices.extend(at+i for i in (0,1,2,0,2,3))
leaves=primitive(pos,normal,uv,colour,indices,1)

def chunk(name, value): return struct.pack('>I',len(value))+name+value+struct.pack('>I',zlib.crc32(name+value)&0xffffffff)
size=64
pixels=bytearray()
for y in range(size):
    pixels.append(0)
    for x in range(size):
        u,v=(x+.5)/size*2-1,(y+.5)/size*2-1
        alpha=255 if u*u+v*v*.5 < .85 and ((x//8+y//8)%4!=0) else 0
        pixels.extend((255,255,255,alpha))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b'')
while len(binary)%4:binary.append(0)
views.append(dict(buffer=0,byteOffset=len(binary),byteLength=len(png))); binary.extend(png)
gltf=dict(asset=dict(version='2.0'),scene=0,scenes=[dict(nodes=[0])],nodes=[dict(mesh=0)],meshes=[dict(primitives=[trunk,leaves])],materials=[dict(name='Bark',pbrMetallicRoughness=dict(baseColorFactor=[.42,.19,.06,1],metallicFactor=0,roughnessFactor=.9)),dict(name='Leaves',alphaMode='MASK',alphaCutoff=.45,doubleSided=True,pbrMetallicRoughness=dict(baseColorFactor=[.2,.65,.12,1],baseColorTexture=dict(index=0),metallicFactor=0,roughnessFactor=.8))],textures=[dict(source=0)],images=[dict(bufferView=len(views)-1,mimeType='image/png')],buffers=[dict(byteLength=len(binary))],bufferViews=views,accessors=accessors)
metadata=json.dumps(gltf,separators=(',',':')).encode();metadata+=b' '*((-len(metadata))%4);binary+=b'\x00'*((-len(binary))%4)
blob=struct.pack('<III',0x46546c67,2,12+8+len(metadata)+8+len(binary))+struct.pack('<II',len(metadata),0x4e4f534a)+metadata+struct.pack('<II',len(binary),0x004e4942)+binary
(ROOT/'assets/meshes/tree.glb').write_bytes(blob)
