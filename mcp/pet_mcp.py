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
    "home_cooking_stir": "memasak dan mengaduk",
    "home_washing_dishes": "mencuci piring",
    "home_wiping_counter": "mengelap meja",
    "home_folding_laundry": "melipat cucian",
    "home_washing_hair": "membilas rambut",
}

# Nama protokol di AGENTS.md ditulis ke pet sebagai gestur yang punya frame.
POSE_ALIASES = {
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
    return list(POSES.keys())


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
            "description": "Tampilkan semua gestur yang bisa dilakukan si pet.",
            "inputSchema": {"type": "object", "properties": {}},
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
    if name == "play_pose":
        requested: list[str] = []
        single = arguments.get("pose")
        if isinstance(single, str) and single:
            requested.append(single)
        many = arguments.get("poses")
        if isinstance(many, list):
            requested.extend(str(item) for item in many if item)

        if not requested:
            return error_result("Sebutkan minimal satu gestur, misalnya \"duduk\".")

        unknown = [item for item in requested if normalize_pose(item) not in POSES]
        if unknown:
            return error_result(
                "Gestur tidak dikenal: " + ", ".join(unknown)
                + ". Yang tersedia: " + ", ".join(visible_poses()) + "."
            )

        if not is_running():
            return error_result(
                "Pet sedang tidak jalan. Jalankan start_pet dulu."
            )

        for item in requested:
            send_pose(item)

        described = ", ".join(
            f"{normalize_pose(item)} ({POSES[normalize_pose(item)]})" for item in requested
        )
        return text_result(f"Gestur dikirim ke pet: {described}.")

    if name == "list_poses":
        lines = [f"- {key}: {value}" for key, value in POSES.items()]
        return text_result("Gestur yang tersedia:\n" + "\n".join(lines))

    if name == "get_pet_status":
        config = read_config()
        status = "jalan" if is_running() else "mati"
        pid = pet_pid()
        models = config.get("models") or []
        current = config.get("model") or "(default OpenCode)"
        detail = [
            f"Status: {status}" + (f" (pid {pid})" if pid else ""),
            f"Model aktif: {current}",
            f"Model tersedia: {', '.join(models) if models else '(tidak ada)'}",
            f"Gestur tersedia: {', '.join(visible_poses())}",
        ]
        return text_result("\n".join(detail))

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
