#!/usr/bin/env node
// Attack only the fresh loopback bridge allocated by an isolated proof launch.
// No legitimate credential is accepted by this tool or inherited from its caller.
const net=require('net');
const port=Number(process.argv[2]);
if(!Number.isInteger(port)||port<1||port>65535)throw Error('Expected private bridge port');
async function rejected(name,payload,end){
 return new Promise((resolve,reject)=>{
  const start=performance.now(),socket=net.createConnection({host:'127.0.0.1',port});
  let connected=false,settled=false;
  const timer=setTimeout(()=>finish(Error(name+': candidate was not rejected within 1500 ms')),1500);
  function finish(error){if(settled)return;settled=true;clearTimeout(timer);socket.destroy();if(error)reject(error);else resolve();}
  socket.on('connect',()=>{connected=true;if(payload)socket.write(payload);if(end)socket.end();});
  socket.on('data',()=>finish(Error(name+': unauthenticated client received transport bytes')));
  socket.on('error',error=>{if(error.code!=='ECONNRESET')finish(error);});
  socket.on('close',()=>{if(!connected)return finish(Error(name+': listener did not accept candidate'));
   const elapsed=Math.round(performance.now()-start);
   if(name==='stalled'&&elapsed<180)return finish(Error('Stalled candidate closed before expected authentication deadline'));
   console.log('PASS rejected '+name+' candidate; elapsed_ms='+elapsed);finish();
  });
 });
}
(async()=>{
 await rejected('wrong32',Buffer.alloc(32),false);
 await rejected('short',Buffer.from('short'),true);
 await rejected('stalled',null,false);
 console.log('PASS same bridge listener survived all unauthenticated candidates; legitimate launch follows');
})().catch(error=>{console.error(error.message);process.exitCode=1;});
