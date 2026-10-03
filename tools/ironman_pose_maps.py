#!/usr/bin/env python3
"""Render OpenPose BODY_18 conditioning maps for the planned Iron Man clips.

The maps are plain colored stick figures on black 512x768 canvases.  Coordinates
are authored in a shared standing-space, so jumps/flight change actual body
height while grounded clips keep a common foot line.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / "artwork/iron-man-action/plan.json"
OUT = ROOT / "artwork/iron-man-action/pose-maps"
SPECS = ROOT / "artwork/iron-man-action/pose-specs.json"
W, H = 512, 768

# BODY_18 indices: nose, neck, R shoulder/elbow/wrist, L shoulder/elbow/wrist,
# R hip/knee/ankle, L hip/knee/ankle, R eye/L eye/R ear/L ear.
LIMBS = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7),
         (1, 8), (8, 9), (9, 10), (1, 11), (11, 12), (12, 13),
         (1, 0), (0, 14), (14, 16), (0, 15), (15, 17), (2, 16), (5, 17)]
COLORS = [(255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0),
          (170, 255, 0), (85, 255, 0), (0, 255, 0), (0, 255, 85),
          (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255),
          (0, 0, 255), (85, 0, 255), (170, 0, 255), (255, 0, 255),
          (255, 0, 170), (255, 0, 85), (153, 153, 153)]

# Each arm gives (elbow dx,dy, wrist dx,dy) from its shoulder.
ARM = {
    "down": ((-18, 72, -16, 139), (18, 72, 16, 139)),
    "ready": ((-30, 45, -44, 80), (30, 45, 44, 80)),
    "guard": ((-20, 50, -5, 91), (20, 50, 5, 91)),
    "load": ((-48, 75, -65, 105), (48, 75, 65, 105)),
    "lift_right": ((-5, 40, 18, 8), (18, 72, 15, 139)),
    "lift_left": ((-18, 72, -15, 139), (5, 40, -18, 8)),
    "aim_right": ((4, 34, 63, 4), (22, 65, 48, 104)),
    "recoil_right": ((-2, 44, 25, 23), (26, 74, 44, 128)),
    "reach_right": ((5, 20, 77, -15), (36, 63, 57, 113)),
    "reach_left": ((-35, 62, -57, 112), (-4, 20, -77, -15)),
    "wide": ((-16, 16, -55, -4), (16, 16, 55, -4)),
    "wide_low": ((-14, 40, -58, 65), (14, 40, 58, 65)),
    "cross": ((-7, 35, 25, 72), (7, 35, -25, 72)),
    "protect": ((-6, 13, 24, 49), (6, 13, -24, 49)),
    "holo": ((-22, 57, -15, 112), (3, 30, 42, 21)),
    "point_holo": ((-18, 72, -15, 139), (-1, 22, 48, 38)),
    "charge_low": ((-14, 48, 8, 80), (14, 48, -8, 80)),
    "charge_high": ((-13, 28, 7, 58), (13, 28, -7, 58)),
    "palm_low": ((-16, 42, -32, 45), (16, 42, 32, 45)),
    "palm_lowered": ((-16, 49, -32, 59), (16, 49, 32, 59)),
    "palm_high": ((-13, 25, -34, 28), (13, 25, 34, 28)),
    "wind_right": ((-31, 45, -48, 23), (27, 63, 44, 109)),
    "wind_left": ((-27, 63, -44, 109), (31, 45, 48, 23)),
    "punch_right": ((-1, 36, 83, 25), (28, 68, 48, 124)),
    "punch_left": ((-28, 68, -48, 124), (1, 36, -83, 25)),
    "brake": ((-17, 26, -48, 13), (17, 26, 48, 13)),
    "fly": ((-20, 35, -58, 54), (20, 35, 58, 54)),
    "sprint": ((-34, 20, -58, -3), (31, 83, 48, 127)),
    "sprint_alt": ((-31, 83, -48, 127), (34, 20, 58, -3)),
    "balance": ((-23, 55, -48, 76), (23, 28, 50, 4)),
    "rise": ((-22, 47, -27, 7), (22, 47, 27, 7)),
    "ground_touch": ((-18, 65, -10, 220), (18, 72, 16, 139)),
}

# Hip-relative knee/ankle positions; shared standing baseline is y=704.
LEG = {
    "stand": ((-3, 150, -8, 333), (3, 150, 8, 333)),
    "soft": ((-8, 126, -8, 333), (8, 126, 8, 333)),
    "crouch": ((-45, 91, -61, 332), (44, 91, 59, 332)),
    "deep": ((-58, 72, -82, 326), (51, 89, 79, 332)),
    "air_tuck": ((-48, 103, -77, 175), (47, 99, 75, 183)),
    "air_descend": ((-24, 130, -38, 278), (27, 134, 42, 284)),
    "landing": ((-48, 94, -61, 332), (48, 93, 62, 332)),
    "flight_bend": ((-29, 126, -52, 269), (29, 125, 52, 270)),
    "flight_back": ((-6, 180, -43, 270), (9, 192, -79, 270)),
    "flight_straight": ((-3, 180, -28, 280), (8, 184, -72, 280)),
    "dash_back": ((-26, 130, -58, 250), (34, 91, 51, 171)),
    "dash_brake": ((-40, 96, -29, 249), (37, 125, 70, 330)),
    "stride_a": ((-41, 120, -72, 249), (44, 154, 65, 333)),
    "stride_b": ((-43, 159, -59, 333), (51, 112, 81, 240)),
    "stride_c": ((-45, 148, -22, 331), (48, 147, 19, 333)),
    "stride_d": ((-50, 115, -81, 237), (42, 162, 57, 333)),
    "stride_e": ((-52, 160, -63, 333), (41, 119, 74, 246)),
    "stride_f": ((-47, 146, -17, 333), (45, 151, 25, 333)),
    "punch_brace": ((-23, 158, -55, 333), (24, 147, 28, 333)),
    "landing_three": ((-40, 86, -53, 283), (53, 137, 75, 333)),
    "rise_knee": ((-34, 137, -69, 333), (38, 137, 49, 333)),
}

# Phase rows: arm preset, leg preset, body y, torso lean, torso drop, head yaw,
# x shift, and a concise natural-language description of this exact phase.
def phase(arms, legs, prompt, *, y=0, lean=0, drop=0, head=0, x=0,
          pelvis=0, pitch=0, compress=0):
    return dict(arms=arms, legs=legs, prompt=prompt, y=y, lean=lean,
                drop=drop, head=head, x=x, pelvis=pelvis, pitch=pitch,
                compress=compress)

CLIPS = {
 "action_ready": [
  phase("down","soft","Upright alert stance with both arms relaxed low."),
  phase("lift_right","soft","Turns helmet right and raises the right forearm near the chest.",head=16),
  phase("guard","crouch","Pivots slightly right into a compact two-fist guard.",lean=5,head=12,pelvis=32,drop=12),
  phase("lift_left","soft","Scans left while the left forearm rises and the right arm lowers.",head=-18),
  phase("down","stand","Straightens the knees as both arms lower and shoulders settle.",drop=-4),
  phase("down","soft","Returns to the upright relaxed ready stance.",head=3)],
 "action_repulsor_shoot": [
  phase("down","soft","Faces three-quarter right with knees soft and arms low."),
  phase("lift_right","soft","Lifts the right elbow and turns its palm toward the target.",head=8),
  phase("aim_right","punch_brace","Fully extends the right arm toward upper right while the left arm counterbalances.",lean=7,head=10),
  phase("recoil_right","punch_brace","Braces the firing arm with a short cyan repulsor beam flashing from the right palm and a slight torso recoil.",lean=-3,drop=5,head=8),
  phase("aim_right","soft","Retracts the right elbow as the torso recovers." ,lean=3),
  phase("down","soft","Lowers the right arm back to the relaxed ready stance.",head=-3)],
 "action_jump": [
  phase("ready","soft","Stands with softly bent knees and arms ready."),
  phase("load","deep","Drops into a deep crouch and sweeps both arms backward to load the jump.",drop=22,pelvis=54),
  phase("wide","air_descend","Rises airborne with a lengthened torso and both arms lifting.",y=-42,drop=-10),
  phase("balance","air_tuck","Reaches the jump apex with both knees tucked and arms balancing wide.",y=-35,drop=-18),
  phase("reach_right","air_descend","Descends with boots angled down and knees preparing to bend.",y=-34,drop=-8),
  phase("balance","landing","Touches down in a deep bent-knee landing with one hand balancing forward.",drop=14,pelvis=45)],
 "action_flight": [
  phase("wide_low","flight_bend","Hovers upright with arms slightly out, legs hanging bent, and cyan boot jets glowing.",y=-20),
  phase("wide","flight_bend","Ascends a little with wider arms, lightly bent knees, and brighter cyan boot jets.",y=-30,pitch=7),
  phase("fly","flight_back","Tilts forward into flight with legs swept behind, arms steering, and cyan boot jets.",y=-32,lean=5,pitch=27),
  phase("fly","flight_straight","Stretches into a faster forward tilt with legs trailing together and long cyan boot exhaust.",y=-38,lean=7,pitch=39),
  phase("brake","flight_bend","Brakes toward upright, bends knees, brings arms forward, and shortens the boot jets.",y=-25,lean=3,pitch=15),
  phase("wide_low","flight_bend","Returns to an upright hover with arms lowered and compact cyan boot jets.",y=-18,head=3)],
 "action_landing": [
  phase("wide_low","flight_bend","Hovers low upright with legs bent beneath the body.",y=-30),
  phase("balance","landing_three","Drops with the right knee folding and left boot reaching ground.",y=-15),
  phase("ground_touch","landing_three","Settles into a low three-point landing with the right fist touching near the ground.",pelvis=180,pitch=80,compress=50,x=-8),
  phase("balance","landing_three","Lifts the helmet and chest while staying close to the ground.",drop=5,head=5,pelvis=115,pitch=58,compress=25,x=-5),
  phase("rise","rise_knee","Rises onto the left leg and draws the right arm back.",drop=-3),
  phase("down","soft","Finishes standing ready with both arms lowered.")],
 "action_running": [
  phase("sprint","stride_a","Runs with left foot forward, right leg back, and opposing arm swing.",lean=13),
  phase("sprint_alt","stride_b","Lands on the left foot as the right knee lifts forward.",lean=10),
  phase("sprint","stride_c","Passes through midflight with the right knee ahead and left leg trailing.",y=-24,lean=14),
  phase("sprint_alt","stride_d","Swings the right foot forward and the left leg back.",lean=13),
  phase("sprint","stride_e","Lands on the right foot with the left knee lifted.",lean=10),
  phase("sprint_alt","stride_f","Passes through midflight with the left knee forward and right leg trailing.",y=-24,lean=14)],
 "action_dash": [
  phase("ready","soft","Starts in a low ready stance."),
  phase("load","crouch","Leans sharply forward, loads one bent knee, and sweeps arms back.",lean=14,drop=12,pelvis=38,pitch=13),
  phase("sprint","dash_back","Dashes airborne to the right with legs stretched behind and arms streamlined.",lean=4,pitch=34,y=-35,x=8),
  phase("brake","dash_brake","Pulls both knees forward and spreads the hands to brake.",lean=7,pitch=18,y=-18,x=6),
  phase("balance","crouch","Skids into a low bent-knee stance with one arm reaching forward.",lean=8,pelvis=35),
  phase("down","soft","Straightens into the recovered ready stance.")],
 "action_punch": [
  phase("guard","punch_brace","Holds a compact boxing guard with both elbows bent."),
  phase("wind_right","punch_brace","Winds the right fist behind the shoulder and twists the waist.",lean=-9,head=8),
  phase("punch_right","punch_brace","Drives a straight right punch forward over a braced front leg.",lean=10,head=12),
  phase("guard","punch_brace","Withdraws the right fist as the left shoulder rotates forward.",lean=-4),
  phase("punch_left","punch_brace","Extends the left fist while rotating the torso the opposite way.",lean=-10,head=-8),
  phase("guard","soft","Returns both fists to the boxing guard.")],
 "action_block": [
  phase("down","soft","Stands upright in a neutral ready position."),
  phase("guard","crouch","Raises both elbows toward the chest and bends the knees.",pelvis=25,drop=10),
  phase("cross","deep","Crosses both forearms high before the faceplate in a deep brace.",drop=4,pelvis=48),
  phase("protect","crouch","Leans back under an imagined impact with forearms shielding the head.",lean=-8,head=-5,pelvis=24,drop=7),
  phase("guard","soft","Separates the forearms into a protective guard."),
  phase("down","soft","Lowers both arms and returns to ready.",head=3)],
 "action_chest_blast": [
  phase("down","soft","Stands ready with arms low and chest centered."),
  phase("charge_low","soft","Curls both fists near the hips as the chest charge builds."),
  phase("wide","soft","Spreads both arms outward with palms turned back and chest bright.",lean=2),
  phase("recoil_right","punch_brace","Braces and recoils slightly as a short cyan beam releases from the chest reactor.",lean=-8,drop=5),
  phase("wide_low","soft","Lets the blast fade and begins lowering both arms."),
  phase("down","soft","Returns arms low as the chest settles to its normal glow.",head=3)],
 "action_scan": [
  phase("down","soft","Looks forward with both arms relaxed at the sides."),
  phase("holo","soft","Turns the helmet right and lifts the left hand near the chest.",head=15),
  phase("holo","soft","Holds the raised left palm beneath a small hologram ring.",head=12),
  phase("point_holo","soft","Dips the helmet toward the hologram and points into it with the right hand.",head=8,drop=5),
  phase("guard","soft","Retracts the pointing hand as the helmet turns forward and hologram fades."),
  phase("down","soft","Lowers the left arm to the original relaxed posture.",head=3)],
 "action_energy_charge": [
  phase("down","soft","Relaxes both arms by the sides."),
  phase("charge_low","soft","Bends both elbows and curls fists beside the hips."),
  phase("palm_low","soft","Opens both hands forward at waist height with faint palm energy."),
  phase("palm_high","soft","Raises both open palms near the chest with bright energy above them.",drop=-2),
  phase("palm_lowered","soft","Lowers the hands toward the waist as the energy subsides."),
  phase("down","soft","Relaxes both arms and returns palms to normal.",head=3)],
}


def build_joints(spec):
    """Return exactly 18 integer [x,y] points in BODY_18 order."""
    y, x = spec["y"], spec["x"]
    hip_y = 367 + y + spec["pelvis"]
    hip_r = (232 + x, hip_y)
    hip_l = (280 + x, hip_y)
    pitch = math.radians(spec["pitch"])
    c, s = math.cos(pitch), math.sin(pitch)

    def rotate(dx, dy):
        return dx*c - dy*s, dx*s + dy*c
    def add(origin, offset):
        return (round(origin[0] + offset[0]), round(origin[1] + offset[1]))

    # Adult-width shoulder girdle; pitch rotates the whole upper body about pelvis.
    torso_len = 186 - spec["compress"]
    neck_len = 203 - spec["compress"]
    torso_center_x = 256 + x + spec["lean"]
    pivot = (torso_center_x, hip_y)
    neck = add(pivot, rotate(0, -neck_len))
    shoulder_r = add(pivot, rotate(-66, -torso_len))
    shoulder_l = add(pivot, rotate(66, -torso_len))
    if spec["drop"]:
        neck = (neck[0], neck[1] + spec["drop"])
        shoulder_r = (shoulder_r[0], shoulder_r[1] + spec["drop"])
        shoulder_l = (shoulder_l[0], shoulder_l[1] + spec["drop"])

    def solve_bone(origin, target, lengths, bend_hint):
        """Place a joint between fixed-length adult limb segments."""
        ox, oy = origin; tx, ty = target
        vx, vy = tx-ox, ty-oy
        d = math.hypot(vx, vy)
        l1, l2 = lengths
        minimum, maximum = abs(l1-l2) + 1, l1+l2-1
        d2 = min(max(d, minimum), maximum)
        if d < 1e-6:
            vx, vy, d = 0, 1, 1
        else:
            vx, vy = vx/d, vy/d
        tx, ty = ox + vx*d2, oy + vy*d2
        along = (l1*l1 - l2*l2 + d2*d2) / (2*d2)
        height = math.sqrt(max(0, l1*l1 - along*along))
        ux, uy = vx, vy
        # Cross-product sign keeps elbows/knees on the requested side of the limb.
        sign = 1 if vx*bend_hint[1] - vy*bend_hint[0] >= 0 else -1
        joint = (ox + ux*along - uy*height*sign,
                 oy + uy*along + ux*height*sign)
        return (round(joint[0]), round(joint[1])), (round(tx), round(ty))

    right_arm, left_arm = ARM[spec["arms"]]
    def arm_points(shoulder, control, side):
        # Preset wrist targets and elbow side are rotated with the torso pitch.
        elbow_hint = rotate(control[0], control[1])
        wrist_vec = rotate(control[2], control[3])
        target = (shoulder[0] + wrist_vec[0], shoulder[1] + wrist_vec[1])
        if spec["arms"] == "ground_touch" and side == "right":
            target = (shoulder[0] - 8, 650)
            elbow_hint = (-18, 65)
        return solve_bone(shoulder, target, (86, 82), elbow_hint)

    r_elbow, r_wrist = arm_points(shoulder_r, right_arm, "right")
    l_elbow, l_wrist = arm_points(shoulder_l, left_arm, "left")

    right_leg, left_leg = LEG[spec["legs"]]
    def leg_points(hip, control):
        knee_hint = (control[0], control[1])
        ankle = (hip[0] + control[2], hip[1] + control[3] - spec["pelvis"])
        return solve_bone(hip, ankle, (166, 166), knee_hint)
    r_knee, r_ankle = leg_points(hip_r, right_leg)
    l_knee, l_ankle = leg_points(hip_l, left_leg)

    # Helmet landmarks follow the rotated neck, preserving the same head-to-body ratio.
    yaw = spec["head"]
    def headpt(dx, dy):
        rx, ry = rotate(dx + yaw * 0.35, dy)
        return add((neck[0] + spec["lean"], neck[1]), (rx, ry))
    nose = headpt(16, -81)
    eye_r = headpt(10 + yaw*.1, -86)
    eye_l = headpt(26 + yaw*.08, -85)
    ear_r = headpt(-12, -80)
    ear_l = headpt(39, -79)
    return [nose, neck, shoulder_r, r_elbow, r_wrist, shoulder_l, l_elbow,
            l_wrist, hip_r, r_knee, r_ankle, hip_l, l_knee, l_ankle,
            eye_r, eye_l, ear_r, ear_l]


def render(points, target):
    image = Image.new("RGB", (W, H), (0, 0, 0))
    draw = ImageDraw.Draw(image)
    for i, (a, b) in enumerate(LIMBS):
        draw.line((points[a], points[b]), fill=COLORS[i], width=8)
    # Standard colored joint dots, with a restrained white center for crisp joints.
    for i, point in enumerate(points):
        c = COLORS[i % len(COLORS)]
        x, y = point
        draw.ellipse((x-7, y-7, x+7, y+7), fill=c)
    image.save(target)


def main():
    plan = json.loads(PLAN.read_text())
    expected = {a["clip"] for a in plan["actions"]}
    if expected != set(CLIPS):
        raise SystemExit(f"clip definitions mismatch: missing={expected-set(CLIPS)}, extra={set(CLIPS)-expected}")
    OUT.mkdir(parents=True, exist_ok=True)
    entries = []
    valid = 0
    for clip in (a["clip"] for a in plan["actions"]):
        if len(CLIPS[clip]) != 6:
            raise SystemExit(f"{clip} must have six phases")
        for index, spec in enumerate(CLIPS[clip]):
            joints = build_joints(spec)
            in_bounds = len(joints) == 18 and all(20 <= px < W-20 and 20 <= py < H-20 for px, py in joints)
            if not in_bounds:
                raise SystemExit(f"invalid geometry {clip}_{index:02d}: {joints}")
            valid += 1
            render(joints, OUT / f"{clip}_{index:02d}.png")
            entries.append({"clip": clip, "index": index, "joints": [list(p) for p in joints],
                            "prompt": spec["prompt"]})
    SPECS.write_text(json.dumps({"format": "OpenPose BODY_18", "canvas": [W, H],
                                 "joint_order": ["nose", "neck", "right_shoulder", "right_elbow", "right_wrist",
                                                 "left_shoulder", "left_elbow", "left_wrist", "right_hip", "right_knee",
                                                 "right_ankle", "left_hip", "left_knee", "left_ankle", "right_eye",
                                                 "left_eye", "right_ear", "left_ear"],
                                 "poses": entries}, indent=2) + "\n")
    print(f"Generated {valid} OpenPose18 maps; {valid} geometry-valid poses.")


if __name__ == "__main__":
    main()
