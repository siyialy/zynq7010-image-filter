from pathlib import Path
from PIL import Image, ImageOps, ImageDraw

source = next(p for p in Path('D:/').glob('IMG_20261024_120056*') if p.is_dir())
files = sorted(source.glob('*.jpg'))
out = Path(__file__).parent / 'image_review'
out.mkdir(exist_ok=True)
for start in (0, 12):
    canvas = Image.new('RGB', (1600, 1380), '#eeeeee')
    draw = ImageDraw.Draw(canvas)
    for j, f in enumerate(files[start:start + 12]):
        im = ImageOps.exif_transpose(Image.open(f))
        print(start+j+1, f.name, im.size)
        im.thumbnail((390, 410))
        x, y = (j % 4) * 400, (j // 4) * 460
        canvas.paste(im, (x + (400-im.width)//2, y+30))
        draw.text((x+8, y+8), f'{start+j+1}  {f.stem}', fill='black')
    canvas.save(out / f'sheet_{start+1}.jpg')
