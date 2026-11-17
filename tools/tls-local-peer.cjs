// Independent local TLS test peer. Node/OpenSSL is used only by the offline tests,
// never by the lkjscript browser. Keys below are synthetic committed test fixtures.
'use strict';
const fs=require('fs'),path=require('path'),https=require('https'),http=require('http'),net=require('net');
const root=path.resolve(__dirname,'..'),output=process.argv[2];
if(!output)throw new Error('port manifest path required');
const servers=[],sockets=new Set(),ports={};
function track(server){servers.push(server);server.on('connection',s=>{sockets.add(s);s.on('close',()=>sockets.delete(s));s.on('error',()=>{});});}
function listen(server,name){track(server);return new Promise((resolve,reject)=>{
 server.once('error',reject);server.listen(0,'127.0.0.1',()=>{ports[name]=server.address().port;resolve();});
});}
function content(req,res){
 const url=new URL(req.url,'https://localhost');
 // These routes exercise browser stylesheet integration, not Node rendering.
 const sheets={
  '/repeat.css':'#repeat-target {color:#112233}',
  '/cap-a.css':'.unused-a {color:#213141}',
  '/cap-b.css':'.unused-b {color:#314151}',
  '/cap-c.css':'.unused-c {color:#415161}',
  '/cap-denied.css':'#repeat-target {color:#ff0000} #cap-marker {display:none}',
  '/print.css':'#link-print {display:none}',
  '/width-exact.css':'#link-exact {display:block} @media screen and (min-width:1000px) and (max-width:1000px) {#external-query {display:block}} @media print {#screen-only {display:none}}',
  '/width-below.css':'#link-boundary {display:none}',
  '/width-above.css':'#link-boundary {display:none}'
 };
 if(Object.hasOwn(sheets,url.pathname)){
  process.stdout.write('STYLE_REQUEST '+url.pathname+url.search+'\n');
  res.writeHead(200,{'Content-Type':'text/css'});res.end(sheets[url.pathname]);return;
 }
 if(url.pathname==='/slow.css'){
  process.stdout.write('STYLE_REQUEST '+url.pathname+url.search+'\n');
  const timer=setTimeout(()=>{
   if(!res.destroyed){res.writeHead(200,{'Content-Type':'text/css'});res.end('#slow-ready {display:none}');}
  },5000);
  res.once('close',()=>clearTimeout(timer));return;
 }
 if(url.pathname==='/style-repeat.html'){
  const head='<link rel="stylesheet" href="/repeat.css">'+
   '<link rel="stylesheet" href="/cap-a.css"><link rel="stylesheet" href="/cap-b.css"><link rel="stylesheet" href="/cap-c.css">'+
   '<style>#repeat-target {color:#206040}</style><link rel="stylesheet" href="/repeat.css">'+
   '<link rel="stylesheet" href="/cap-denied.css">';
  res.writeHead(200,{'Content-Type':'text/html'});res.end('<html><head><title>Repeated stylesheet</title>'+head+'</head><body><p id="repeat-target">Repeated stylesheet wins</p><p id="cap-marker">four-distinct-sheets-only</p></body></html>');return;
 }
 if(url.pathname==='/style-media.html'){
  const head='<style media="print">#inline-print {display:none}</style><link rel="stylesheet" media="print" href="/print.css">';
  res.writeHead(200,{'Content-Type':'text/html'});res.end('<html><head><title>Screen media</title>'+head+'</head><body><p id="inline-print">inline-print-visible</p><p id="link-print">link-print-visible</p></body></html>');return;
 }
 if(url.pathname==='/style-width.html'){
  const head='<style>#inline-exact,#link-exact,#inline-query,#external-query {display:none} @media screen and (min-width:1000px) and (max-width:1000px) {#inline-query {display:block}} @media print {#screen-only {display:none}}</style>'+
   '<style media="screen and (min-width:1000px) and (max-width:1000px)">#inline-exact {display:block}</style>'+
   '<style media="(max-width:999px)">#inline-boundary {display:none}</style><style media="(min-width:1001px)">#inline-boundary {display:none}</style>'+
   '<link rel="stylesheet" media="screen and (min-width:1000px) and (max-width:1000px)" href="/width-exact.css">'+
   '<link rel="stylesheet" media="(max-width:999px)" href="/width-below.css"><link rel="stylesheet" media="(min-width:1001px)" href="/width-above.css">';
  const body=['inline-exact','link-exact','inline-query','external-query','inline-boundary','link-boundary','screen-only'].map(id=>'<p id="'+id+'">'+id+'-visible</p>').join('');
  res.writeHead(200,{'Content-Type':'text/html'});res.end('<html><head><title>Exact viewport media</title>'+head+'</head><body>'+body+'</body></html>');return;
 }
 if(url.pathname==='/slow-style.html'){
  // Two distinct stalled URLs detect a fresh per-sheet timeout replacing the
  // required one absolute deadline shared by the whole external-sheet load.
  const head='<link rel="stylesheet" href="/slow.css"><link rel="stylesheet" href="/slow.css?second=1">';
  res.writeHead(200,{'Content-Type':'text/html'});res.end('<html><head><title>Stylesheet timeout</title>'+head+'</head><body><p id="slow-ready">slow-style-body-visible</p></body></html>');return;
 }
 if(url.pathname==='/theme.css'){
  res.writeHead(200,{'Content-Type':'text/css'});res.end('.hide {display:none} h1 {color:#112233}');return;
 }
 if(url.pathname==='/styled.html'||url.pathname==='/style-before.html'||url.pathname==='/mixed-style.html'){
  const inline='<style>h1 {color:#206040}</style>';
  const target=url.pathname==='/mixed-style.html'?'http://localhost:'+ports.http+'/theme.css':'/theme.css';
  const link='<link rel="stylesheet" href="'+target+'">';
  const head=url.pathname==='/style-before.html'?inline+link:link+inline;
  res.writeHead(200,{'Content-Type':'text/html'});res.end('<html><head><title>Style order</title>'+head+'</head><body><h1>Style order</h1><p class="hide">needle-not-rendered</p><p>Readable content</p></body></html>');return;
 }
 if(url.pathname==='/lazy.html'){
  res.writeHead(200,{'Content-Type':'text/html'});res.end('<html><head><title>Visible images</title></head><body><img src="/workshop.png" width="64" height="32"><div style="height:1800px"></div><img src="/workshop.png?late=1" width="64" height="32"></body></html>');return;
 }
 if(url.pathname==='/redirect'){res.writeHead(302,{Location:'/article.html'});res.end();return;}
 if(url.pathname==='/downgrade'){res.writeHead(302,{Location:'http://localhost:'+ports.http+'/article.html'});res.end();return;}
 if(url.pathname==='/plain'){res.writeHead(200,{'Content-Type':'text/plain'});res.end('Authenticated TLS text.\n');return;}
 if(url.pathname==='/chunked'){res.writeHead(200,{'Content-Type':'text/html'});const body=fs.readFileSync(path.join(root,'fixtures/article.html'));res.write(body.subarray(0,31));res.write(body.subarray(31,149));res.end(body.subarray(149));return;}
 const name=url.pathname==='/'?'article.html':url.pathname.slice(1);
 if(!['article.html','simple.html','sample.png','landscape.png','workshop.png','error.html'].includes(name)){
  res.writeHead(404,{'Content-Type':'text/html'});res.end('<h1>Not found</h1>');return;
 }
 const file=path.join(root,'fixtures',name);
 if(!fs.existsSync(file)){res.writeHead(404);res.end();return;}
 const bytes=fs.readFileSync(file);res.writeHead(200,{'Content-Type':name.endsWith('.png')?'image/png':'text/html','Content-Length':bytes.length});res.end(bytes);
}
(async()=>{
 const types={good:['localhost','localhost'],rsa:['rsa','rsa'],p384:['p384','p384'],expired:['expired','localhost'],wronghost:['wronghost','localhost'],selfsigned:['selfsigned','localhost']};
 for(const [name,[certificate,key]] of Object.entries(types)){
  const server=https.createServer({cert:fs.readFileSync(path.join(root,'tests/x509',certificate+'.pem')),key:fs.readFileSync(path.join(root,'tests/x509',key+'.key')),
   minVersion:'TLSv1.3',maxVersion:'TLSv1.3',ciphers:'TLS_AES_128_GCM_SHA256',ecdhCurve:'X25519',ALPNProtocols:['http/1.1']},content);
  server.on('tlsClientError',()=>{});
  await listen(server,name);
 }
 const plain=http.createServer((req,res)=>{
  if(req.url==='/upgrade'){res.writeHead(302,{Location:'https://localhost:'+ports.good+'/article.html'});res.end();}else content(req,res);
 });await listen(plain,'http');
 const proxy=net.createServer(client=>{
  const upstream=net.connect({host:'127.0.0.1',port:ports.good});
  sockets.add(upstream);upstream.on('close',()=>sockets.delete(upstream));upstream.on('error',()=>client.destroy());
  let buffer=Buffer.alloc(0),flipped=false;
  client.pipe(upstream);
  upstream.on('data',chunk=>{
   buffer=Buffer.concat([buffer,chunk]);
   while(buffer.length>=5){
    const size=5+buffer.readUInt16BE(3);if(buffer.length<size)break;
    const record=Buffer.from(buffer.subarray(0,size));buffer=buffer.subarray(size);
    if(!flipped&&record[0]===23){record[record.length-1]^=1;flipped=true;}
    client.write(record);
   }
  });
  upstream.on('end',()=>client.end());client.on('close',()=>upstream.destroy());
 });await listen(proxy,'tampered');
 fs.writeFileSync(output,JSON.stringify(ports)+'\n');
})().catch(e=>{process.stderr.write(e.message+'\n');shutdown(1);});
function shutdown(code=0){for(const s of sockets)s.destroy();for(const s of servers)s.close();setTimeout(()=>process.exit(code),20);}
process.on('SIGINT',()=>shutdown());process.on('SIGTERM',()=>shutdown());
