#!/usr/bin/env python3
"""Assemble transparent Iron Man action sheets into six-pose animation clips.

Each input PNG in ``artwork/iron-man-action/sheets`` is a 3-column by 2-row
sheet in row-major order. The script extracts and fits those six real poses,
writes 960x1040 PNG frames, transparent looping GIF previews, and a labeled
overview. Source sheets are left untouched. Use ``--install`` to copy the PNG
frames into ``Resources/characters/iron-man/<clip>``.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "artwork" / "iron-man-action"
SHEETS = ART / "sheets"
DERIVED = ART / "derived"
FRAME_ROOT = DERIVED / "frames"
GIF_ROOT = ART / "gifs"
PREVIEW_ROOT = ART / "previews"
FRAME_SIZE = (960, 1040)
GRID = (3, 2)
OVERVIEW_FRAME_DURATION_MS = 180

ACTION_DURATIONS = {
    "run": 0.12, "dash": 0.12, "punch": 0.12,
    "repulsor_shoot": 0.18, "chest_blast": 0.18,
    "jump": 0.18, "landing": 0.18, "block": 0.18,
    "flight": 0.24,
    "ready": 0.28, "scan": 0.28, "energy_charge": 0.28,
}
HUMAN_NAMES = {
    "run": "Run", "dash": "Dash", "punch": "Punch",
    "repulsor_shoot": "Repulsor Shot", "chest_blast": "Chest Blast",
    "jump": "Jump", "landing": "Landing", "block": "Block",
    "flight": "Flight", "ready": "Ready", "scan": "Scan",
    "energy_charge": "Energy Charge",
}


def action_for_clip(name: str) -> str:
    normalized = name.lower().replace("-", "_").replace(" ", "_")
    matches = [action for action in ACTION_DURATIONS if action in normalized]
    return max(matches, key=len) if matches else "ready"


def clip_duration_seconds(name: str) -> float:
    return ACTION_DURATIONS[action_for_clip(name)]


def human_name(name: str) -> str:
    action = action_for_clip(name)
    normalized = name.lower().replace("-", "_").replace(" ", "_")
    suffix = normalized.replace(action, "")
    for prefix in ("iron_man", "ironman", "action"):
        suffix = suffix.replace(prefix, "")
    suffix = suffix.strip("_")
    return HUMAN_NAMES[action] + (f" {suffix.replace('_', ' ').title()}" if suffix else "")


def load_friday_helpers():
    """Load the shared extraction helpers without depending on cwd/PYTHONPATH."""
    path = ROOT / "tools" / "assemble_friday_action_sheets.py"
    spec = importlib.util.spec_from_file_location("friday_action_helpers", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load shared sheet helpers from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def png_sha256(path: Path) -> str:
    return sha256(path.read_bytes())


def save_transparent_gif(path: Path, frames: list[Image.Image], duration_ms: int) -> None:
    """Save a looped GIF with a shared palette and a real transparent index."""
    if not frames:
        raise ValueError("Cannot write an empty GIF")
    rgba = [frame.convert("RGBA") for frame in frames]
    # Palette from all six visible poses; reserve index 255 for transparency.
    # First remap opaque pixels that quantize to 255 to the nearest black entry.
    contact = Image.new("RGB", (FRAME_SIZE[0] * 3, FRAME_SIZE[1] * 2), (0, 0, 0))
    for index, frame in enumerate(rgba):
        rgb = np.asarray(frame.convert("RGB")).copy()
        alpha = np.asarray(frame.getchannel("A"))
        rgb[alpha < 128] = 0
        contact.paste(Image.fromarray(rgb), ((index % 3) * FRAME_SIZE[0], (index // 3) * FRAME_SIZE[1]))
    if all(np.asarray(frame.getchannel("A")).max() == 0 for frame in rgba):
        raise ValueError(f"{path}: all frames are transparent")
    palette_image = contact.quantize(colors=255)
    palette = palette_image.getpalette()[:255 * 3] + [0, 0, 0]
    palette_image.putpalette(palette)
    rgb_palette = np.asarray(palette[:255 * 3], dtype=np.int32).reshape(255, 3)
    black_index = int(np.argmin(np.sum(rgb_palette * rgb_palette, axis=1)))
    indexed = []
    for frame in rgba:
        color = frame.convert("RGB").quantize(palette=palette_image, dither=Image.Dither.FLOYDSTEINBERG)
        values = np.asarray(color, dtype=np.uint8).copy()
        alpha = np.asarray(frame.getchannel("A"), dtype=np.uint8)
        values[values == 255] = black_index
        values[alpha < 128] = 255
        out = Image.fromarray(values, "P")
        out.putpalette(palette)
        indexed.append(out)
    path.parent.mkdir(parents=True, exist_ok=True)
    indexed[0].save(path, save_all=True, append_images=indexed[1:], duration=duration_ms,
                     loop=0, transparency=255, disposal=2, optimize=False)


def make_overview(frames_by_clip: dict[str, list[Image.Image]], path: Path) -> None:
    """Write synchronized, named clip thumbnails as one looping overview GIF."""
    labels = list(frames_by_clip)
    thumb_w, thumb_h, header_h, pad = 220, 238, 34, 10
    columns = min(4, max(1, len(labels)))
    rows = math.ceil(len(labels) / columns)
    width = columns * thumb_w
    height = rows * (header_h + thumb_h)
    font = ImageFont.load_default()
    overview = []
    for pose_index in range(6):
        canvas = Image.new("RGB", (width, height), (34, 39, 46))
        draw = ImageDraw.Draw(canvas)
        for index, label in enumerate(labels):
            col, row = index % columns, index // columns
            x, y = col * thumb_w, row * (header_h + thumb_h)
            draw.text((x + pad, y + 9), human_name(label), font=font, fill=(245, 247, 250))
            thumb = frames_by_clip[label][pose_index].resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
            background = Image.new("RGBA", thumb.size, (68, 76, 87, 255))
            background.alpha_composite(thumb)
            canvas.paste(background.convert("RGB"), (x, y + header_h))
        overview.append(canvas)
    save_opaque_gif(path, overview, OVERVIEW_FRAME_DURATION_MS)


def save_opaque_gif(path: Path, frames: list[Image.Image], duration_ms: int) -> None:
    """Save the labeled overview GIF; its review background is intentionally opaque."""
    palette = frames[0].quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    indexed = [frame.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG) for frame in frames]
    path.parent.mkdir(parents=True, exist_ok=True)
    indexed[0].save(path, save_all=True, append_images=indexed[1:], duration=duration_ms,
                     loop=0, disposal=2, optimize=False)


def verify_saved_gif(path: Path, expected_frames: int, duration_ms: int, transparent: bool) -> dict:
    with Image.open(path) as gif:
        count = getattr(gif, "n_frames", 1)
        durations = []
        transparency = gif.info.get("transparency")
        for index in range(count):
            gif.seek(index)
            durations.append(int(gif.info.get("duration", 0)))
            if transparent and gif.convert("RGBA").getchannel("A").getextrema() != (0, 255):
                raise ValueError(f"{path}: frame {index} does not retain both transparent and opaque pixels")
        if count != expected_frames:
            raise ValueError(f"{path}: expected {expected_frames} frames, got {count}")
        if any(ms != duration_ms for ms in durations):
            raise ValueError(f"{path}: unexpected frame durations {durations}")
        if int(gif.info.get("loop", -1)) != 0:
            raise ValueError(f"{path}: GIF is not configured to loop forever")
        if transparent and transparency is None:
            raise ValueError(f"{path}: no GIF transparent palette index")
    return {"frame_count": count, "durations_ms": durations, "loop": 0,
            "transparent_index": transparency}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clips", nargs="+", help="assemble named sheet stems; default is every PNG sheet")
    parser.add_argument("--install", action="store_true", help="copy generated PNG frames into Resources/characters/iron-man")
    args = parser.parse_args()
    try:
        if not SHEETS.is_dir():
            raise FileNotFoundError(f"Source sheet directory not found: {SHEETS}")
        sources = {p.stem: p for p in sorted(SHEETS.glob("*.png"))}
        if args.clips:
            missing = [name for name in args.clips if name not in sources]
            if missing:
                raise FileNotFoundError(f"Missing source sheets for clips: {', '.join(missing)}")
            selected = list(dict.fromkeys(args.clips))
        else:
            selected = list(sources)
        if not selected:
            raise FileNotFoundError(f"No PNG source sheets found in {SHEETS}")

        helpers = load_friday_helpers()
        FRAME_ROOT.mkdir(parents=True, exist_ok=True)
        GIF_ROOT.mkdir(parents=True, exist_ok=True)
        PREVIEW_ROOT.mkdir(parents=True, exist_ok=True)
        reports = []
        overview_frames: dict[str, list[Image.Image]] = {}
        for name in selected:
            duration_seconds = clip_duration_seconds(name)
            duration_ms = int(round(duration_seconds * 100)) * 10
            if duration_ms % 10:
                raise AssertionError(f"{name}: GIF timing must use 10ms increments")
            source = sources[name]
            sheet = Image.open(source).convert("RGBA")
            helpers.validate_alpha(sheet, source)
            cells, extraction = helpers.extract_component_cells(sheet, GRID)
            if len(cells) != 6:
                raise ValueError(f"{source}: expected six extracted poses, got {len(cells)}")
            crop = helpers.shared_crop(cells)
            keyframes = [helpers.fit_cell(cell, crop) for cell in cells]
            if any(frame.size != FRAME_SIZE for frame in keyframes):
                raise ValueError(f"{source}: output frames must be {FRAME_SIZE}")
            key_hashes = [sha256(frame.tobytes()) for frame in keyframes]
            if len(set(key_hashes)) != 6:
                raise ValueError(f"{source}: extracted key poses are not all distinct")
            for index, frame in enumerate(keyframes):
                alpha_extrema = frame.getchannel("A").getextrema()
                if alpha_extrema != (0, 255):
                    raise ValueError(f"{source}: pose {index + 1} alpha range is {alpha_extrema}, expected transparent and opaque pixels")

            frame_dir = FRAME_ROOT / name
            if frame_dir.exists():
                shutil.rmtree(frame_dir)
            frame_dir.mkdir(parents=True)
            metadata = {"frame_duration": duration_seconds, "loops": True}
            (frame_dir / "animation.json").write_text(json.dumps(metadata, indent=2) + "\n")
            output_hashes = []
            for index, frame in enumerate(keyframes):
                destination = frame_dir / f"{index:02d}.png"
                frame.save(destination, compress_level=4)
                output_hashes.append(png_sha256(destination))
                with Image.open(destination) as check:
                    if check.size != FRAME_SIZE or check.mode != "RGBA":
                        raise ValueError(f"{destination}: expected RGBA {FRAME_SIZE}, got {check.mode} {check.size}")

            gif_path = GIF_ROOT / f"{name}.gif"
            save_transparent_gif(gif_path, keyframes, duration_ms)
            gif_check = verify_saved_gif(gif_path, 6, duration_ms, transparent=True)
            overview_frames[name] = keyframes
            report = {
                "clip": name,
                "source": str(source.relative_to(ROOT)),
                "source_sha256": png_sha256(source),
                "source_size": list(sheet.size),
                "grid": list(GRID),
                "cell_crop_bbox": list(crop),
                "extraction": extraction,
                "frame_size": list(FRAME_SIZE),
                "frame_count": len(keyframes),
                "distinct_pose_count": len(set(key_hashes)),
                "pose_sha256": key_hashes,
                "output_sha256": output_hashes,
                "alpha_extrema": [[int(v) for v in frame.getchannel("A").getextrema()] for frame in keyframes],
                "frame_duration_seconds": duration_seconds,
                "frame_duration_ms": duration_ms,
                "clip_duration_seconds": duration_seconds * 6,
                "animation_metadata": metadata,
                "gif": str(gif_path.relative_to(ROOT)),
                "gif_validation": gif_check,
            }
            reports.append(report)
            print(json.dumps({k: v for k, v in report.items() if k not in ("output_sha256", "pose_sha256")}), flush=True)

            # A six-cell contact sheet records the source-order key poses.
            contact = Image.new("RGB", (3 * 320, 2 * 360), (234, 237, 240))
            draw = ImageDraw.Draw(contact)
            for index, frame in enumerate(keyframes):
                x, y = (index % 3) * 320, (index // 3) * 360
                draw.text((x + 8, y + 4), f"{human_name(name)} · Pose {index + 1}", fill=(36, 41, 47))
                thumb = frame.resize((320, 347), Image.Resampling.LANCZOS)
                background = Image.new("RGBA", thumb.size, (234, 237, 240, 255))
                background.alpha_composite(thumb)
                contact.paste(background.convert("RGB"), (x, y + 22))
            contact.save(PREVIEW_ROOT / f"{name}-poses.png")

            if args.install:
                install_dir = ROOT / "Resources" / "characters" / "iron-man" / name
                if install_dir.exists():
                    shutil.rmtree(install_dir)
                shutil.copytree(frame_dir, install_dir)
                report["installed_frames"] = str(install_dir.relative_to(ROOT))

        overview_path = PREVIEW_ROOT / "iron-man-actions.gif"
        make_overview(overview_frames, overview_path)
        overview_validation = verify_saved_gif(overview_path, 6, OVERVIEW_FRAME_DURATION_MS, transparent=False)
        validation = {
            "format_version": 1,
            "grid": list(GRID),
            "frame_size": list(FRAME_SIZE),
            "frame_durations_seconds": {name: clip_duration_seconds(name) for name in selected},
            "clips": reports,
            "overview_gif": str(overview_path.relative_to(ROOT)),
            "overview_validation": overview_validation,
        }
        (DERIVED / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"overview_gif": str(overview_path.relative_to(ROOT)),
                          "validation": str((DERIVED / "validation.json").relative_to(ROOT)),
                          "installed": bool(args.install)}), flush=True)
        return 0
    except Exception as exc:
        print(f"assemble_ironman_actions: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
