import { Innertube, Platform } from 'youtubei.js';
import vm from 'node:vm';
Platform.shim.eval = async data => vm.runInNewContext(`(function(){${data.output}})()`, {}, {timeout:3000});
const yt = await Innertube.create();
for(const client of ['ANDROID','IOS','WEB']) {
 try { const info = await yt.getBasicInfo('aqz-KE-bpKQ',{client});
 const s=info.streaming_data;
 console.log(JSON.stringify({client,title:info.basic_info.title,status:info.playability_status,formats:s?.formats?.map(f=>({itag:f.itag,q:f.quality_label})),adaptive:s?.adaptive_formats?.length,hls:!!s?.hls_manifest_url}));
 if(s?.formats?.length){const url=await s.formats[0].decipher(yt.session.player);const r=await fetch(url,{headers:{Range:'bytes=0-1023'},signal:AbortSignal.timeout(15000)});console.log('stream',r.status,r.headers.get('content-type'));await r.body?.cancel();}
 }catch(e){console.log(client,e.message)}
}
