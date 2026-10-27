import Fastify from 'fastify';
import { Innertube, Platform, Log } from 'youtubei.js';
import vm from 'node:vm';
import {randomUUID} from 'node:crypto';
import {Readable} from 'node:stream';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import os from 'node:os';
const execute = promisify(execFile);
Log.setLevel(Log.Level.ERROR);
Platform.shim.eval = async data => vm.runInNewContext(`(function(){${data.output}})()`, {}, { timeout: 3000 });
const yt = await Innertube.create();
const app = Fastify({logger:false,bodyLimit:4096});
const cache = new Map();
const media = new Map();
function relay(url) {
 const u = new URL(url);
 if(u.protocol !== 'https:' || !u.hostname.endsWith('.googlevideo.com')) throw new Error('Unsupported stream host');
 if(media.size > 3000) { for(const [k,v] of media) if(v.until<Date.now()) media.delete(k); }
 if(media.size > 5000) throw new Error('Media session capacity exceeded');
 const token=randomUUID();media.set(token,{url:u.toString(),until:Date.now()+60*60*1000});
 return new URL(`http://127.0.0.1:${process.env.PORT||8787}/media/${token}`);
}
app.get('/media/:token',async(req,reply)=>{
 const m=media.get(req.params.token);if(!m||m.until<Date.now())return reply.code(410).send({error:'Nguồn đã hết hạn. Mở lại video để tải nguồn mới.'});
 const range=req.headers.range;if(range && !/^bytes=\d+-\d*$/.test(range))return reply.code(400).send();
 const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),30000);
 reply.raw.on('close',()=>{clearTimeout(timeout);if(!reply.raw.writableEnded)controller.abort();});
 try{
  let url=m.url,response;
  const total=Number(new URL(url).searchParams.get('clen'));
  let actualRange=range;
  if(actualRange && actualRange.endsWith('-') && total>0) actualRange += String(total-1);
  
  for(let i=0;i<4;i++){
   response=await fetch(url,{headers:actualRange?{Range:actualRange}:{},redirect:'manual',signal:controller.signal});
   if(response.status<300||response.status>=400)break;
   const next=new URL(response.headers.get('location'),url);await response.body?.cancel();
   if(next.protocol!=='https:'||!next.hostname.endsWith('.googlevideo.com'))throw new Error('Invalid stream redirect');url=next.toString();
  }
  if(![200,206].includes(response.status) || (actualRange && response.status!==206)){console.error('media status',response.status,'range',actualRange);await response.body?.cancel();clearTimeout(timeout);return reply.code(response.status===200?502:response.status).send();}
  for(const key of ['content-type','content-length','content-range','accept-ranges']){const v=response.headers.get(key);if(v)reply.header(key,v);}
  reply.header('cache-control','no-store');reply.code(response.status);return reply.send(Readable.fromWeb(response.body));
 }catch(e){clearTimeout(timeout);if(!reply.raw.destroyed)return reply.code(502).send();}
});
const text = x => x?.toString?.() ?? '';
function card(v){return {id:v.id,title:text(v.title),author:v.author?.name??'',thumbnail:v.thumbnails?.at(-1)?.url??'',duration:v.duration?.text??''};}
app.get('/health', async()=>({ok:true,version:'0.1.0',provider:'youtubei.js + yt-dlp',authConfigured:false}));
app.get('/search', async(req,reply)=>{
 const q=String(req.query.q??'').trim();if(!q||q.length>200)return reply.code(400).send({error:'Nhập từ khóa hoặc liên kết YouTube.'});
 const key='s:'+q;const old=cache.get(key);if(old&&old.until>Date.now())return old.data;
 const result=await yt.search(q,{type:'video'});const data={videos:result.videos.filter(v=>v.id).slice(0,24).map(card)};
 if(cache.size>100)cache.clear();cache.set(key,{until:Date.now()+60000,data});return data;
});
app.post('/resolve', async(req,reply)=>{
 const id=req.body?.id;if(typeof id!=='string'||!/^[-\w]{11}$/.test(id))return reply.code(400).send({error:'Video ID không hợp lệ.'});
 const old=cache.get(id);if(old&&old.until>Date.now())return old.data;
 const info=await yt.getBasicInfo(id,{client:'IOS'});
 if(info.playability_status?.status!=='OK')return reply.code(422).send({error:info.playability_status?.reason||'Nguồn video hiện không khả dụng.'});
 if(!info.streaming_data) return reply.code(422).send({error:'Không tìm thấy nguồn phát công khai.'});
 const {stdout} = await execute(process.env.YTB_DLP || `${os.homedir()}/.local/share/ytb-tools/yt-dlp`, ['--no-playlist','--skip-download','--dump-single-json','--js-runtimes',`node:${process.execPath}`,`https://www.youtube.com/watch?v=${id}`], {timeout:45000,maxBuffer:12*1024*1024});
 const extracted = JSON.parse(stdout);
 const usable = new Map(extracted.formats.filter(f=>f.url && !f.has_drm && f.protocol==='https').map(f=>[f.format_id,f]));
 info.streaming_data.adaptive_formats = info.streaming_data.adaptive_formats.filter(f=>{
  const match=usable.get(String(f.itag));
  if(!match || f.is_drc || (f.has_audio && f.itag!==140) || (match.filesize && Number(f.content_length)!==Number(match.filesize)))return false;
  f.url=match.url;f.signature_cipher=undefined;f.cipher=undefined;f.decipher=async()=>match.url;return true;
 });
 if(!info.streaming_data.adaptive_formats.some(f=>f.has_video)||!info.streaming_data.adaptive_formats.some(f=>f.has_audio))throw new Error('No compatible audio/video tracks');
 const checks = await Promise.all(info.streaming_data.adaptive_formats.map(async f=>{
  if(f.has_video && (f.height>2160 || f.mime_type.includes('av01'))) return false;
  const start=Math.max(0,Math.floor(Number(f.content_length||0)/2));
  const end=Math.min(start+65535,Number(f.content_length||65536)-1);
  try {const response=await fetch(f.url,{headers:{Range:`bytes=${start}-${end}`},signal:AbortSignal.timeout(8000)});
   if(response.status!==206){await response.body?.cancel();return false;}
   await response.arrayBuffer();return true;
  }catch{return false;}
 }));
 info.streaming_data.adaptive_formats=info.streaming_data.adaptive_formats.filter((_,index)=>checks[index]);
 if(!info.streaming_data.adaptive_formats.some(f=>f.has_video)||!info.streaming_data.adaptive_formats.some(f=>f.has_audio)) return reply.code(422).send({error:'YouTube đang từ chối nguồn phát của video này. Hãy chọn video khác hoặc thử lại sau.'});
 const mpd=await info.toDash({url_transformer:relay,format_filter:f=>!(f.url || f.signature_cipher) || f.has_text || (f.has_video ? f.height>2160 || f.mime_type.includes('av01') : !f.mime_type.includes('mp4a'))});
 const b=info.basic_info;const data={id,title:b.title,author:b.author,thumbnail:b.thumbnail?.at(-1)?.url??'',duration:b.duration,mpd};
 if(cache.size>100)cache.clear();cache.set(id,{until:Date.now()+5*60000,data});return data;
});
app.setErrorHandler((err,req,reply)=>{console.error(req.routeOptions.url,err.name);reply.code(502).send({error:'Nguồn YouTube tạm thời không đáp ứng. Vui lòng thử lại.'});});
await app.listen({port:Number(process.env.PORT||8787),host:'127.0.0.1'});
console.log('YTB source provider ready on 127.0.0.1:8787');
