// Nonvisual debug acceptance commands. Never use with a public/untrusted VM service.
import fs from 'node:fs';
const config=JSON.parse(fs.readFileSync(process.argv[2]));
const params=JSON.parse(process.argv[3]??'{"action":"status"}');
const ws=new WebSocket(config.vm);
await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
let serial=0;const pending=new Map();
ws.onmessage=({data})=>{const m=JSON.parse(data);const p=pending.get(m.id);if(p){pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result);}};
function rpc(method,params={}) {return new Promise((resolve,reject)=>{const id=String(++serial);pending.set(id,{resolve,reject});ws.send(JSON.stringify({jsonrpc:'2.0',id,method,params}));});}
try {
  const vm=await rpc('getVM');const isolate=vm.isolates.find(i=>i.name==='main')??vm.isolates[0];
  for (const command of Array.isArray(params)?params:[params]) {
    if(command.waitMs) {await new Promise(resolve=>setTimeout(resolve,Math.min(Number(command.waitMs),15000)));continue;}
    const result=await rpc('ext.fqapp.acceptance',{isolateId:isolate.id,...command});
    console.log(JSON.stringify({action:command.action,...result}));
  }
} finally {ws.close();}
