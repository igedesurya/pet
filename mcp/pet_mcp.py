#!/usr/bin/env python3
"""Server MCP kecil untuk menggerakkan Pet Asisten.

Menyediakan tool supaya agent (OpenCode, dsb.) bisa memerintah si pet:
memutar gestur, membuka chat, mengganti ukuran, menyembunyikan, dan
mengetahuinya lewat get_pet_status.

Protokol: MCP stdio (JSON-RPC 2.0, dibatasi newline).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

PET_DIR = Path(__file__).resolve().parent.parent   # root project pet
PET_HOME = Path.home() / ".pet"
COMMAND_FILE = PET_HOME / "poses.command"
CONFIG_FILE = PET_HOME / "config.json"

# Gestur yang dikenal; harus cocok dengan PetPose di Sources/PetState.swift
POSES: dict[str, str] = {
    "duduk": "duduk bersila (ditahan beberapa detik)",
    "ketawa": "tertawa",
    "peluk": "membuka tangan untuk memeluk",
    "lompat": "melompat",
    "lambai": "melambai",
    "cium": "meniup ciuman",
    "senyum": "senyum sambil isyarat OK",
    "sedih": "sedih (ditahan beberapa detik)",
    "menunggu": "berdiri menunggu",
    "bicara": "sedang berbicara",
    "telutut": "tangan di lutut (ditahan beberapa detik)",
    "regang": "duduk regang (ditahan beberapa detik)",
    "skin_base": "berdiri dengan bikini putih",
    "interaksi_bawah_1": "duduk, tangan di lutut, bikini putih",
    "interaksi_bawah_2": "duduk, tangan di paha, bikini putih",
    "mood_intense": "ekspresi hangat dengan bikini putih",
    "pegang_memek": "sama dengan interaksi_bawah_1",
    "mainkan_anal": "sama dengan interaksi_bawah_2",
    "hide_clothes": "sama dengan skin_base",
    "horny": "sama dengan mood_intense",
    "orgasme": "sama dengan mood_intense",
    "gym_barbell_squat": "squat barbel",
    "gym_leg_press": "leg press",
    "gym_biceps_curl": "curl bisep",
    "gym_shoulder_press": "angkat bahu",
    "gym_lat_pulldown": "lat pulldown",
    "gym_seated_row": "seated row",
    "gym_treadmill_walk": "jalan di treadmill",
    "gym_stationary_cycle": "sepeda statis",
    "home_sweeping": "menyapu lantai",
    "home_watering_plants": "menyiram tanaman",
    "home_hanging_laundry": "menjemur pakaian di jemuran",
    "home_cooking_stir": "memasak dan mengaduk",
    "home_washing_dishes": "mencuci piring",
    "home_wiping_counter": "mengelap meja",
    "home_folding_laundry": "melipat cucian",
    "home_washing_hair": "membilas rambut",
    "home_drinking_tea": "minum teh (paket Nori rumah)",
    "home_reading_book": "membaca buku (paket Nori rumah)",
    "home_eating": "makan (paket Nori rumah)",
    "home_waking_up": "bangun dan meregangkan badan",
    "home_sleeping": "tidur santai (paket Nori rumah)",
    "pesona_wave": "melambai sambil duduk" ,
    "pesona_nod": "mengangguk setuju" ,
    "pesona_shrug": "mengangkat bahu" ,
    "pesona_check_watch": "melihat jam tangan" ,
    "pesona_hand_heart": "membentuk hati dengan tangan" ,
    "pesona_listening_v2": "mendengarkan dengan perhatian (Pesona v2)",
    "pesona_thinking_v2": "berpikir sambil menyentuh pelipis (Pesona v2)",
    "pesona_typing_v2": "mengetik di laptop (Pesona v2)",
    "pesona_breathing_v2": "bernapas santai (Pesona v2)",
    "pesona_clapping_v2": "tepuk tangan kecil menyemangati (Pesona v2)",
    "pesona_v2": "peregangan duduk versi dewasa dengan tanktop krem",
    "pesona_rest_v2": "istirahat duduk versi dewasa dengan tanktop krem",
    "pesona_hair_v2": "merapikan rambut versi dewasa dengan tanktop krem",
    "pesona_knee_v2": "menyesuaikan postur duduk versi dewasa dengan tanktop krem",
    "pesona": "duduk menghadap depan, kaki terbuka lebar, tangan ke atas lalu ke bawah (paket Pesona)",
    "pesona_rest": "duduk diam menatap, kaki terbuka lebar (paket Pesona)",
    "pesona_hair": "merapikan rambut sambil duduk, kaki terbuka lebar (paket Pesona)",
    "pesona_knee": "angkat satu kaki lalu berpangku tangan di lutut (paket Pesona)",
}

# Nama protokol di AGENTS.md ditulis ke pet sebagai gestur yang punya frame.
POSE_ALIASES = {
    "bangun_tidur": "home_waking_up",
    "masak": "home_cooking_stir",
    "nyapu": "home_sweeping",
    "nyiram_tanaman": "home_watering_plants",
    "jemur_pakaian": "home_hanging_laundry",
    "jemur": "home_hanging_laundry",
    "hide_clothes": "skin_base",
    "horny": "mood_intense",
    "orgasme": "mood_intense",
    "pegang_memek": "interaksi_bawah_1",
    "mainkan_anal": "interaksi_bawah_2",
}

SERVER_NAME = "pet"
SERVER_VERSION = "0.1.0"
PROTOCOL_VERSION = "2024-11-05"


# ---------------------------------------------------------------- utilitas pet


def is_running() -> bool:
    try:
        result = subprocess.run(
            ["pgrep", "-f", "Pet.app/Contents/MacOS/pet"],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.returncode == 0 and result.stdout.strip() != ""
    except OSError:
        return False


def normalize_pose(pose: str) -> str:
    key = pose.strip().lower().replace("-", "_").replace(" ", "_")
    return POSE_ALIASES.get(key, key)


def send_pose(pose: str) -> None:
    PET_HOME.mkdir(parents=True, exist_ok=True)
    with COMMAND_FILE.open("a", encoding="utf-8") as handle:
        handle.write(normalize_pose(pose) + "\n")


def pet_pid() -> str | None:
    try:
        result = subprocess.run(
            ["pgrep", "-f", "Pet.app/Contents/MacOS/pet"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    pid = result.stdout.strip().split("\n")[0] if result.stdout.strip() else ""
    return pid or None


def read_config() -> dict[str, Any]:
    if not CONFIG_FILE.exists():
        return {}
    try:
        return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def visible_poses() -> list[str]:
    return sorted({name for pack in character_catalog() for name in
                   [*(pose["name"] for pose in pack["poses"]), *pack["aliases"]]})


LEGACY_CLIPS = {
    "duduk": "sitting", "ketawa": "laughing", "peluk": "hug",
    "lompat": "jumping", "lambai": "waving", "cium": "kiss",
    "senyum": "okay-smile", "sedih": "failed", "menunggu": "waiting",
    "bicara": "talking", "telutut": "hand-on-knee", "regang": "seated-split",
    **POSE_ALIASES,
}
# Mirror CharacterSprite.fallbackAlias; report aliases separately from actual assets.
FALLBACK_CLIPS = {
    "talking": "waiting", "kiss": "waving", "hug": "idle",
    "okay-smile": "idle", "laughing": "idle", "sitting": "seated-double-leg-raise",
    "seated-split": "standby-stretch", "hand-on-knee": "standby-stretch",
    "skin_base": "idle", "interaksi_bawah_1": "seated-double-leg-raise",
    "interaksi_bawah_2": "seated-straddle-leg-raise", "mood_intense": "idle",
}


def character_catalog() -> list[dict[str, Any]]:
    """Discover installed assets, falling back to source for an unbuilt checkout."""
    bundled = PET_DIR / "bin/Pet.app/Contents/Resources"
    resource = bundled if (bundled / "character").is_dir() else PET_DIR / "Resources"
    roots = [("nori", "Nori", resource / "character")]
    extra = resource / "characters"
    if extra.is_dir():
        roots.extend((p.name, p.name, p) for p in sorted(extra.iterdir()) if p.is_dir() and p.name != "nori")
    catalog = []
    for identifier, label, root in roots:
        if not root.is_dir():
            continue
        try:
            metadata = json.loads((root / "pack.json").read_text(encoding="utf-8"))
            if not isinstance(metadata, dict):
                metadata = {}
        except (OSError, json.JSONDecodeError):
            metadata = {}
        poses = []
        for folder in sorted(root.iterdir()):
            if not folder.is_dir():
                continue
            frames = list(folder.glob("*.png"))
            if frames:
                poses.append({"name": folder.name, "frames": len(frames),
                              "description": POSES.get(normalize_pose(folder.name), folder.name.replace("_", " ").replace("-", " "))})
        canonical = {normalize_pose(p["name"]): p["name"] for p in poses}
        available = dict(canonical)
        for alias, target in FALLBACK_CLIPS.items():
            key = normalize_pose(alias)
            if key not in available and normalize_pose(target) in available:
                available[key] = available[normalize_pose(target)]
        for alias, target in LEGACY_CLIPS.items():
            if normalize_pose(target) in available:
                available[alias] = available[normalize_pose(target)]
        aliases = {key: target for key, target in available.items() if key != target}
        modes = metadata.get("modes", [])
        if not isinstance(modes, list):
            modes = []
        catalog.append({"id": identifier, "name": metadata.get("label") or label,
                        "poses": poses, "aliases": aliases, "standby_modes": modes})
    return catalog


def find_character(raw: str, catalog: list[dict[str, Any]]) -> dict[str, Any] | None:
    key = normalize_pose(raw)
    return next((pack for pack in catalog if key in
                 (normalize_pose(pack["id"]), normalize_pose(pack["name"]))), None)


def resolve_clip(pack: dict[str, Any], pose: str) -> str | None:
    key = normalize_pose(pose)
    actual = {normalize_pose(item["name"]): item["name"] for item in pack["poses"]}
    return actual.get(key) or pack["aliases"].get(key)


def request_pet(payload: dict[str, Any], timeout: float = 5.0) -> dict[str, Any]:
    """Queue atomically and wait for the running app's acknowledgement."""
    requests = PET_HOME / "command-requests"
    results = PET_HOME / "command-results"
    requests.mkdir(parents=True, exist_ok=True)
    results.mkdir(parents=True, exist_ok=True)
    identifier = str(uuid.uuid4())
    pending = requests / (identifier + ".json")
    temporary = requests / (identifier + ".tmp")
    answer = results / pending.name
    temporary.write_text(json.dumps(payload), encoding="utf-8")
    temporary.replace(pending)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            response = json.loads(answer.read_text(encoding="utf-8"))
        except FileNotFoundError:
            time.sleep(0.05)
            continue
        answer.unlink(missing_ok=True)
        return response
    pending.unlink(missing_ok=True)
    return {"ok": False, "error": "Pet belum mengonfirmasi perintah. Pastikan aplikasi sudah memakai build terbaru; perintah mungkin sedang diproses."}


def json_result(payload: dict[str, Any]) -> dict[str, Any]:
    return text_result(json.dumps(payload, ensure_ascii=False, indent=2))


# ------------------------------------------------------------------- tool MCP


def tool_definitions() -> list[dict[str, Any]]:
    return [
        {
            "name": "play_pose",
            "description": (
                "Putar gestur si pet. Pakai ini ketika pengguna meminta pet "
                "melakukan sesuatu seperti duduk, ketawa, melambai, atau peluk."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "character": {
                        "type": "string",
                        "description": "ID atau nama karakter dari list_characters. Karakter diganti langsung sebelum pose diputar.",
                    },
                    "pose": {
                        "type": "string",
                        "enum": visible_poses(),
                        "description": "Nama gestur yang ingin diputar.",
                    },
                    "poses": {
                        "type": "array",
                        "items": {"type": "string", "enum": visible_poses()},
                        "description": "Beberapa gestur sekaligus, dijalankan berurutan.",
                    },
                },
            },
        },
        {
            "name": "list_poses",
            "description": "Katalog pose aktual dan alias per karakter; tanpa character menampilkan semua karakter.",
            "inputSchema": {"type": "object", "properties": {
                "character": {"type": "string", "description": "ID atau nama karakter (opsional)."}
            }},
        },
        {
            "name": "list_characters",
            "description": "Daftar semua karakter, nama pose aktual, jumlah frame, alias dan mode standby. Dibaca langsung dari aset terpasang.",
            "inputSchema": {"type": "object", "properties": {}},
        },
        {
            "name": "set_pet_character",
            "description": "Ganti karakter pet langsung tanpa restart. Pilih ID dari list_characters.",
            "inputSchema": {"type": "object", "properties": {
                "character": {"type": "string"}
            }, "required": ["character"]},
        },
        {
            "name": "get_pet_status",
            "description": (
                "Cek keadaan si pet: apakah sedang jalan, model apa yang dipakai, "
                "dan gestur apa saja yang tersedia."
            ),
            "inputSchema": {"type": "object", "properties": {}},
        },
        {
            "name": "open_pet_chat",
            "description": "Munculkan si pet dan buka panel chat-nya.",
            "inputSchema": {"type": "object", "properties": {}},
        },
        {
            "name": "show_pet",
            "description": "Munculkan kembali si pet kalau sedang disembunyikan.",
            "inputSchema": {"type": "object", "properties": {}},
        },
        {
            "name": "set_pet_size",
            "description": "Atur besar kecil karakter pet (0.5 sampai 2.0).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "scale": {
                        "type": "number",
                        "minimum": 0.5,
                        "maximum": 2.0,
                        "description": "1.0 = ukuran normal.",
                    }
                },
                "required": ["scale"],
            },
        },
        {
            "name": "start_pet",
            "description": "Nyalakan Pet Asisten kalau sedang tidak jalan.",
            "inputSchema": {"type": "object", "properties": {}},
        },
    ]


def text_result(text: str) -> dict[str, Any]:
    return {"content": [{"type": "text", "text": text}]}


def error_result(text: str) -> dict[str, Any]:
    return {"content": [{"type": "text", "text": text}], "isError": True}


def call_tool(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name in ("list_characters", "list_poses"):
        catalog = character_catalog()
        raw = arguments.get("character")
        if raw is not None:
            if not isinstance(raw, str) or not (pack := find_character(raw, catalog)):
                return error_result("Karakter tidak dikenal. Gunakan list_characters.")
            catalog = [pack]
        return json_result({"characters": catalog})

    if name == "set_pet_character":
        raw = arguments.get("character")
        catalog = character_catalog()
        if not isinstance(raw, str) or not (pack := find_character(raw, catalog)):
            return error_result("Karakter tidak dikenal. Gunakan list_characters.")
        if not is_running():
            return error_result("Pet sedang tidak jalan. Jalankan start_pet dulu.")
        response = request_pet({"action": "character", "character": pack["id"]})
        return json_result(response) if response.get("ok") else error_result(response.get("error", "Gagal mengganti karakter."))

    if name == "play_pose":
        requested = []
        single = arguments.get("pose")
        if isinstance(single, str) and single.strip():
            requested.append(single)
        many = arguments.get("poses")
        if many is not None:
            if not isinstance(many, list) or not all(isinstance(item, str) and item.strip() for item in many):
                return error_result("poses harus berupa daftar nama pose yang tidak kosong.")
            requested.extend(many)
        if not requested:
            return error_result('Sebutkan minimal satu gestur, misalnya "duduk".')
        if not is_running():
            return error_result("Pet sedang tidak jalan. Jalankan start_pet dulu.")
        catalog = character_catalog()
        explicit = arguments.get("character")
        if explicit is not None:
            if not isinstance(explicit, str) or not (pack := find_character(explicit, catalog)):
                return error_result("Karakter tidak dikenal. Gunakan list_characters.")
        else:
            status = request_pet({"action": "status"})
            if not status.get("ok"):
                return error_result(status.get("error", "Gagal membaca karakter aktif."))
            pack = find_character(status["character"], catalog)
            if not pack or not all(resolve_clip(pack, pose) for pose in requested):
                candidates = [item for item in catalog if all(resolve_clip(item, pose) for pose in requested)]
                if len(candidates) != 1:
                    choices = ", ".join(item["id"] for item in candidates)
                    return error_result("Pilih character untuk pose ini: " + (choices or "tidak ada karakter yang menyediakan semua pose tersebut") + ". Gunakan list_characters.")
                pack = candidates[0]
        missing = [pose for pose in requested if not resolve_clip(pack, pose)]
        if missing:
            return error_result("Pose tidak tersedia di " + pack["id"] + ": " + ", ".join(missing) + ". Gunakan list_poses dengan character yang sama.")
        clips = [resolve_clip(pack, pose) for pose in requested]
        response = request_pet({"action": "play", "character": pack["id"], "poses": clips})
        if not response.get("ok"):
            return error_result(response.get("error", "Gagal memutar pose."))
        response["accepted_poses"] = clips
        response["message"] = "Pose pertama dimulai; pose berikutnya diantrekan dan diputar berurutan."
        return json_result(response)

    if name == "get_pet_status":
        config = read_config()
        response = {"running": is_running(), "pid": pet_pid(),
                    "agent": config.get("agent", "opencode"), "model": config.get("model"),
                    "characters": [{"id": item["id"], "name": item["name"], "pose_count": len(item["poses"])}
                                   for item in character_catalog()]}
        if response["running"]:
            status = request_pet({"action": "status"})
            response["app"] = status
        return json_result(response)

    if name == "open_pet_chat":
        if not is_running():
            return error_result("Pet sedang tidak jalan. Jalankan start_pet dulu.")
        subprocess.Popen(["open", str(PET_DIR / "bin" / "Pet.app")])
        (PET_HOME / "show.request").touch()
        return text_result("Pet dimunculkan. Panel chat bisa dibuka dengan mengklik karakternya.")

    if name == "show_pet":
        if not is_running():
            return error_result("Pet sedang tidak jalan. Jalankan start_pet dulu.")
        PET_HOME.mkdir(parents=True, exist_ok=True)
        (PET_HOME / "show.request").touch()
        return text_result("Pet dimunculkan kembali.")

    if name == "set_pet_size":
        raw = arguments.get("scale")
        try:
            scale = float(raw)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            return error_result("Nilai scale harus berupa angka antara 0.5 dan 2.0.")
        if not 0.5 <= scale <= 2.0:
            return error_result("Nilai scale harus antara 0.5 dan 2.0.")

        if not is_running():
            return error_result("Pet sedang tidak jalan. Jalankan start_pet dulu.")

        # UserDefaults app disimpan dengan bundle id com.surya.pet
        subprocess.run(
            ["defaults", "write", "com.surya.pet", "pet.scale", "-float", str(scale)],
            check=False,
        )
        # ukuran dibaca saat aplikasi mulai, jadi perlu dijalankan ulang
        subprocess.run(["pkill", "-f", "Pet.app/Contents/MacOS/pet"], check=False)

        # beri jeda supaya proses lama benar-benar berhenti sebelum diluncurkan lagi
        for _ in range(20):
            time.sleep(0.25)
            probe = subprocess.run(
                ["pgrep", "-f", "Pet.app/Contents/MacOS/pet"],
                capture_output=True,
                text=True,
                check=False,
            )
            if probe.stdout.strip() == "":
                break

        subprocess.Popen(["open", str(PET_DIR / "bin" / "Pet.app")])
        time.sleep(1.0)

        state = "jalan" if is_running() else "GAGAL dijalankan ulang"
        return text_result(
            f"Ukuran pet diatur ke {scale:.2f}x. Pet dijalankan ulang — status: {state}."
        )

    if name == "start_pet":
        if is_running():
            return text_result("Pet sudah jalan.")
        subprocess.Popen([str(PET_DIR / "run.sh")])
        return text_result("Pet dinyalakan.")

    return error_result(f"Tool tidak dikenal: {name}")


# --------------------------------------------------------------- loop MCP stdio


def write_message(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def handle_request(message: dict[str, Any]) -> dict[str, Any] | None:
    method = message.get("method")
    request_id = message.get("id")

    # notifikasi (tanpa id) tidak dibalas
    if method == "notifications/initialized":
        return None

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        }

    if method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {"tools": tool_definitions()},
        }

    if method == "tools/call":
        params = message.get("params") or {}
        name = params.get("name", "")
        arguments = params.get("arguments") or {}
        result = call_tool(name, arguments)
        return {"jsonrpc": "2.0", "id": request_id, "result": result}

    if method == "ping":
        return {"jsonrpc": "2.0", "id": request_id, "result": {}}

    if request_id is None:
        return None

    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    }


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        try:
            response = handle_request(message)
        except Exception as exc:  # noqa: BLE001 - server tidak boleh mati
            request_id = message.get("id")
            response = {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32603, "message": f"Kesalahan internal: {exc}"},
            }
        if response is not None:
            write_message(response)


if __name__ == "__main__":
    main()
