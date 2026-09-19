"""Bounded release-contract tests; legacy full suite is a separate diagnostic."""
import argparse, subprocess, pathlib, json, re, sys
p=argparse.ArgumentParser();p.add_argument('--godot',required=True);args=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];out=root/'.verification/release';out.mkdir(parents=True,exist_ok=True)
results=[]
for name in ['test_release_controls','test_release_edges','test_release_defense','test_return_to_sender','test_return_to_sender_defenses','test_release_story_run']:
 log=out/(name+'.log')
 with log.open('w',encoding='utf-8') as f:
  try: code=subprocess.run([args.godot,'--headless','--path',str(root),'--script','res://tests/'+name+'.gd'],stdout=f,stderr=subprocess.STDOUT,timeout=180).returncode
  except subprocess.TimeoutExpired: code=124
 text=log.read_text(encoding='utf-8',errors='replace');markers=[l for l in text.splitlines() if '_COMPLETE' in l]
 ok=code==0 and len(markers)==1 and not re.search(r'SCRIPT ERROR:|ERROR:|FAIL[: ]',text)
 results.append({'test':name,'exit':code,'passed':ok,'markers':markers});print(results[-1],flush=True)
code=subprocess.run([sys.executable,str(root/'tests/test_release_help.py')]).returncode
results.append({'test':'test_release_help','passed':code==0,'exit':code})
(out/'results.json').write_text(json.dumps(results,indent=2))
sys.exit(0 if all(r['passed'] for r in results) else 1)
