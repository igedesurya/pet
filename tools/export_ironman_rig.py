#!/usr/bin/env python3
"""Validate and export the approved bitmap rig's twelve looping action clips."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'artwork/iron-man-action'
NATIVE = ART / 'rig-frames'
OUT = ART / 'gifs'
SIZE = (960, 1040)
GIF_DURATIONS = [30, 30, 40] * 20
PLAN = json.loads((ART / 'plan.json').read_text())
CLIPS = PLAN['modes'][0]['clips']
LABELS = {p['clip']: p['label'] for p in PLAN['actions']}


def digest(image):
    return hashlib.sha256(image.convert('RGBA').tobytes()).hexdigest()


def export_gif(path, frames, transparent=True):
    thumbnails = []
    for frame in frames[::6]:
        thumb = frame.copy()
        thumb.thumbnail((240, 260))
        thumbnails.append(thumb.convert('RGB'))
    contact = Image.new('RGB', (240 * len(thumbnails), 260), (0, 0, 0))
    for index, thumb in enumerate(thumbnails):
        contact.paste(thumb, (240 * index, 0))
    palette_image = contact.quantize(colors=255)
    entries = ((palette_image.getpalette() or []) + [0] * 765)[:765] + [0, 0, 0]
    palette_image.putpalette(entries)
    colors = np.array(entries[:765], dtype=np.int32).reshape(255, 3)
    black = int(np.argmin(np.sum(colors * colors, axis=1)))
    sequence = []
    for frame in frames:
        indexed = frame.convert('RGB').quantize(palette=palette_image, dither=Image.Dither.FLOYDSTEINBERG)
        pixels = np.array(indexed)
        pixels[pixels == 255] = black
        if transparent:
            pixels[np.array(frame.getchannel('A')) < 128] = 255
        indexed = Image.fromarray(pixels)
        indexed.putpalette(entries)
        sequence.append(indexed)
    kwargs = {'transparency': 255, 'background': 255} if transparent else {}
    path.parent.mkdir(parents=True, exist_ok=True)
    sequence[0].save(path, save_all=True, append_images=sequence[1:], duration=GIF_DURATIONS,
                     loop=0, disposal=2, optimize=False, **kwargs)
    with Image.open(path) as check:
        assert check.info.get('loop') == 0
        elapsed = 0
        unique = set()
        for index in range(check.n_frames):
            check.seek(index)
            elapsed += check.info['duration']
            decoded = check.convert('RGBA')
            if transparent:
                assert decoded.getchannel('A').getextrema() == (0, 255)
            unique.add(digest(decoded))
        assert elapsed == 2000, (path, elapsed)
        assert len(unique) >= 20, (path, len(unique))
        return {'encoded_frames': check.n_frames, 'distinct_frames': len(unique),
                'duration_ms': elapsed, 'loop': 0, 'transparent': transparent}


def overview(thumbs):
    columns = min(4, len(thumbs))
    rows = (len(thumbs) + columns - 1) // columns
    width, height = columns * 220, rows * 272
    try:
        font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 15)
    except OSError:
        font = ImageFont.load_default()
    frames = []
    for index in range(60):
        canvas = Image.new('RGB', (width, height), (31, 37, 46))
        draw = ImageDraw.Draw(canvas)
        for item, (clip, sequence) in enumerate(thumbs.items()):
            x, y = (item % columns) * 220, (item // columns) * 272
            draw.text((x + 10, y + 8), LABELS[clip], fill=(225, 240, 255), font=font)
            background = Image.new('RGBA', (220, 238), (68, 76, 87, 255))
            background.alpha_composite(sequence[index])
            canvas.paste(background.convert('RGB'), (x, y + 34))
        frames.append(canvas)
    return frames


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clips', nargs='+', choices=CLIPS)
    parser.add_argument('--install', action='store_true')
    args = parser.parse_args()
    clips = args.clips or CLIPS
    if args.install and clips != CLIPS:
        raise ValueError('Only the complete verified twelve-action pack can be installed')
    reports, thumbs = [], {}
    for clip in clips:
        files = sorted((NATIVE / clip).glob('*.png'))
        if len(files) != 60:
            raise ValueError(f'{clip}: expected sixty rendered frames, got {len(files)}')
        frames = []
        for file in files:
            with Image.open(file) as source:
                assert source.size == SIZE and source.mode == 'RGBA', (file, source.size, source.mode)
                image = source.copy()
            assert image.getchannel('A').getextrema() == (0, 255), file
            frames.append(image)
        hashes = [digest(image) for image in frames]
        assert len(set(hashes)) >= 20, (clip, len(set(hashes)))
        result = export_gif(OUT / (clip + '.gif'), frames)
        reports.append({'clip': clip, 'native_frames': 60, 'distinct_native_frames': len(set(hashes)),
                        'canvas': list(SIZE), 'gif': str((OUT / (clip + '.gif')).relative_to(ROOT)),
                        'gif_validation': result, 'native_rgba_sha256': hashes})
        thumbs[clip] = [image.resize((220, 238), Image.Resampling.LANCZOS) for image in frames]
        print(json.dumps({k: v for k, v in reports[-1].items() if k != 'native_rgba_sha256'}), flush=True)
        del frames
    name = 'iron-man-12-actions.gif' if len(clips) == 12 else 'iron-man-preview.gif'
    combined = overview(thumbs)
    check = export_gif(OUT / name, combined, transparent=False)
    report = {'method': 'articulated bitmap rig from approved reference', 'frame_rate': 30,
              'action_count': len(clips), 'clips': reports, 'overview': name, 'overview_validation': check}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / ('validation.json' if len(clips) == 12 else 'preview-validation.json')).write_text(json.dumps(report, indent=2) + '\n')
    if args.install:
        stage = ART / 'install-staging'
        if stage.exists():
            shutil.rmtree(stage)
        stage.mkdir()
        for clip in CLIPS:
            shutil.copytree(NATIVE / clip, stage / clip)
            (stage / clip / 'animation.json').write_text(json.dumps({'frame_duration': 1/30, 'loops': True}, indent=2) + '\n')
        pack = {'label': 'Iron Man', 'description': 'Dua belas animasi aksi Iron Man dari satu desain armor yang konsisten.', 'modes': PLAN['modes']}
        (stage / 'pack.json').write_text(json.dumps(pack, indent=2) + '\n')
        destination = ROOT / 'Resources/characters/iron-man'
        if destination.exists():
            raise FileExistsError('Refusing to replace an existing character without a preservation backup')
        stage.rename(destination)
        print('Installed complete Iron Man character: ' + str(destination), flush=True)


if __name__ == '__main__':
    main()
