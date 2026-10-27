#!/usr/bin/env python3
"""Exercise the actual native receiver over LAN. Reads pairing data from fresh adb UI XML.
No PIN, pairing token, signed stream URL or raw source response is written to artifacts.
"""
import json,socket,subprocess,re,time,xml.etree.ElementTree as ET,sys
from pathlib import Path
adb=str(Path.home()/'Library/Android/sdk/platform-tools/adb');serial=sys.argv[1]
def run(*args):return subprocess.check_output([adb,'-s',serial,*args],timeout=20)
raw=run('exec-out','uiautomator','dump','--compressed','/dev/tty').decode(errors='replace')
start=raw.find('<?xml');end=raw.rfind('</hierarchy>')+len('</hierarchy>')
root=ET.fromstring(raw[start:end]);labels=[n.attrib.get('text','') for n in root.iter('node') if n.attrib.get('package')=='com.duchaik.ytb'];text=' '.join(labels)
pin=re.search(r'Mã(?: ghép)?:\s*(\d{6})',text);address=re.search(r'(\d+\.\d+\.\d+\.\d+):(\d+)',text)
if not pin or not address:raise SystemExit('Receiver pairing UI is not visible')
host,port=address.group(1),int(address.group(2));token=None
report={'transport':'device-local TCP via adb netcat; direct Mac-to-Samsung LAN failed with No route to host','device':'Samsung SM-G975U1 acting as native TV receiver','physicalTV':False}
def call(method,args=None,**extra):
 data={'method':method,**extra}
 if token:data['token']=token
 if args is not None:data['args']=args
 data_bytes=(json.dumps(data)+'\n').encode()
 if '--device-client' in sys.argv:
  response=subprocess.run([adb,'-s',serial,'shell','toybox','nc','-w','5','-W','25',host,str(port)],input=data_bytes,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30,check=True)
  value=json.loads(response.stdout)
 else:
  with socket.create_connection((host,port),timeout=5) as client:
   client.settimeout(25);client.sendall(data_bytes);chunks=b''
   while b'\n' not in chunks:
    chunk=client.recv(65536)
    if not chunk:break
    chunks+=chunk
   value=json.loads(chunks)
 return value
assert 'error' in call('state');report['rejectsUnauthenticated']=True
assert 'error' in call('pair',pin='bad');report['rejectsWrongPin']=True
token=call('pair',pin=pin.group(1))['token']
original_queue=call('queue')['result']
def state():
 value=call('state');assert 'error' not in value,value;return value['result']
def until(done,seconds=40):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  s=state();assert s.get('error') is None,s.get('error')
  if done(s):return s
  time.sleep(.05)
 raise AssertionError('Receiver state timeout')
loadtimes=[];frames=[]
for i in range(52):
 vid=['aqz-KE-bpKQ','WhWc3b3KhnY'][i%2]
 start=time.monotonic();assert 'error' not in call('load',{'id':vid,'title':'Public Blender test video','position':0})
 s=until(lambda s:s['id']==vid and s['playing'] and s['ready'] and s['firstFrameMs']>=0)
 loadtimes.append(round((time.monotonic()-start)*1000));frames.append(s['firstFrameMs'])
print('Receiver playback samples:',len(loadtimes),flush=True)
report['warm50NativeFirstFrameP50Ms']=sorted(frames[2:])[24]
report['warm50NativeFirstFrameP95Ms']=sorted(frames[2:])[47]
report['startupMsIncludingAdbDriver']=loadtimes;report['firstFrameMs']=frames
Path('artifacts/duchaik-0.6/tv-receiver-release.json').write_text(json.dumps(report,indent=2))
call('pause');assert state()['playing']==False
call('seek',{'position':10000});until(lambda s:abs(s['position']-10000)<1000)
call('speed',{'value':1.5});assert state()['speed']==1.5
call('play');until(lambda s:s['playing'])
call('timer',{'milliseconds':500});until(lambda s:s['timerExpired']);assert state()['playing']==False
report.update(pausePlaySeekSpeed=True,sleepTimer=True)
# Exercise queue editing with 30 distinct, syntactically valid public YouTube IDs.
ids=json.loads((Path(__file__).resolve().parents[1]/'apps/native/test/fixtures/public_queue_ids.json').read_text());assert len(ids)>=30
queue=[{'id':vid,'title':f'Queue QA {i+1}'} for i,vid in enumerate(ids[:30])]
current=call('queue',{'items':queue,'repeat':0})['result'];assert len(current['items'])==30
reordered=call('queue',{'items':list(reversed(queue)),'repeat':0,'revision':current['revision']})['result'];assert reordered['items'][0]['id']==queue[-1]['id']
assert 'error' in call('queue',{'items':queue,'repeat':0,'revision':current['revision']})
report['queue30AndRevision']=True

call('timer',{'milliseconds':0});call('speed',{'value':1.0});call('queue',{'items':original_queue['items'],'repeat':original_queue['repeat']});call('pause')
Path('artifacts/duchaik-0.6/tv-receiver-release.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report),flush=True)
