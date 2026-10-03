#!/usr/bin/env python3
"""Assemble six-pose Friday sprite sheets into crisp held-key-pose previews.

The input sheets are 3 columns by 2 rows in row-major order. Every output frame
uses one clip-wide content crop, preserving the source cell's relative framing.
Generated frames and previews are staging artifacts; this script never installs
anything into Resources/characters.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "artwork" / "friday-action-v2"
SHEETS = ART / "sheets"
SIZING = ART / "metadata" / "sizing.json"
DERIVED = ART / "derived"
CLIPS = (
    "home_waking_up",
    "home_cooking_stir",
    "home_sweeping",
    "home_watering_plants",
    "home_hanging_laundry",
)
FRAME_SIZE = (960, 1040)
FRAME_COUNT = 60
FPS = 12
DURATION_MS = [80, 80, 90] * 20  # GIF uses 10ms units; totals exactly 5 seconds.
MAX_FLOW_EDGE = 512


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sizing_config(path: Path = SIZING) -> dict:
    """Load declared sheet geometry/sizing; retain the agreed grid if absent."""
    config = {"grid": [3, 2], "frame_size": list(FRAME_SIZE), "fps": FPS, "duration_seconds": 5}
    if path.exists():
        raw = json.loads(path.read_text())
        # Accept both a direct grid pair and a small explicit object.
        grid = raw.get("grid", raw.get("columns_rows", [3, 2]))
        if isinstance(grid, dict):
            grid = [grid.get("columns"), grid.get("rows")]
        config.update(raw)
        config["grid"] = grid
    if config["grid"] != [3, 2]:
        raise ValueError(f"Sizing metadata must specify grid [3, 2], got {config['grid']!r}")
    if tuple(config.get("frame_size", FRAME_SIZE)) != FRAME_SIZE:
        raise ValueError(f"Output frames must be {FRAME_SIZE}, got {config.get('frame_size')!r}")
    return config


def crop_cells(sheet: Image.Image, grid=(3, 2)) -> list[Image.Image]:
    """Crop exact cells using rounded fractional edges for uneven dimensions."""
    cols, rows = grid
    width, height = sheet.size
    cells = []
    for row in range(rows):
        top = round(row * height / rows)
        bottom = round((row + 1) * height / rows)
        for col in range(cols):
            left = round(col * width / cols)
            right = round((col + 1) * width / cols)
            cells.append(sheet.crop((left, top, right, bottom)).convert("RGBA"))
    # Uneven sheet sizes can give neighboring cells dimensions that differ by
    # one pixel. Pad only at the right/bottom so the shared local origin stays
    # fixed across all six key poses.
    cell_w = max(im.width for im in cells)
    cell_h = max(im.height for im in cells)
    normalized = []
    for im in cells:
        canvas = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
        canvas.alpha_composite(im, (0, 0))
        normalized.append(canvas)
    return normalized


def extract_component_cells(sheet: Image.Image, grid=(3, 2), threshold=128,
                            soft_threshold=8, soft_radius=3) -> tuple[list[Image.Image], dict]:
    """Isolate the six actor silhouettes, including pose/tool spill across cells.

    Dominant alpha components are assigned by their centroids. If two adjacent
    actors touch and form one component, split that component with a cell-center
    Voronoi seam, retaining every source pixel on one side or the other.
    Returned patches share one local crop relative to each original cell origin.
    """
    import cv2

    rgba = sheet.convert("RGBA")
    pixels = np.asarray(rgba, dtype=np.uint8)
    alpha = pixels[:, :, 3]
    height, width = alpha.shape
    cols, rows = grid
    xedges = [round(i * width / cols) for i in range(cols + 1)]
    yedges = [round(i * height / rows) for i in range(rows + 1)]
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(
        (alpha >= threshold).astype(np.uint8), connectivity=8
    )
    components = []
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area < 5000:
            continue
        cx, cy = centroids[label]
        col = min(cols - 1, max(0, int(cx * cols / width)))
        row = min(rows - 1, max(0, int(cy * rows / height)))
        components.append({"label": label, "area": area, "centroid": [float(cx), float(cy)],
                           "cell": row * cols + col,
                           "bbox": [int(stats[label, cv2.CC_STAT_LEFT]), int(stats[label, cv2.CC_STAT_TOP]),
                                    int(stats[label, cv2.CC_STAT_LEFT] + stats[label, cv2.CC_STAT_WIDTH]),
                                    int(stats[label, cv2.CC_STAT_TOP] + stats[label, cv2.CC_STAT_HEIGHT])]})
    if len(components) < cols * rows - 1:
        raise ValueError(f"Only {len(components)} dominant alpha components found; expected at least five")

    by_cell: dict[int, list[dict]] = {i: [] for i in range(cols * rows)}
    for component in components:
        by_cell[component["cell"]].append(component)
    selected: dict[int, np.ndarray] = {}
    selected_components: dict[int, dict] = {}
    missing = []
    for cell, candidates in by_cell.items():
        if not candidates:
            missing.append(cell)
            continue
        chosen = max(candidates, key=lambda c: c["area"])
        selected[cell] = labels == chosen["label"]
        selected_components[cell] = chosen

    split_records = []
    for missing_cell in missing:
        miss_row, miss_col = divmod(missing_cell, cols)
        # Find a dominant component whose centroid owns a neighboring cell and
        # whose extent crosses into the missing cell. This handles thin alpha
        # bridges between otherwise distinct actors or props.
        candidates = []
        for source_cell, chosen in selected_components.items():
            row, col = divmod(source_cell, cols)
            if row != miss_row or abs(col - miss_col) != 1:
                continue
            left, top, right, bottom = chosen["bbox"]
            target_left, target_right = xedges[miss_col], xedges[miss_col + 1]
            if right > target_left and left < target_right:
                candidates.append((chosen["area"], source_cell, chosen))
        if not candidates:
            raise ValueError(f"No neighboring connected component crosses into missing cell {missing_cell}")
        _, source_cell, chosen = max(candidates)
        source_row, source_col = divmod(source_cell, cols)
        component_mask = labels == chosen["label"]
        ys, xs = np.nonzero(component_mask)
        sx = (xedges[source_col] + xedges[source_col + 1]) / 2
        tx = (xedges[miss_col] + xedges[miss_col + 1]) / 2
        sy = (yedges[source_row] + yedges[source_row + 1]) / 2
        ty = (yedges[miss_row] + yedges[miss_row + 1]) / 2
        source_distance = (xs - sx) ** 2 + (ys - sy) ** 2
        target_distance = (xs - tx) ** 2 + (ys - ty) ** 2
        source_side = np.zeros((height, width), dtype=bool)
        target_side = np.zeros((height, width), dtype=bool)
        source_side[ys[source_distance <= target_distance], xs[source_distance <= target_distance]] = True
        target_side[ys[target_distance < source_distance], xs[target_distance < source_distance]] = True
        selected[source_cell] = source_side
        selected[missing_cell] = target_side
        source_ys, source_xs = np.nonzero(source_side)
        selected_components[source_cell] = {
            **chosen, "area": int(source_side.sum()),
            "centroid": [float(source_xs.mean()), float(source_ys.mean())],
            "bbox": [int(source_xs.min()), int(source_ys.min()),
                     int(source_xs.max()) + 1, int(source_ys.max()) + 1],
        }
        selected_components[missing_cell] = {"label": chosen["label"], "area": int(target_side.sum()),
                                             "centroid": [float(xs[target_distance < source_distance].mean()),
                                                          float(ys[target_distance < source_distance].mean())],
                                             "cell": missing_cell,
                                             "bbox": [int(xs[target_distance < source_distance].min()),
                                                      int(ys[target_distance < source_distance].min()),
                                                      int(xs[target_distance < source_distance].max()) + 1,
                                                      int(ys[target_distance < source_distance].max()) + 1]}
        split_records.append({"component_label": chosen["label"], "source_cell": source_cell,
                              "split_cell": missing_cell, "rule": "nearest-cell-center",
                              "removed_fragment_area_px": {}})

        # The ownership split can leave narrow orphan slivers from the other
        # pose at the far crop edge. Keep the main owned regions and discard
        # only tiny disconnected hard-alpha remnants created by that split.
        for split_cell in (source_cell, missing_cell):
            binary = selected[split_cell].astype(np.uint8)
            part_count, part_labels, part_stats, _ = cv2.connectedComponentsWithStats(binary, connectivity=8)
            areas = [int(part_stats[i, cv2.CC_STAT_AREA]) for i in range(1, part_count)]
            largest = max(areas, default=0)
            cutoff = max(500, int(largest * 0.0025))
            clean = np.zeros_like(binary, dtype=bool)
            removed = 0
            for part in range(1, part_count):
                area = int(part_stats[part, cv2.CC_STAT_AREA])
                if area >= cutoff or area == largest:
                    clean |= part_labels == part
                else:
                    removed += area
            selected[split_cell] = clean
            ys_clean, xs_clean = np.nonzero(clean)
            selected_components[split_cell]["area"] = int(clean.sum())
            selected_components[split_cell]["centroid"] = [float(xs_clean.mean()), float(ys_clean.mean())]
            selected_components[split_cell]["bbox"] = [int(xs_clean.min()), int(ys_clean.min()),
                                                         int(xs_clean.max()) + 1, int(ys_clean.max()) + 1]
            split_records[-1]["removed_fragment_area_px"][str(split_cell)] = removed

    if len(selected) != cols * rows:
        raise ValueError(f"Extracted {len(selected)} cell masks; expected six")

    # Work out a common extent in coordinates relative to each grid cell's
    # original top-left. Negative values deliberately preserve protruding arms
    # and long tools that cross a nominal cell edge.
    relative_bounds = []
    for cell, mask in selected.items():
        ys, xs = np.nonzero(mask)
        if not len(xs):
            raise ValueError(f"Cell {cell} has an empty component mask")
        row, col = divmod(cell, cols)
        relative_bounds.append((int(xs.min()) - xedges[col], int(ys.min()) - yedges[row],
                                int(xs.max()) + 1 - xedges[col], int(ys.max()) + 1 - yedges[row]))
    left = min(b[0] for b in relative_bounds)
    top = min(b[1] for b in relative_bounds)
    right = max(b[2] for b in relative_bounds)
    bottom = max(b[3] for b in relative_bounds)
    pad = max(3, round(max(right - left, bottom - top) * 0.015))
    left -= pad; top -= pad; right += pad; bottom += pad

    # Preserve original RGB/alpha around each selected core, including a few
    # pixels of antialiasing. Low-alpha colored fringe/checker artifacts are
    # removed only in these derived pack-cleanup pixels; source sheets stay intact.
    kernel_size = soft_radius * 2 + 1
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))
    extracted = []
    for cell in range(cols * rows):
        row, col = divmod(cell, cols)
        core = selected[cell].astype(np.uint8)
        support = cv2.dilate(core, kernel)
        other_hard_cores = (alpha >= threshold) & (core == 0)
        distance_to_core = cv2.distanceTransform((core == 0).astype(np.uint8), cv2.DIST_L2, 3)
        distance_to_other = cv2.distanceTransform((~other_hard_cores).astype(np.uint8), cv2.DIST_L2, 3)
        soft_candidate = ((support > 0) & (alpha > soft_threshold) & ~other_hard_cores
                          & (distance_to_core <= distance_to_other))
        soft_count, soft_labels = cv2.connectedComponents(soft_candidate.astype(np.uint8), connectivity=8)
        owned_labels = np.unique(soft_labels[core > 0])
        owned_labels = owned_labels[owned_labels > 0]
        allowed = np.isin(soft_labels, owned_labels) if len(owned_labels) else core.astype(bool)
        isolated = pixels.copy()
        isolated[:, :, 3] = np.where(allowed, alpha, 0).astype(np.uint8)
        isolated_rgba = Image.fromarray(isolated, "RGBA")
        origin_x = xedges[col] + left
        origin_y = yedges[row] + top
        extracted.append(isolated_rgba.crop((origin_x, origin_y, origin_x + right - left,
                                             origin_y + bottom - top)))
    report = {"method": "alpha-connected-components", "hard_alpha_threshold": threshold,
              "soft_alpha_threshold": soft_threshold, "soft_alpha_radius_px": soft_radius,
              "shared_cell_relative_bbox": [left, top, right, bottom],
              "component_area_px": [int(selected_components[i]["area"]) for i in range(cols * rows)],
              "component_centroids_px": [selected_components[i]["centroid"] for i in range(cols * rows)],
              "split_components": split_records}
    return extracted, report


def validate_alpha(sheet: Image.Image, path: Path) -> None:
    rgba = sheet.convert("RGBA")
    alpha = np.asarray(rgba.getchannel("A"), dtype=np.uint8)
    amin, amax = int(alpha.min()), int(alpha.max())
    transparent = int(np.count_nonzero(alpha == 0))
    translucent = int(np.count_nonzero((alpha > 0) & (alpha < 255)))
    opaque = int(np.count_nonzero(alpha == 255))
    if amin == 255 or transparent == 0:
        raise ValueError(f"{path}: no transparent pixels in actual alpha channel; refusing opaque/fake transparency")
    if amax < 200 or opaque == 0:
        raise ValueError(f"{path}: alpha channel has no solid character pixels (range {amin}..{amax})")
    # Opaque checkerboard art is caught by the fully-opaque check above. Also
    # reject near-opaque alpha coverage that looks like an opaque canvas with
    # only a thin accidental border removed; never infer/strip a background.
    fraction_transparent = transparent / alpha.size
    if fraction_transparent < 0.005:
        raise ValueError(f"{path}: only {fraction_transparent:.3%} transparent pixels; refusing likely opaque background")
    print(json.dumps({"source": path.name, "alpha_min": amin, "alpha_max": amax,
                      "alpha_transparent_pixels": transparent, "alpha_translucent_pixels": translucent,
                      "alpha_opaque_pixels": opaque}), flush=True)


def shared_crop(cells: list[Image.Image]) -> tuple[int, int, int, int]:
    """Return one union alpha bbox, so all six poses share scale and alignment."""
    bounds = [im.getchannel("A").getbbox() for im in cells]
    bounds = [b for b in bounds if b is not None]
    if not bounds:
        raise ValueError("All six cells are transparent")
    left = min(b[0] for b in bounds)
    top = min(b[1] for b in bounds)
    right = max(b[2] for b in bounds)
    bottom = max(b[3] for b in bounds)
    # Add the same small margin around the full action envelope.
    width, height = cells[0].size
    pad = max(2, round(max(right - left, bottom - top) * 0.025))
    return max(0, left - pad), max(0, top - pad), min(width, right + pad), min(height, bottom + pad)


def fit_cell(cell: Image.Image, bbox: tuple[int, int, int, int]) -> Image.Image:
    cropped = cell.crop(bbox)
    scale = min(FRAME_SIZE[0] / cropped.width, FRAME_SIZE[1] / cropped.height)
    out_w, out_h = max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))
    resized = cropped.resize((out_w, out_h), Image.Resampling.LANCZOS)
    frame = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))
    # Same source-space crop and same offset for every key pose: do not recenter
    # individual bodies or resize their heads independently.
    frame.alpha_composite(resized, ((FRAME_SIZE[0] - out_w) // 2, (FRAME_SIZE[1] - out_h) // 2))
    return frame


def premultiplied_float(image: Image.Image) -> np.ndarray:
    a = np.asarray(image.getchannel("A"), dtype=np.float32) / 255.0
    rgb = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0
    rgb *= a[:, :, None]
    return np.dstack((rgb, a)).astype(np.float32)


def flow_warp(field: np.ndarray, dx: np.ndarray, dy: np.ndarray, t: float) -> np.ndarray:
    import cv2

    h, w = field.shape[:2]
    yy, xx = np.mgrid[:h, :w].astype(np.float32)
    # Flow is estimated source-to-destination. Sampling backwards by the
    # appropriately scaled field gives a practical symmetric approximation.
    map_x = xx - dx * t
    map_y = yy - dy * t
    return cv2.remap(field, map_x, map_y, interpolation=cv2.INTER_LINEAR,
                     borderMode=cv2.BORDER_CONSTANT, borderValue=0)


def interpolate_pair(a: Image.Image, b: Image.Image, steps: int = 10) -> list[Image.Image]:
    """Return segment start and nine in-betweens using bidirectional dense flow."""
    import cv2

    scale = min(1.0, MAX_FLOW_EDGE / max(FRAME_SIZE))
    work_size = (max(1, round(FRAME_SIZE[0] * scale)), max(1, round(FRAME_SIZE[1] * scale)))
    pa = premultiplied_float(a)
    pb = premultiplied_float(b)
    if work_size != FRAME_SIZE:
        pa = cv2.resize(pa, work_size, interpolation=cv2.INTER_AREA)
        pb = cv2.resize(pb, work_size, interpolation=cv2.INTER_AREA)
    ga = cv2.cvtColor(np.clip(pa[:, :, :3] * 255, 0, 255).astype(np.uint8), cv2.COLOR_RGB2GRAY)
    gb = cv2.cvtColor(np.clip(pb[:, :, :3] * 255, 0, 255).astype(np.uint8), cv2.COLOR_RGB2GRAY)
    # CPU-bounded parameters; lower pyramid levels keep the small 512px working
    # image practical while retaining distinct arm/tool motion.
    params = dict(pyr_scale=0.5, levels=4, winsize=21, iterations=4,
                  poly_n=7, poly_sigma=1.5, flags=0)
    ab = cv2.calcOpticalFlowFarneback(ga, gb, None, **params)
    ba = cv2.calcOpticalFlowFarneback(gb, ga, None, **params)
    results = []
    for index in range(steps):
        t = index / steps
        if index == 0:
            results.append(a.copy())
            continue
        wa = flow_warp(pa, ab[:, :, 0], ab[:, :, 1], t)
        wb = flow_warp(pb, ba[:, :, 0], ba[:, :, 1], 1 - t)
        mixed = wa * (1 - t) + wb * t
        if work_size != FRAME_SIZE:
            mixed = cv2.resize(mixed, FRAME_SIZE, interpolation=cv2.INTER_LINEAR)
        alpha = np.clip(mixed[:, :, 3:4], 0, 1)
        rgb = np.divide(mixed[:, :, :3], alpha, out=np.zeros_like(mixed[:, :, :3]), where=alpha > 1e-5)
        rgba = np.dstack((np.clip(rgb * 255, 0, 255), np.clip(alpha[:, :, 0] * 255, 0, 255))).astype(np.uint8)
        results.append(Image.fromarray(rgba, "RGBA"))
    return results


def build_frames(keys: list[Image.Image], mode: str) -> list[Image.Image]:
    frames = []
    if mode == "poses":
        # One cycle is 6 held key poses x 5 output frames = 30 frames (2.5s).
        # Repeat the cycle once for a 60-frame, five-second preview. There is
        # no blend or optical warp between poses in this mode.
        return [key.copy() for _cycle in range(2) for key in keys for _hold in range(5)]
    if mode == "hold":
        for key in keys:
            frames.extend([key.copy() for _ in range(10)])
        return frames
    if mode != "farneback":
        raise ValueError(f"Unknown interpolation mode: {mode}")
    for index, key in enumerate(keys):
        nxt = keys[(index + 1) % len(keys)]
        frames.extend(interpolate_pair(key, nxt, 10))
    return frames


def gif_save(path: Path, images: list[Image.Image], durations=DURATION_MS) -> None:
    # Shared palette avoids per-frame color flicker; alpha remains binary in GIF.
    rgb = [im.convert("RGB") for im in images]
    palette = rgb[0].quantize(colors=192)
    sequence = [im.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG) for im in rgb]
    sequence[0].save(path, save_all=True, append_images=sequence[1:], duration=durations,
                     loop=0, optimize=False, disposal=2)


def render_mp4(path: Path, frames: list[Image.Image], ffmpeg: str) -> None:
    size = frames[0].size
    with tempfile.TemporaryDirectory(prefix="friday-preview-") as tmp:
        tmp_path = Path(tmp)
        for i, frame in enumerate(frames):
            # H.264 does not support alpha. Composite on a neutral review canvas.
            bg = Image.new("RGBA", size, (234, 237, 240, 255))
            bg.alpha_composite(frame.convert("RGBA"))
            bg.convert("RGB").save(tmp_path / f"{i:03d}.png", compress_level=2)
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(FPS),
                        "-i", str(tmp_path / "%03d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p",
                        "-movflags", "+faststart", str(path)], check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clips", nargs="+", choices=CLIPS, help="assemble a subset; default is all five")
    parser.add_argument("--interpolation", choices=("farneback", "hold", "poses"), default="poses",
                        help="preferred: crisp six-key-pose cycle; experimental: farneback flow or ten-frame holds")
    parser.add_argument("--ffmpeg", default="/opt/homebrew/bin/ffmpeg")
    parser.add_argument("--sizing", type=Path, default=SIZING, help="sheet/output sizing metadata JSON")
    args = parser.parse_args()
    try:
        cfg = sizing_config(args.sizing)
        if cfg["duration_seconds"] != 5 or cfg["fps"] != 12:
            raise ValueError("Sizing metadata must retain the requested 5s/12fps timing")
        selected = args.clips or list(CLIPS)
        preview_dir = DERIVED / "previews"
        frame_root = DERIVED / "frames"
        preview_dir.mkdir(parents=True, exist_ok=True)
        all_preview_frames: dict[str, list[Image.Image]] = {}
        all_keyframes: dict[str, list[Image.Image]] = {}
        reports = []
        for name in selected:
            source = SHEETS / f"{name}.png"
            if not source.exists():
                raise FileNotFoundError(f"Missing source sheet: {source}")
            sheet = Image.open(source).convert("RGBA")
            validate_alpha(sheet, source)
            cells, extraction = extract_component_cells(
                sheet, cfg["grid"], threshold=cfg.get("component_alpha_threshold", 128),
                soft_threshold=cfg.get("soft_alpha_threshold", 8),
                soft_radius=cfg.get("soft_alpha_radius_px", 3),
            )
            bbox = shared_crop(cells)
            keyframes = [fit_cell(cell, bbox) for cell in cells]
            frames = build_frames(keyframes, args.interpolation)
            if len(frames) != FRAME_COUNT:
                raise AssertionError(f"{name}: expected {FRAME_COUNT}, produced {len(frames)}")
            out_dir = frame_root / name
            if out_dir.exists():
                shutil.rmtree(out_dir)
            out_dir.mkdir(parents=True)
            hashes = []
            alpha_sizes = []
            for i, frame in enumerate(frames):
                dest = out_dir / f"{i + 1:02d}.png"
                frame.save(dest, compress_level=4)
                hashes.append(file_sha256(dest))
                alpha_sizes.append(list(frame.getchannel("A").getextrema()))
            if any(Image.open(out_dir / f"{i:02d}.png").size != FRAME_SIZE for i in (1, 20, 40, 60)):
                raise AssertionError(f"{name}: output dimensions do not match {FRAME_SIZE}")
            unique_count = len(set(hashes))
            key_hashes = [hashlib.sha256(im.tobytes()).hexdigest() for im in keyframes]
            if len(set(key_hashes)) != len(keyframes):
                raise AssertionError(f"{name}: extracted keyframe poses are not all distinct")
            if args.interpolation == "poses":
                raw_hashes = [hashlib.sha256(im.tobytes()).hexdigest() for im in frames]
                expected = [digest for digest in key_hashes for _ in range(5)] * 2
                if raw_hashes != expected or unique_count != 6:
                    raise AssertionError(f"{name}: poses mode must repeat six original keys, five frames each, twice")
            elif args.interpolation == "farneback" and unique_count < FRAME_COUNT * 0.9:
                raise AssertionError(f"{name}: flow interpolation produced only {unique_count} unique frames")
            # GIF preview stays at full review scale; app installation is separate.
            gif_path = preview_dir / f"{name}.gif"
            gif_save(gif_path, frames)
            all_preview_frames[name] = frames
            all_keyframes[name] = keyframes
            seam = float(np.abs(np.asarray(frames[0], dtype=np.int16) - np.asarray(frames[-1], dtype=np.int16)).mean())
            report = {
                "clip": name, "source": str(source.relative_to(ROOT)), "source_sha256": sha256(source),
                "source_size": list(sheet.size), "grid": cfg["grid"], "cell_crop_bbox": list(bbox),
                "extraction": extraction,
                "frame_size": list(FRAME_SIZE), "frame_count": len(frames), "fps": FPS,
                "duration_seconds": 5, "gif_duration_schedule_ms": DURATION_MS,
                "interpolation": args.interpolation, "source_keyframe_hashes": key_hashes,
                "unique_frame_count": unique_count,
                "expected_unique_frame_count": 6 if args.interpolation == "poses" else None,
                "output_sha256": hashes,
                "alpha_extrema": sorted(set(tuple(v) for v in alpha_sizes)),
                "loop_edge_mean_absolute_delta": round(seam, 6), "gif": str(gif_path.relative_to(ROOT)),
            }
            reports.append(report)
            print(json.dumps({k: v for k, v in report.items() if k != "output_sha256"}, ensure_ascii=False), flush=True)

            # Six native key poses, shown in their source row-major order.
            tile_w, tile_h, label_h = 320, 347, 22
            contact = Image.new("RGB", (3 * tile_w, 2 * (tile_h + label_h)), (234, 237, 240))
            draw = ImageDraw.Draw(contact)
            for i, key in enumerate(keyframes):
                col, row = i % 3, i // 3
                x, y = col * tile_w, row * (tile_h + label_h)
                draw.text((x + 8, y + 4), f"Keyframe {i + 1}", fill=(36, 41, 47))
                thumb = key.resize((tile_w, tile_h), Image.Resampling.LANCZOS)
                rgba_bg = Image.new("RGBA", thumb.size, (234, 237, 240, 255))
                rgba_bg.alpha_composite(thumb)
                contact.paste(rgba_bg.convert("RGB"), (x, y + label_h))
            contact.save(preview_dir / f"{name}-keyframes.png")

        labels = {"home_waking_up": "Bangun tidur", "home_cooking_stir": "Memasak",
                  "home_sweeping": "Menyapu", "home_watering_plants": "Menyiram tanaman",
                  "home_hanging_laundry": "Menjemur pakaian"}
        thumbs = {}
        for name, sequence in all_preview_frames.items():
            thumbs[name] = []
            for frame in sequence:
                thumb = frame.resize((288, 312), Image.Resampling.LANCZOS)
                bg = Image.new("RGBA", thumb.size, (234, 237, 240, 255))
                bg.alpha_composite(thumb)
                thumbs[name].append(bg.convert("RGB"))
        combined = []
        for i in range(FRAME_COUNT):
            canvas = Image.new("RGB", (len(selected) * 288, 348), (234, 237, 240))
            draw = ImageDraw.Draw(canvas)
            for col, name in enumerate(selected):
                draw.text((col * 288 + 12, 10), labels[name], fill=(36, 41, 47))
                canvas.paste(thumbs[name][i], (col * 288, 36))
            combined.append(canvas)
        preview_stem = "friday-five-activities" if tuple(selected) == CLIPS else "friday-selected-activities"
        combined_gif = preview_dir / f"{preview_stem}.gif"
        gif_save(combined_gif, combined)
        combined[0].save(preview_dir / f"{preview_stem}.png")
        if shutil.which(args.ffmpeg) is None and not Path(args.ffmpeg).exists():
            raise FileNotFoundError(f"ffmpeg not found: {args.ffmpeg}")
        mp4 = preview_dir / f"{preview_stem}.mp4"
        render_mp4(mp4, combined, args.ffmpeg)
        (DERIVED / "validation.json").write_text(json.dumps(reports, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"combined_gif": str(combined_gif.relative_to(ROOT)),
                          "combined_mp4": str(mp4.relative_to(ROOT)), "report": str((DERIVED / 'validation.json').relative_to(ROOT))}), flush=True)
        return 0
    except Exception as exc:
        print(f"assemble_friday_action_sheets: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
