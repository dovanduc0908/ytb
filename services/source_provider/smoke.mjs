import fs from 'node:fs/promises';
const base='http://127.0.0.1:8787';
const results=[];
const searchResponse=await fetch(`${base}/search?q=Blender%20open%20movie`);
const search=await searchResponse.json();
if(searchResponse.status!==200 || !search.videos?.length)throw new Error('Search failed');
const ids=[...new Set(['aqz-KE-bpKQ','WhWc3b3KhnY',...search.videos.slice(0,4).map(v=>v.id)])];
for(const id of ids){
 const started=Date.now();
 const response=await fetch(`${base}/resolve`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id}),signal:AbortSignal.timeout(65000)});
 const d=await response.json();const record={id,status:response.status,ms:Date.now()-started};
 if(d.mpd){
  record.heights=[...new Set([...d.mpd.matchAll(/height="(\d+)"/g)].map(x=>Number(x[1])))].sort((a,b)=>a-b);
  const urls=[...d.mpd.matchAll(/<BaseURL>(.*?)<\/BaseURL>/gs)].map(m=>m[1].replaceAll('&amp;','&'));
  record.rangeStatus=[];
  for(const url of [urls[0],urls.at(-1)]){
   const r=await fetch(url,{headers:{Range:'bytes=0-1023'},signal:AbortSignal.timeout(15000)});
   record.rangeStatus.push(r.status);await r.body?.cancel();
  }
  record.playable=record.rangeStatus.every(s=>s===206);
 }else {record.error=d.error;record.playable=false;}
 results.push(record);console.log(record);
}
const invalid=await fetch(`${base}/resolve`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:'https://localhost/'})});
results.push({invalidIdStatus:invalid.status});
await fs.writeFile('../../artifacts/provider-smoke.json',JSON.stringify(results,null,2));
// A declared 422 is an honest blocked source; a successful manifest with broken streams is a regression.
if(results.some(x=>(x.status && ![200,422].includes(x.status)) || (x.status===200&&!x.playable)) || !results.some(x=>x.playable) || invalid.status!==400)process.exitCode=1;
