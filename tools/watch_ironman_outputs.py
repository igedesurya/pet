#!/usr/bin/env python3
"""Incrementally extract and assemble completed six-pose Iron Man clips."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "artwork" / "iron-man-action"
SOURCE_ROOT = ART / "local-frames"
CUTOUT_ROOT = ART / "cutouts"
ASSEMBLER = ROOT / "tools" / "assemble_ironman_frames.py"
EXTRACTOR = ROOT / "tools" / "extract_ironman_foreground.swift"
CLIPS = (
    "action_ready", "action_repulsor_shoot", "action_jump", "action_flight",
    "action_landing", "action_running", "action_dash", "action_punch",
    "action_block", "action_chest_blast", "action_scan", "action_energy_charge",
)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def frame_paths(source_root: Path, clip: str) -> list[Path]:
    return [source_root / f"{clip}_{index:02d}.png" for index in range(6)]


def snapshot(paths: list[Path]) -> tuple[tuple[int, int], ...] | None:
    if not all(path.is_file() for path in paths):
        return None
    try:
        return tuple((path.stat().st_size, path.stat().st_mtime_ns) for path in paths)
    except FileNotFoundError:
        return None


def process_clip(clip: str, sources: list[Path], extractor: Path,
                 cutout_root: Path, python: str) -> None:
    with tempfile.TemporaryDirectory(prefix=f"ironman-{clip}-input-") as td:
        staged = Path(td)
        for source in sources:
            # Hard links avoid another full copy of the large rendered PNGs.
            os.link(source, staged / source.name)
        result = subprocess.run([str(extractor), str(staged), str(cutout_root)],
                                cwd=ROOT, text=True, capture_output=True)
        if result.stdout:
            print(result.stdout, end="", flush=True)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or f"Swift extractor failed for {clip}")
    for index in range(6):
        cutout = cutout_root / f"{clip}_{index:02d}.png"
        if not cutout.is_file():
            raise RuntimeError(f"Extractor did not create {cutout}")
        with Image.open(cutout) as image:
            if image.format != "PNG" or image.mode != "RGBA" or image.size != (512, 768):
                raise RuntimeError(f"Unexpected cutout format for {cutout}: {image.mode} {image.size}")
            if image.getchannel("A").getextrema() != (0, 255):
                raise RuntimeError(f"Cutout alpha did not span 0..255: {cutout}")
    result = subprocess.run([python, str(ASSEMBLER), "--clips", clip,
                             "--cutouts", str(cutout_root)], cwd=ROOT,
                            text=True, capture_output=True)
    if result.stdout:
        print(result.stdout, end="", flush=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"Assembler failed for {clip}")
    source_hashes = [digest(path) for path in sources]
    manifest_path = ART / "derived-native" / "watch-manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest = {}
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text())
        except (OSError, json.JSONDecodeError):
            manifest = {}
    manifest[clip] = {"source_sha256": source_hashes, "ready_at_unix": time.time()}
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"READY clip={clip} gif=artwork/iron-man-action/gifs/{clip}.gif "
          f"contact=artwork/iron-man-action/previews/{clip}-poses.png",
          flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=SOURCE_ROOT)
    parser.add_argument("--cutout-dir", type=Path, default=CUTOUT_ROOT)
    parser.add_argument("--python", default=sys.executable,
                        help="Python interpreter with Pillow and NumPy installed")
    parser.add_argument("--poll-seconds", type=float, default=8.0)
    parser.add_argument("--stable-polls", type=int, default=2,
                        help="unchanged file snapshots required before processing")
    args = parser.parse_args()
    args.cutout_dir.mkdir(parents=True, exist_ok=True)
    completed: set[str] = set()
    previous: dict[str, tuple[tuple[int, int], ...] | None] = {clip: None for clip in CLIPS}
    stable: dict[str, int] = {clip: 0 for clip in CLIPS}
    last_progress = 0
    print(f"WATCHING source={args.source_dir} expected_frames={len(CLIPS) * 6}", flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix="ironman-vision-build-") as td:
            extractor = Path(td) / "extract_ironman_foreground"
            build = subprocess.run(["swiftc", str(EXTRACTOR), "-o", str(extractor)],
                                   cwd=ROOT, text=True, capture_output=True)
            if build.returncode:
                raise RuntimeError(build.stderr.strip() or "Could not compile Swift extractor")
            print("EXTRACTOR_COMPILED", flush=True)
            while len(completed) < len(CLIPS):
                available_frames = 0
                for clip in CLIPS:
                    paths = frame_paths(args.source_dir, clip)
                    current = snapshot(paths)
                    available_frames += sum(path.is_file() for path in paths)
                    if clip in completed:
                        continue
                    if current is None:
                        previous[clip] = None
                        stable[clip] = 0
                        continue
                    if current == previous[clip]:
                        stable[clip] += 1
                    else:
                        previous[clip] = current
                        stable[clip] = 0
                    if stable[clip] >= args.stable_polls:
                        print(f"PROCESSING clip={clip} sources=6", flush=True)
                        process_clip(clip, paths, extractor, args.cutout_dir, args.python)
                        completed.add(clip)
                now = time.monotonic()
                if now - last_progress >= 30:
                    ready_count = sum(all(path.is_file() for path in frame_paths(args.source_dir, clip))
                                      for clip in CLIPS)
                    print(f"WAITING clips_present={ready_count}/{len(CLIPS)} "
                          f"frames_present={available_frames}/72 clips_assembled={len(completed)}/12",
                          flush=True)
                    last_progress = now
                if len(completed) < len(CLIPS):
                    time.sleep(max(1.0, args.poll_seconds))

        print("FINAL_OVERVIEW_BUILD", flush=True)
        final = subprocess.run([args.python, str(ASSEMBLER), "--cutouts", str(args.cutout_dir)],
                               cwd=ROOT, text=True, capture_output=True)
        if final.stdout:
            print(final.stdout, end="", flush=True)
        if final.returncode:
            raise RuntimeError(final.stderr.strip() or "Final twelve-clip assembly failed")
        print("ALL_CLIPS_ASSEMBLED overview=artwork/iron-man-action/previews/iron-man-actions.gif "
              "validation=artwork/iron-man-action/derived-native/validation.json",
              flush=True)
        return 0
    except Exception as error:
        print(f"watch_ironman_outputs: {error}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
