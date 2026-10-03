#!/usr/bin/env python3
"""Export installed Friday PNG animations as looping transparent GIF assets."""
from pathlib import Path
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'Resources/characters/friday'
OUT = ROOT / 'artwork/friday-action-v2/gifs'
CLIPS = ('home_waking_up', 'home_cooking_stir', 'home_sweeping',
         'home_watering_plants', 'home_hanging_laundry')


def export(clip):
    files = sorted((PACK / clip).glob('*.png'))
    frames = [Image.open(p).convert('RGBA') for p in files]
    assert len(frames) == 60
    assert all(im.size == (960, 1040) for im in frames)
    # Build one palette from all six poses; reserve entry255 for transparency.
    contact = Image.new('RGB', (960 * 3, 1040 * 2))
    for j, frame in enumerate(frames[::5][:6]):
        rgb = np.array(frame)[:, :, :3].copy()
        rgb[np.array(frame.getchannel('A')) < 128] = 0
        contact.paste(Image.fromarray(rgb), ((j % 3) * 960, (j // 3) * 1040))
    palette = contact.quantize(colors=255)
    entries = palette.getpalette()[:255 * 3] + [0, 0, 0]
    palette.putpalette(entries)
    black = int(np.argmin(np.sum(np.array(entries[:255 * 3]).reshape(255, 3) ** 2, axis=1)))
    sequence = []
    for frame in frames:
        indexed = frame.convert('RGB').quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG)
        pixels = np.array(indexed)
        pixels[pixels == 255] = black
        pixels[np.array(frame.getchannel('A')) < 128] = 255
        indexed = Image.fromarray(pixels)
        indexed.putpalette(entries)
        sequence.append(indexed)
    dest = OUT / (clip + '.gif')
    sequence[0].save(dest, save_all=True, append_images=sequence[1:],
                     duration=[80, 80, 90] * 20, loop=0, optimize=False,
                     transparency=255, background=255, disposal=2)
    with Image.open(dest) as im:
        count = im.n_frames
        total = 0
        poses = []
        assert im.info['loop'] == 0 and im.info['transparency'] == 255
        for i in range(count):
            im.seek(i)
            total += im.info['duration']
            rgba = im.convert('RGBA')
            assert rgba.getchannel('A').getextrema() == (0, 255)
            poses.append(rgba.tobytes())
        assert count == 12 and len(set(poses)) == 6 and total == 5000
    return {'clip': clip, 'path': str(dest.relative_to(ROOT)), 'size': [960, 1040],
            'gif_frames': count, 'distinct_poses': 6, 'duration_ms': total,
            'infinite_loop': True, 'transparent': True}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    reports = [export(clip) for clip in CLIPS]
    (OUT / 'validation.json').write_text(json.dumps(reports, indent=2) + '\n')
    print(json.dumps(reports, indent=2))


if __name__ == '__main__':
    main()
