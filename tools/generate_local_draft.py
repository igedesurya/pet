#!/usr/bin/env python3
"""Generate the Iron Man concept through an already running local ComfyUI."""
import json
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artwork/iron-man-draft'
URL = 'http://127.0.0.1:8188'
PROMPT = ('Iron Man, full body, solo, closed gold helmet, red and gold mechanical armor, '
          'blue glowing eyes, circular blue arc reactor on chest, heroic adult proportions, '
          'relaxed neutral standing pose, arms at sides, complete boots visible, '
          'clean polished comic book character illustration, dimensional cel shading, '
          'crisp edges, plain white studio background, centered character, generous margins')
NEGATIVE = ('cropped, out of frame, closeup, multiple characters, extra arms, extra legs, '
            'extra fingers, malformed hands, text, watermark, logo, blurry, low quality')
WORKFLOW = {
 '1': {'class_type': 'CheckpointLoaderSimple', 'inputs': {'ckpt_name': 'DreamShaper_8_pruned.safetensors'}},
 '2': {'class_type': 'CLIPTextEncode', 'inputs': {'text': PROMPT, 'clip': ['1',1]}},
 '3': {'class_type': 'CLIPTextEncode', 'inputs': {'text': NEGATIVE, 'clip': ['1',1]}},
 '4': {'class_type': 'EmptyLatentImage', 'inputs': {'width': 512, 'height': 768, 'batch_size': 1}},
 '5': {'class_type': 'KSampler', 'inputs': {'model': ['1',0], 'positive': ['2',0], 'negative': ['3',0],
       'latent_image': ['4',0], 'seed': 3072026, 'steps': 24, 'cfg': 7.0, 'sampler_name': 'euler',
       'scheduler': 'normal', 'denoise': 1.0}},
 '6': {'class_type': 'VAEDecode', 'inputs': {'samples': ['5',0], 'vae': ['1',2]}},
 '7': {'class_type': 'SaveImage', 'inputs': {'images': ['6',0], 'filename_prefix': 'iron-man-draft-v1'}}
}

def request(path, body=None):
    req=urllib.request.Request(URL+path, data=None if body is None else json.dumps(body).encode(),
                               headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'workflow-api.json').write_text(json.dumps(WORKFLOW,indent=2))
    result=request('/prompt',{'prompt':WORKFLOW})
    identifier=result['prompt_id']
    print('Job:',identifier,flush=True)
    (OUT/'job.json').write_text(json.dumps(result,indent=2))
    deadline=time.monotonic()+600
    while time.monotonic()<deadline:
        history=request('/history/'+identifier).get(identifier)
        if history:
            (OUT/'history.json').write_text(json.dumps(history,indent=2))
            if history.get('status',{}).get('status_str')=='error':
                raise RuntimeError(history['status'])
            images=history.get('outputs',{}).get('7',{}).get('images',[])
            if images:
                image=images[0]
                from urllib.parse import urlencode
                with urllib.request.urlopen(URL+'/view?'+urlencode(image),timeout=30) as response:
                    destination=OUT/'iron-man-draft-v1.png'
                    destination.write_bytes(response.read())
                print('Saved:',destination,flush=True)
                return
        time.sleep(2)
    raise TimeoutError('Job still running; check job.json and ComfyUI history before resubmitting.')

if __name__=='__main__': main()
