// Test-only independent HTTP/HTTPS stylesheet peers. All listeners are loopback and owned.
'use strict';
const fs=require('fs'),path=require('path'),http=require('http'),https=require('https'),zlib=require('zlib'),child=require('child_process');
const executable=path.resolve(process.argv[2]),directory=path.resolve(process.argv[3]),root=path.resolve(__dirname,'..');
fs.mkdirSync(directory,{recursive:true});
const trust=path.join(root,'tests/x509/root.pem'),servers=[],sockets=new Set(),requests=[];
let plainPort=0,securePort=0,count=0;
const privateFile=path.join(directory,'private.css');fs.writeFileSync(privateFile,'.private { color:#ff0000; }');
function send(response,body,headers={}){
 response.writeHead(200,{'Content-Type':'text/css',...headers});response.end(body);
}
function serve(request,response){
 requests.push(request.url);
 const sheets={
 '/a.css':'/* source */ @import url("nested/b.css"); .outer {color:#333333}',
 '/nested/b.css':'@import "../cycle.css"; .inner {color:#222222}',
 '/cycle.css':'@import "a.css"; .cycle {color:#111111}',
 '/simple.css':'.simple {color:#111111}',
 '/screen.css':'.screen {color:#222222}',
 '/print.css':'.print {color:#333333}',
 '/late.css':'.late {color:#444444}',
 '/c.css':'.cap_c {color:#333333}',
 '/d.css':'.cap_d {color:#444444}',
 '/e.css':'.cap_e {color:#555555}',
 '/cap.css':'@import "simple.css"; .cap {color:#222222}',
 '/assets/theme.css':'@import "base.css"; .redirected {color:#121212}',
 '/assets/base.css':'.redirect_base {color:#343434}',
 '/remote.css':'@import "file://'+privateFile+'"; .remote {color:#333333}',
 '/secure.css':'@import "http://127.0.0.1:'+plainPort+'/mixed.css"; .secure {color:#444444}',
 '/mixed.css':'.insecure {color:#ff0000}',
 };
 if(request.url==='/jump.css'){response.writeHead(302,{Location:'/assets/theme.css'});response.end();return;}
 if(request.url==='/compressed.css'){send(response,zlib.gzipSync(Buffer.from('@import "simple.css"; .compressed {color:#222222}')),{'Content-Encoding':'gzip'});return;}
 if(request.url==='/legacy.css'){send(response,Buffer.from('.caf\xe9 {color:#123456}','latin1'),{'Content-Type':'text/css; charset=iso-8859-1'});return;}
 if(request.url==='/too-large.css'){send(response,zlib.gzipSync(Buffer.alloc(1048577,97)),{'Content-Encoding':'gzip'});return;}
 if(request.url==='/slow.css'||request.url==='/slow2.css'||request.url==='/slow3.css'){
  const timer=setTimeout(()=>{if(!response.destroyed)send(response,request.url==='/slow.css'?'@import "slow2.css"; .slow_outer {color:#123456}':'.too_slow {color:#ff0000}');},2000);
  response.once('close',()=>clearTimeout(timer));return;
 }
 if(Object.hasOwn(sheets,request.url)){send(response,sheets[request.url]);return;}
 response.writeHead(404);response.end();
}
function listen(server){
 servers.push(server);server.on('connection',socket=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket));socket.on('error',()=>{});});
 return new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',()=>resolve(server.address().port));});
}
function execute(args){
 return new Promise(resolve=>child.execFile(executable,args,{timeout:10000,maxBuffer:1024*1024},(error,stdout,stderr)=>resolve({code:error?error.code:0,signal:error?error.signal:null,stdout,stderr})));
}
function occurrences(text,needle){return text.split(needle).length-1;}
async function run(name,source,base,check){
 requests.length=0;const input=path.join(directory,name+'.html'),output=path.join(directory,name+'.css');
 fs.writeFileSync(input,source);fs.rmSync(output,{force:true});
 const result=await execute([input,base,output,trust,'1000']);
 fs.writeFileSync(path.join(directory,name+'.log'),result.stdout+result.stderr);
 if(result.code!==0||result.signal||!fs.existsSync(output))throw Error(name+' did not complete: '+JSON.stringify(result));
 const text=fs.readFileSync(output,'utf8');check(text,[...requests],result.stdout);
 count++;console.log('PASS '+name);
}
function assert(value,message){if(!value)throw Error(message);}
(async()=>{
 plainPort=await listen(http.createServer(serve));
 const secure=https.createServer({
  cert:fs.readFileSync(path.join(root,'tests/x509/localhost.pem')),key:fs.readFileSync(path.join(root,'tests/x509/localhost.key')),
  minVersion:'TLSv1.3',maxVersion:'TLSv1.3',ciphers:'TLS_AES_128_GCM_SHA256',ecdhCurve:'X25519'
 },serve);secure.on('tlsClientError',()=>{});
 securePort=await listen(secure);
 try{
  const base='http://127.0.0.1:'+plainPort+'/page.html',secureBase='https://localhost:'+securePort+'/page.html';
  await run('import-cycle-order','<link rel="stylesheet" href="a.css"><style>.inline {color:#ff0000}</style><link rel="stylesheet" href="a.css">',base,(text,seen)=>{
   assert(JSON.stringify(seen)===JSON.stringify(['/a.css','/nested/b.css','/cycle.css']),'cycle/repeat performed extra requests');
   const positions=['.cycle','.inner','.outer','.inline'].map(x=>text.indexOf(x));
   assert(positions.every((p,i)=>p>=0&&(i===0||p>positions[i-1])),'import/source order wrong');
   for(const name of ['.cycle','.inner','.outer'])assert(occurrences(text,name)===2,'cached sheet was not replayed at the second occurrence: '+name);
  });
  await run('four-total-urls','<link rel="stylesheet" href="cap.css"><link rel="stylesheet" href="c.css"><link rel="stylesheet" href="d.css"><link rel="stylesheet" href="e.css">',base,(text,seen)=>{
   assert(JSON.stringify(seen)===JSON.stringify(['/cap.css','/simple.css','/c.css','/d.css']),'imports escaped four-URL budget');
   assert(!text.includes('.cap_e')&&text.includes('.cap_d'),'four-URL fallback wrong');
  });
  await run('import-media-and-placement','<style>@import "print.css" print; @import url("screen.css") screen and (min-width:1000px) and (max-width:1000px); .local {color:#555555} @import "late.css";</style><style media="print">@import "print.css";</style>',base,(text,seen)=>{
   assert(JSON.stringify(seen)===JSON.stringify(['/screen.css']),'nonmatching or late import was fetched');
   assert(text.indexOf('.screen')<text.indexOf('.local'),'matching import order wrong');
  });
  await run('redirect-relative-import','<link rel="stylesheet" href="jump.css">',base,(text,seen)=>{
   assert(JSON.stringify(seen)===JSON.stringify(['/jump.css','/assets/theme.css','/assets/base.css']),'relative import did not use final redirected URL');
   assert(text.indexOf('.redirect_base')<text.indexOf('.redirected'),'redirect import order wrong');
  });
  await run('compressed-import','<link rel="stylesheet" href="compressed.css">',base,(text,seen)=>{
   assert(seen.includes('/simple.css')&&text.indexOf('.simple')<text.indexOf('.compressed'),'compressed CSS import failed');
  });
  await run('legacy-css-header','<link rel="stylesheet" href="legacy.css">',base,text=>assert(text.includes('.café'),'CSS HTTP charset ignored'));
  await run('remote-cannot-import-local','<style>@import "http://127.0.0.1:'+plainPort+'/remote.css";</style>','file://'+path.join(directory,'local.html'),text=>{
   assert(text.includes('.remote')&&!text.includes('.private'),'remote stylesheet inherited local-file authority');
  });
  await run('secure-page-mixed-import','<link rel="stylesheet" href="secure.css">',secureBase,(text,seen)=>{
   assert(text.includes('.secure')&&!text.includes('.insecure')&&!seen.includes('/mixed.css'),'HTTPS page imported HTTP CSS');
  });
  await run('secure-sheet-mixed-import','<link rel="stylesheet" href="https://localhost:'+securePort+'/secure.css">',base,(text,seen)=>{
   assert(text.includes('.secure')&&!text.includes('.insecure')&&!seen.includes('/mixed.css'),'HTTPS sheet imported HTTP CSS on an HTTP page');
  });
  await run('expanded-sheet-limit','<link rel="stylesheet" href="too-large.css"><style>.readable {color:#111111}</style>',base,(text,seen,log)=>{
   assert(text.includes('.readable')&&text.length<1000&&log.includes('STYLES unavailable'),'expanded stylesheet byte limit not enforced');
  });
  await run('one-batch-deadline','<link rel="stylesheet" href="slow.css"><link rel="stylesheet" href="slow3.css"><style>.after_timeout {color:#123456}</style>',base,(text,seen,log)=>{
   const time=Number(/elapsed_us=(\d+)/.exec(log)?.[1]);
   assert(time>=2800000&&time<4000000,'batch deadline was reset per imported sheet: '+time);
   assert(JSON.stringify(seen)===JSON.stringify(['/slow.css','/slow2.css']),'request began after the one deadline');
   assert(text.includes('.slow_outer')&&text.includes('.after_timeout')&&!text.includes('.too_slow'),'deadline fallback lost readable local styles');
   assert(log.includes('STYLES timeout'),'missing timeout evidence');
  });
  console.log('PASS '+count+' native stylesheet scenarios; all peers stopped');
 }finally{
  for(const socket of sockets)socket.destroy();
  await Promise.all(servers.map(server=>new Promise(resolve=>server.close(resolve))));
 }
})().catch(error=>{console.error(error.stack);for(const socket of sockets)socket.destroy();for(const server of servers)server.close();process.exitCode=1;});
