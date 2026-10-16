// Run against a debug HAP through HDC fport 18080->8080 and rport 19090->19090.
// The ignored config contains {base: capability-protected device base URL}.
import fs from 'node:fs';
import http from 'node:http';
import assert from 'node:assert/strict';
const config = JSON.parse(fs.readFileSync(process.argv[2]));
const base = new URL(config.base);
assert.equal(base.hostname, '127.0.0.1');
const fixture = fs.readFileSync(new URL('../app/rust/testdata/harmony/cenc.bin', import.meta.url));
const clear = fs.readFileSync(new URL('../app/rust/testdata/harmony/clear.bin', import.meta.url));
let requests = 0;
const server = http.createServer((req,res)=>{
  requests++;
  if (req.url==='/ignored') {res.writeHead(200, {'Content-Length':fixture.length});res.end(fixture);return;}
  const match=/^bytes=(\d+)-(\d+)$/.exec(req.headers.range??'');
  if (!match) {res.writeHead(400);res.end();return;}
  const start=Number(match[1]),end=Math.min(Number(match[2]),fixture.length-1);
  if(start>end) {res.writeHead(416);res.end();return;}
  res.writeHead(206,{'Content-Range':`bytes ${start}-${end}/${fixture.length}`,'Content-Length':end-start+1});res.end(fixture.subarray(start,end+1));
});
await new Promise(resolve=>server.listen(19090,'127.0.0.1',resolve));
function request(path,method='GET',body=null,headers={},prefix=base.pathname) {
  return new Promise((resolve,reject)=>{
    const bytes=body===null?null:Buffer.from(JSON.stringify(body));
    const req=http.request({hostname:'127.0.0.1',port:18080,path:prefix+path,method,headers:{Host:base.host,...(bytes?{'Content-Type':'application/json','Content-Length':bytes.length}:{}),...headers}},res=>{
      const chunks=[]; res.on('data',data=>chunks.push(data));res.on('end',()=>resolve({status:res.statusCode,headers:res.headers,body:Buffer.concat(chunks)}));
    });req.on('error',reject);req.setTimeout(30000,()=>req.destroy(new Error('Timeout'))); if(bytes)req.write(bytes);req.end();
  });
}
let id;
try {
  assert.notEqual((await request('/harmony-media/stats','GET',null,{},'')).status,200,'capability required');
  const opened=await request('/harmony-media/open','POST',{cdnUrl:'http://127.0.0.1:19090/fixture',keyHex:'00112233445566778899aabbccddeeff'});
  assert.equal(opened.status,200,'open source'); id=JSON.parse(opened.body).id;
  const all=await request('/harmony-media/'+id);assert.equal(all.status,200);assert.deepEqual(all.body,clear);
  const head=await request('/harmony-media/'+id,'HEAD');assert.equal(head.status,200);assert.equal(Number(head.headers['content-length']),clear.length);assert.equal(head.body.length,0);
  for(let i=0;i<600;i++){
    const start=(i*997+31)%clear.length,end=Math.min(clear.length-1,start+i*43%512);
    const got=await request('/harmony-media/'+id,'GET',null,{Range:`bytes=${start}-${end}`});
    assert.equal(got.status,206);assert.equal(got.headers['content-range'],`bytes ${start}-${end}/${clear.length}`);assert.deepEqual(got.body,clear.subarray(start,end+1));
  }
  assert.equal((await request('/harmony-media/'+id,'GET',null,{Range:`bytes=${clear.length}-`})).status,416);
  const stats=JSON.parse((await request('/harmony-media/stats')).body); assert(stats.maxCacheBytes<=262144);
  assert.equal((await request('/harmony-media/'+id,'DELETE')).status,204);
  assert.equal((await request('/harmony-media/'+id)).status,404); id=null;
  const rejected=await request('/harmony-media/open','POST',{cdnUrl:'http://127.0.0.1:19090/ignored',keyHex:'00112233445566778899aabbccddeeff'});assert.notEqual(rejected.status,200);
  console.log(JSON.stringify({result:'passed',randomRanges:600,upstreamRequests:requests,stats,capabilityRequired:true,head:true,unsatisfiable416:true,disposed404:true,ignoredRangeRejected:true}));
} finally { if(id)await request('/harmony-media/'+id,'DELETE');server.close(); }
