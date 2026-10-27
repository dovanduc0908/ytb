#!/usr/bin/env python3
"""Inspect/tap Android UI using accessibility bounds, never screenshot coordinates."""
import subprocess,sys,re,xml.etree.ElementTree as ET,json
from pathlib import Path
adb=str(Path.home()/'Library/Android/sdk/platform-tools/adb')
serial=sys.argv[1];action=sys.argv[2];label=sys.argv[3] if len(sys.argv)>3 else ''
def run(*args):return subprocess.check_output([adb,'-s',serial,*args],timeout=20)
raw=run('exec-out','uiautomator','dump','/dev/tty').decode(errors='replace')
start=raw.find('<?xml'); end=raw.rfind('</hierarchy>')+len('</hierarchy>')
if start<0:raise SystemExit(raw)
root=ET.fromstring(raw[start:end])
if not any(n.attrib.get('package')=='com.duchaik.ytb' for n in root.iter('node')): raise SystemExit('YTB is not foreground; no UI action performed')
Path('artifacts/qa/latest-ui.xml').write_text(raw[start:end])
nodes=[n for n in root.iter('node')]
if action=='dump':
 for n in nodes:
  t=n.attrib.get('text') or n.attrib.get('content-desc')
  if t:print(json.dumps({k:n.attrib.get(k) for k in ['text','content-desc','class','clickable','bounds']},ensure_ascii=False))
elif action=='tap':
 matches=[n for n in nodes if label in (n.attrib.get('text',''),n.attrib.get('content-desc',''))]
 if not matches:raise SystemExit('UI label not found: '+label)
 n=next((n for n in matches if n.attrib.get('clickable')=='true'),matches[0]);a=list(map(int,re.findall(r'\d+',n.attrib['bounds'])));
 if a[2]<=a[0] or a[3]<=a[1]:raise SystemExit('UI element has no visible bounds')
 print('tap',label,n.attrib['bounds']);run('shell','input','tap',str((a[0]+a[2])//2),str((a[1]+a[3])//2))
elif action in ('input','type'):
 nodes=[n for n in nodes if n.attrib.get('class')=='android.widget.EditText'];
 if not nodes:raise SystemExit('No text input')
 n=nodes[0];a=list(map(int,re.findall(r'\d+',n.attrib['bounds'])));run('shell','input','tap',str((a[0]+a[2])//2),str((a[1]+a[3])//2));run('shell','input','text',label)
 if action=='input':run('shell','input','keyevent','66')
