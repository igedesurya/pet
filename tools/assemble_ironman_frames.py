#!/usr/bin/env python3
"""Fit Iron Man's full-canvas pose cutouts into six-frame action clips.

Inputs are cutouts named ``<clip>_<00..05>.png``. The source canvas is
uniformly scaled and placed at one fixed origin on a 960x1040 transparent
canvas, retaining shared baselines and the jump's height changes.
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
CUTOUT_ROOT = ART / "cutouts"
DERIVED_ROOT = ART / "derived-native"
FRAME_ROOT = DERIVED_ROOT / "frames"
GIF_ROOT = ART / "gifs"
PREVIEW_ROOT = ART / "previews"
INSTALL_ROOT = ROOT / "Resources" / "characters" / "iron-man"
FRAME_SIZE = (960, 1040)
EXPECTED_SOURCE_SIZE = (512, 768)
CLIPS = (
    "action_ready",
    "action_repulsor_shoot",
    "action_jump",
    "action_flight",
    "action_landing",
    "action_running",
    "action_dash",
    "action_punch",
    "action_block",
    "action_chest_blast",
    "action_scan",
    "action_energy_charge",
)
HUMAN_LABELS = {
    "action_ready": "Ready",
    "action_repulsor_shoot": "Repulsor Shot",
    "action_jump": "Jump",
    "action_flight": "Flight",
    "action_landing": "Landing",
    "action_running": "Running",
    "action_dash": "Dash",
    "action_punch": "Punch",
    "action_block": "Block",
    "action_chest_blast": "Chest Blast",
    "action_scan": "Scan",
    "action_energy_charge": "Energy Charge",
}


def load_sheet_helpers():
    """Use the shared Iron Man timing and GIF validation/export helpers."""
    path = ROOT / "tools" / "assemble_ironman_actions.py"
    spec = importlib.util.spec_from_file_location("ironman_sheet_helpers", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load shared animation helpers from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fit_full_canvas(source: Image.Image) -> tuple[Image.Image, dict]:
    """Uniformly scale the whole source canvas, top-align it, and center x."""
    if source.size != EXPECTED_SOURCE_SIZE:
        raise ValueError(f"Expected source canvas {EXPECTED_SOURCE_SIZE}, got {source.size}")
    scale = min(FRAME_SIZE[0] / source.width, FRAME_SIZE[1] / source.height)
    width = int(round(source.width * scale))
    height = int(round(source.height * scale))
    left = (FRAME_SIZE[0] - width) // 2
    top = 0
    # Mapping both axes through the same floating-point scale avoids a slight
    # aspect-ratio distortion from resizing to a rounded integer rectangle.
    resized = source.convert("RGBA").transform(
        (width, height), Image.Transform.AFFINE,
        (1.0 / scale, 0, 0, 0, 1.0 / scale, 0),
        resample=Image.Resampling.BICUBIC,
    )
    canvas = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))
    canvas.alpha_composite(resized, (left, top))
    return canvas, {"uniform_scale": scale, "scaled_source_size": [width, height],
                    "placement_xy": [left, top], "source_canvas_preserved": True}


def make_overview(frames_by_clip: dict[str, list[Image.Image]], path: Path, duration_ms: int, helpers) -> None:
    """Render one labeled, four-column overview using the shared GIF writer."""
    labels = list(frames_by_clip)
    thumb_w, thumb_h, header_h, pad = 220, 238, 34, 10
    columns = min(4, max(1, len(labels)))
    rows = math.ceil(len(labels) / columns)
    canvas_w = columns * thumb_w
    canvas_h = rows * (header_h + thumb_h)
    font = ImageFont.load_default()
    overview = []
    for pose_index in range(6):
        canvas = Image.new("RGB", (canvas_w, canvas_h), (34, 39, 46))
        draw = ImageDraw.Draw(canvas)
        for index, clip in enumerate(labels):
            col, row = index % columns, index // columns
            x, y = col * thumb_w, row * (header_h + thumb_h)
            draw.text((x + pad, y + 9), HUMAN_LABELS[clip], font=font, fill=(245, 247, 250))
            thumb = frames_by_clip[clip][pose_index].resize(
                (thumb_w, thumb_h), Image.Resampling.LANCZOS)
            background = Image.new("RGBA", thumb.size, (68, 76, 87, 255))
            background.alpha_composite(thumb)
            canvas.paste(background.convert("RGB"), (x, y + header_h))
        overview.append(canvas)
    helpers.save_opaque_gif(path, overview, duration_ms)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clips", nargs="+", choices=CLIPS,
                        help="assemble selected clips; default requires all twelve")
    parser.add_argument("--cutouts", type=Path, default=CUTOUT_ROOT,
                        help="directory containing full-canvas transparent PNG cutouts")
    parser.add_argument("--install", action="store_true",
                        help="copy generated frames into Resources/characters/iron-man")
    args = parser.parse_args()
    try:
        selected = list(dict.fromkeys(args.clips or CLIPS))
        sources = {
            clip: [args.cutouts / f"{clip}_{index:02d}.png" for index in range(6)]
            for clip in selected
        }
        missing = [str(path) for paths in sources.values() for path in paths if not path.is_file()]
        if missing:
            raise FileNotFoundError(
                f"Waiting for all six cutouts per selected clip; missing {len(missing)} file(s): "
                + ", ".join(missing[:12]) + (" …" if len(missing) > 12 else "")
            )

        helpers = load_sheet_helpers()
        duration_ms = helpers.OVERVIEW_FRAME_DURATION_MS
        DERIVED_ROOT.mkdir(parents=True, exist_ok=True)
        FRAME_ROOT.mkdir(parents=True, exist_ok=True)
        GIF_ROOT.mkdir(parents=True, exist_ok=True)
        PREVIEW_ROOT.mkdir(parents=True, exist_ok=True)
        reports = []
        overview_frames: dict[str, list[Image.Image]] = {}
        for clip in selected:
            frame_duration = helpers.clip_duration_seconds(clip)
            frame_duration_ms = int(round(frame_duration * 100)) * 10
            keyframes: list[Image.Image] = []
            source_hashes: list[str] = []
            for source_path in sources[clip]:
                with Image.open(source_path) as input_image:
                    if input_image.format != "PNG":
                        raise ValueError(f"{source_path}: expected PNG input")
                    source = input_image.convert("RGBA")
                alpha_extrema = source.getchannel("A").getextrema()
                if alpha_extrema != (0, 255):
                    raise ValueError(f"{source_path}: expected transparent and opaque pixels, got {alpha_extrema}")
                fitted, fit_record = fit_full_canvas(source)
                if fitted.getchannel("A").getextrema() != (0, 255):
                    raise ValueError(f"{source_path}: fitted frame lost transparency or foreground")
                keyframes.append(fitted)
                source_hashes.append(file_sha256(source_path))

            pose_hashes = [rgba_sha256(frame) for frame in keyframes]
            if len(set(pose_hashes)) != 6:
                raise ValueError(f"{clip}: cutouts must produce six distinct RGBA key poses")

            frame_dir = FRAME_ROOT / clip
            if frame_dir.exists():
                shutil.rmtree(frame_dir)
            frame_dir.mkdir(parents=True)
            metadata = {"frame_duration": frame_duration, "loops": True}
            (frame_dir / "animation.json").write_text(json.dumps(metadata, indent=2) + "\n")
            output_hashes = []
            for index, frame in enumerate(keyframes):
                destination = frame_dir / f"{index:02d}.png"
                frame.save(destination, compress_level=4)
                output_hashes.append(file_sha256(destination))
                with Image.open(destination) as check:
                    if check.mode != "RGBA" or check.size != FRAME_SIZE:
                        raise ValueError(f"{destination}: expected RGBA {FRAME_SIZE}")

            gif_path = GIF_ROOT / f"{clip}.gif"
            helpers.save_transparent_gif(gif_path, keyframes, frame_duration_ms)
            gif_validation = helpers.verify_saved_gif(gif_path, 6, frame_duration_ms, transparent=True)
            overview_frames[clip] = keyframes
            report = {
                "clip": clip,
                "label": HUMAN_LABELS[clip],
                "sources": [str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)
                            for path in sources[clip]],
                "source_sha256": source_hashes,
                "pose_rgba_sha256": pose_hashes,
                "output_png_sha256": output_hashes,
                "frame_size": list(FRAME_SIZE),
                "frame_count": 6,
                "distinct_pose_count": len(set(pose_hashes)),
                "alpha_extrema": [[int(v) for v in frame.getchannel("A").getextrema()]
                                  for frame in keyframes],
                "fit": fit_record,
                "frame_duration_seconds": frame_duration,
                "frame_duration_ms": frame_duration_ms,
                "clip_duration_seconds": frame_duration * 6,
                "animation_metadata": metadata,
                "gif": str(gif_path.relative_to(ROOT)),
                "gif_validation": gif_validation,
            }
            reports.append(report)
            print(json.dumps({key: value for key, value in report.items()
                              if key not in ("source_sha256", "pose_rgba_sha256", "output_png_sha256")}), flush=True)

            contact = Image.new("RGB", (960, 720), (234, 237, 240))
            draw = ImageDraw.Draw(contact)
            for index, frame in enumerate(keyframes):
                x, y = (index % 3) * 320, (index // 3) * 360
                draw.text((x + 8, y + 4), f"{HUMAN_LABELS[clip]} · Pose {index + 1}", fill=(36, 41, 47))
                thumb = frame.resize((320, 347), Image.Resampling.LANCZOS)
                background = Image.new("RGBA", thumb.size, (234, 237, 240, 255))
                background.alpha_composite(thumb)
                contact.paste(background.convert("RGB"), (x, y + 22))
            contact.save(PREVIEW_ROOT / f"{clip}-poses.png")

            if args.install:
                install_dir = INSTALL_ROOT / clip
                if install_dir.exists():
                    shutil.rmtree(install_dir)
                install_dir.parent.mkdir(parents=True, exist_ok=True)
                shutil.copytree(frame_dir, install_dir)
                report["installed_frames"] = str(install_dir.relative_to(ROOT))

        overview_path = PREVIEW_ROOT / "iron-man-actions.gif"
        make_overview(overview_frames, overview_path, duration_ms, helpers)
        overview_validation = helpers.verify_saved_gif(
            overview_path, 6, duration_ms, transparent=False)
        validation = {
            "format_version": 1,
            "source_canvas_size": list(EXPECTED_SOURCE_SIZE),
            "frame_size": list(FRAME_SIZE),
            "frame_durations_seconds": {
                clip: helpers.clip_duration_seconds(clip) for clip in selected
            },
            "clips": reports,
            "overview_gif": str(overview_path.relative_to(ROOT)),
            "overview_validation": overview_validation,
            "installed": bool(args.install),
        }
        (DERIVED_ROOT / "validation.json").write_text(
            json.dumps(validation, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"overview_gif": str(overview_path.relative_to(ROOT)),
                          "validation": str((DERIVED_ROOT / "validation.json").relative_to(ROOT)),
                          "installed": bool(args.install)}), flush=True)
        return 0
    except Exception as exc:
        print(f"assemble_ironman_frames: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
