from pathlib import Path
import random

root = Path(__file__).resolve().parent
rng = random.Random(1065)
width, height, frames = 64, 24, 8
images = []
for f in range(frames):
    image = []
    for y in range(height):
        for x in range(width):
            if f == 0:
                pixel = (17, 17, 17)
            elif f == 1:
                pixel = (255, 255, 255) if x % 2 else (0, 0, 0)
            elif f == 2:
                pixel = (x * 4, y * 10, (x + y) % 256)
            else:
                pixel = tuple(rng.randrange(256) for _ in range(3))
            image.append(pixel)
    images.append(image)

gray_images = [[(77*r + 150*g + 29*b)//256 for r,g,b in im] for im in images]
maps = []
for im in gray_images:
    hist = [im.count(v) for v in range(256)]
    cumulative = 0
    lut = []
    for count in hist:
        cumulative += count
        lut.append(cumulative * 255 // len(im))
    maps.append(lut)

def pack(pixels):
    return sum(((r << 16) | (g << 8) | b) << (24*p) for p,(r,g,b) in enumerate(pixels))

inputs, grays, equal, gaussian, flags = [], [], [], [], []
for f, im in enumerate(images):
    mapping_frame = None if f < 2 else f-2 if f < 6 else f-1
    for index in range(0, len(im), 4):
        gs = gray_images[f][index:index+4]
        es = gs if mapping_frame is None else [maps[mapping_frame][g] for g in gs]
        inputs.append(f'{pack(im[index:index+4]):024x}')
        grays.append(f'{pack([(g,g,g) for g in gs]):024x}')
        equal.append(f'{pack([(g,g,g) for g in es]):024x}')
        filtered = []
        for at in range(index,index+4):
            yy,xx=divmod(at,width)
            weighted = 0
            for dy,wy in [(-1,1),(0,2),(1,1)]:
                for dx,wx in [(-1,1),(0,2),(1,1)]:
                    sy=min(height-1,max(0,yy+dy))
                    sx=min(width-1,max(0,xx+dx))
                    weighted += wy*wx*gray_images[f][sy*width+sx]
            filtered.append(weighted//16)
        gaussian.append(f'{pack([(g,g,g) for g in filtered]):024x}')
        flags.append(f'{(2 if index == 0 else 0) | (1 if index % width == width-4 else 0):x}')
for name, values in [('input',inputs),('gray',grays),('equal',equal),('gaussian',gaussian),('flags',flags)]:
    (root/f'{name}.hex').write_text('\n'.join(values)+'\n', encoding='ascii')
print(f'Independent RGB/luma/CDF reference: {frames} frames, {len(inputs)*4} pixels')
