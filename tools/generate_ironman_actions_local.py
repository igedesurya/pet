#!/usr/bin/env python3
"""Generate real key poses using the user's local ComfyUI, with resumable jobs.

Uses existing DreamShaper 8 and official OpenPose conditioning, not animation
warping. All prompts, seeds, workflow graphs, jobs and original outputs persist.
"""
import argparse
import hashlib
import json
import shutil
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'artwork/iron-man-action'
URL = 'http://127.0.0.1:8188'
CHECKPOINT = 'DreamShaper_8_pruned.safetensors'
CONTROLNET = 'control_v11p_sd15_openpose_fp16.safetensors'
POSITIVE = ('Iron Man Mark III, one adult male armored superhero, full body, solo, '
            '(fully closed gold helmet faceplate:1.6), '
            'red and gold mechanical armor, red leg armor and red boots, blue glowing eyes, '
            'circular blue arc reactor on chest, heroic adult proportions, '
            'complete boots visible, clean polished comic book character illustration, '
            'dimensional cel shading, crisp edges, plain white studio background, '
            'centered character, generous margins, ')
NEGATIVE = ('(unmasked:1.5), (human face:1.5), hair, skin, woman, female, exposed head, '
            'cropped, closeup, extra arms, extra legs, extra fingers, malformed hands, '
            'multiple people, text, watermark, blurry, low quality, exposed face, '
            'red faceplate, triangle chest reactor, white armor, blue armor, '
            'weapon, sword, gun')


def request(path, body=None):
    req = urllib.request.Request(URL + path, data=None if body is None else json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def workflow(spec, steps):
    name = f"{spec['clip']}_{spec['index']:02d}"
    pose_prompt = spec.get('prompt', spec.get('pose_prompt', spec.get('description', '')))
    if spec['clip'] == 'action_repulsor_shoot' and spec['index'] == 3:
        pose_prompt += ' A compact bright cyan repulsor light flash projects from the extended open palm.'
    elif spec['clip'] == 'action_chest_blast' and spec['index'] == 3:
        pose_prompt += ' A compact bright cyan light beam projects from the round chest reactor.'
    elif spec['clip'] == 'action_flight' or (spec['clip'] == 'action_dash' and spec['index'] in (2, 3)):
        pose_prompt += ' Short vivid cyan jet flames emerge directly under both armored boots.'
    elif spec['clip'] == 'action_scan' and spec['index'] in (2, 3):
        pose_prompt += ' A small cyan holographic disc glows directly over the raised palm.'
    elif spec['clip'] == 'action_energy_charge' and spec['index'] in (2, 3):
        pose_prompt += ' Both open armored palms glow with vivid cyan energy.'
    return {
        '1': {'class_type': 'CheckpointLoaderSimple', 'inputs': {'ckpt_name': CHECKPOINT}},
        '2': {'class_type': 'ControlNetLoader', 'inputs': {'control_net_name': CONTROLNET}},
        '3': {'class_type': 'CLIPTextEncode', 'inputs': {'text': POSITIVE + pose_prompt, 'clip': ['1', 1]}},
        '4': {'class_type': 'CLIPTextEncode', 'inputs': {'text': NEGATIVE, 'clip': ['1', 1]}},
        '5': {'class_type': 'LoadImage', 'inputs': {'image': 'ironman-poses/' + name + '.png'}},
        '6': {'class_type': 'ControlNetApplyAdvanced', 'inputs': {
            'positive': ['3', 0], 'negative': ['4', 0], 'control_net': ['2', 0],
            'image': ['5', 0], 'strength': 0.90, 'start_percent': 0.0, 'end_percent': 0.85}},
        '7': {'class_type': 'EmptyLatentImage', 'inputs': {'width': 512, 'height': 768, 'batch_size': 1}},
        '8': {'class_type': 'KSampler', 'inputs': {'model': ['1', 0], 'positive': ['6', 0],
            'negative': ['6', 1], 'latent_image': ['7', 0], 'seed': 3072026,
            'steps': steps, 'cfg': 7.0, 'sampler_name': 'euler', 'scheduler': 'normal', 'denoise': 1.0}},
        '9': {'class_type': 'VAEDecode', 'inputs': {'samples': ['8', 0], 'vae': ['1', 2]}},
        '10': {'class_type': 'SaveImage', 'inputs': {'images': ['9', 0], 'filename_prefix': 'ironman-actions/' + name}}
    }


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clips', nargs='+')
    parser.add_argument('--limit', type=int)
    parser.add_argument('--steps', type=int, default=20)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    data = json.loads((ART / 'pose-specs.json').read_text())
    specs = data if isinstance(data, list) else data.get('poses', data.get('frames', []))
    if args.clips:
        specs = [item for item in specs if item['clip'] in args.clips]
    if args.limit is not None:
        specs = specs[:args.limit]
    if not specs:
        raise ValueError('No matching pose specifications')
    source_dir = ART / 'local-frames'
    source_dir.mkdir(parents=True, exist_ok=True)
    input_dir = Path('/Users/surya/.local/share/comfyui/input/ironman-poses')
    input_dir.mkdir(parents=True, exist_ok=True)
    for index, spec in enumerate(specs):
        name = f"{spec['clip']}_{spec['index']:02d}"
        shutil.copy2(ART / 'pose-maps' / (name + '.png'), input_dir / (name + '.png'))
        graph = workflow(spec, args.steps)
        workflow_path = ART / 'workflows' / (name + '.json')
        save(workflow_path, graph)
        if args.prepare_only:
            print('Prepared: ' + str(workflow_path), flush=True)
            continue
        destination = source_dir / (name + '.png')
        if destination.exists():
            print(f'{index+1}/{len(specs)} already generated: {name}', flush=True)
            continue
        job_path = ART / 'jobs' / (name + '.json')
        if job_path.exists():
            identifier = json.loads(job_path.read_text())['prompt_id']
            history = request('/history/' + identifier).get(identifier)
            queue = request('/queue')
            active_ids = {str(item[1]) for key in ('queue_running', 'queue_pending') for item in queue.get(key, [])}
            if not history and identifier not in active_ids:
                raise RuntimeError(f'Job {identifier} no longer exists: inspect before resubmitting {name}')
        else:
            result = request('/prompt', {'prompt': graph})
            if result.get('node_errors'):
                raise RuntimeError(result['node_errors'])
            save(job_path, result)
            identifier = result['prompt_id']
        print(f'{index+1}/{len(specs)} generating {name} job={identifier}', flush=True)
        started = time.monotonic()
        next_progress = started + 30
        while time.monotonic() - started < 1200:
            history = request('/history/' + identifier).get(identifier)
            if history:
                save(ART / 'history' / (name + '.json'), history)
                if history.get('status', {}).get('status_str') == 'error':
                    raise RuntimeError(history['status'])
                images = history.get('outputs', {}).get('10', {}).get('images', [])
                if images:
                    with urllib.request.urlopen(URL + '/view?' + urllib.parse.urlencode(images[0]), timeout=30) as response:
                        destination.write_bytes(response.read())
                    print(f'Saved {destination} in {time.monotonic()-started:.1f}s sha256={hashlib.sha256(destination.read_bytes()).hexdigest()}', flush=True)
                    break
            if time.monotonic() >= next_progress:
                print(f'Pending {name}: {time.monotonic()-started:.0f}s', flush=True)
                next_progress = time.monotonic() + 30
            time.sleep(2)
        else:
            raise TimeoutError(f'Job {identifier} still pending; resume safely without submitting duplicate')


if __name__ == '__main__':
    main()
