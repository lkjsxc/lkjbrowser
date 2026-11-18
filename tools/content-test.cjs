// Independent test-only HTTP/zlib/encoding fixtures. Never part of the browser runtime.
'use strict';
const fs=require('fs'),path=require('path'),http=require('http'),zlib=require('zlib'),child=require('child_process');
const executable=path.resolve(process.argv[2]),directory=path.resolve(process.argv[3]);
fs.mkdirSync(directory,{recursive:true});
const trust='/etc/ssl/certs/ca-certificates.crt';
const plain=Buffer.from('<!doctype html><title>Content decoding</title><p>Readable café — gzip, deflate, chunks and redirects.</p>\n'.repeat(91));
const gzip=zlib.gzipSync(plain),deflate=zlib.deflateSync(plain);
function crc32(bytes){
 const table=Array.from({length:256},(_,n)=>{for(let i=0;i<8;i++)n=n&1?0xedb88320^(n>>>1):n>>>1;return n>>>0;});
 let c=0xffffffff;for(const b of bytes)c=table[(c^b)&255]^(c>>>8);return(c^0xffffffff)>>>0;
}
function optionalGzip(){
 const h=Buffer.concat([Buffer.from([31,139,8,30,0,0,0,0,0,3,3,0,1,2,3]),Buffer.from('page.html\0offline fixture\0')]);
 const check=Buffer.alloc(2);check.writeUInt16LE(crc32(h)&65535);
 return Buffer.concat([h,check,gzip.subarray(10)]);
}
const optional=optionalGzip(),wrongOptional=Buffer.from(optional);wrongOptional[40]^=1;
const wrongChecksum=Buffer.from(gzip);wrongChecksum[wrongChecksum.length-8]^=1;
const wrongSize=Buffer.from(gzip);wrongSize[wrongSize.length-4]^=1;
const reserved=Buffer.from(gzip);reserved[3]|=32;
const oversized=zlib.gzipSync(Buffer.alloc(16*1024*1024+1,97));
const cases=new Map([
 ['identity',{body:plain,expected:plain}],
 ['gzip',{body:gzip,encoding:'gzip',expected:plain}],
 ['gzip-dynamic',{body:zlib.gzipSync(plain,{level:9}),encoding:'gzip',expected:plain}],
 ['gzip-stored',{body:zlib.gzipSync(plain,{level:0}),encoding:'gzip',expected:plain}],
 ['gzip-fixed',{body:zlib.gzipSync(plain,{strategy:zlib.constants.Z_FIXED}),encoding:'gzip',expected:plain}],
 ['gzip-optional',{body:optional,encoding:'gzip',expected:plain}],
 ['gzip-concatenated',{body:Buffer.concat([gzip,gzip]),encoding:'gzip',expected:Buffer.concat([plain,plain])}],
 ['gzip-chunked',{body:gzip,encoding:'gzip',expected:plain,chunked:true}],
 ['deflate',{body:deflate,encoding:'deflate',expected:plain}],
 ['layered',{body:zlib.deflateSync(gzip),encoding:'gzip, deflate',expected:plain}],
 ['gzip-header-crc',{body:wrongOptional,encoding:'gzip',error:'header checksum'}],
 ['gzip-checksum',{body:wrongChecksum,encoding:'gzip',error:'content checksum'}],
 ['gzip-size',{body:wrongSize,encoding:'gzip',error:'content size'}],
 ['gzip-truncated',{body:gzip.subarray(0,gzip.length-1),encoding:'gzip',error:'incomplete'}],
 ['gzip-reserved',{body:reserved,encoding:'gzip',error:'reserved flags'}],
 ['gzip-junk',{body:Buffer.concat([gzip,Buffer.from('not another member')]),encoding:'gzip',error:'invalid header'}],
 ['gzip-members',{body:Buffer.concat(Array.from({length:17},()=>zlib.gzipSync(Buffer.alloc(0)))),encoding:'gzip',error:'sixteen members'}],
 ['gzip-expanded-limit',{body:oversized,encoding:'gzip',error:'exceeds'}],
 ['deflate-raw',{body:zlib.deflateRawSync(plain),encoding:'deflate',error:'zlib'}],
 ['unsupported',{body:plain,encoding:'br',error:'cannot decode'}],
 ['too-many-codings',{body:plain,encoding:'identity,identity,identity,identity,identity',error:'four content encoding'}],
 ['redirect',{redirect:'/gzip',expected:plain}],
]);
let badAccept=false,requests=0;
const server=http.createServer((request,response)=>{
 requests++;
 if(request.headers['accept-encoding']!=='gzip, deflate')badAccept=true;
 const name=request.url.slice(1),test=cases.get(name);
 if(!test){response.writeHead(404);response.end();return;}
 if(test.redirect){response.writeHead(302,{Location:test.redirect,'Content-Length':'0'});response.end();return;}
 const headers={'Content-Type':'text/html; charset=utf-8','Connection':'close'};
 if(test.encoding)headers['Content-Encoding']=test.encoding;
 if(!test.chunked)headers['Content-Length']=test.body.length;
 response.writeHead(200,headers);
 if(test.chunked){for(let at=0;at<test.body.length;at+=7)response.write(test.body.subarray(at,at+7));response.end();}
 else response.end(test.body);
});
function execute(args){
 return new Promise(resolve=>child.execFile(executable,args,{timeout:20000,maxBuffer:1024*1024},(error,stdout,stderr)=>{
   resolve({code:error?error.code:0,signal:error?error.signal:null,stdout,stderr});
 }));
}
let count=0;
async function verify(name,args,expected,needle){
 const output=path.join(directory,name+'.out');fs.rmSync(output,{force:true});
 const run=await execute(args(output));
 fs.writeFileSync(path.join(directory,name+'.log'),run.stdout+run.stderr);
 if(expected){
  if(run.code!==0||run.signal||!fs.existsSync(output)||!fs.readFileSync(output).equals(expected)){
   throw Error(name+' failed: '+JSON.stringify(run));
  }
 }else if(run.code===0||run.signal||!run.stderr.includes(needle)||fs.existsSync(output)){
  throw Error(name+' was not refused cleanly: '+JSON.stringify(run));
 }
 count++;console.log('PASS '+name);
}
(async()=>{
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
 try{
  const base='http://127.0.0.1:'+server.address().port;
  for(const [name,test] of cases)await verify(name,out=>['fetch',base+'/'+name,out,trust],test.expected,test.error);
  const utf16le=Buffer.from('A😀 café','utf16le'),utf16be=Buffer.from(utf16le);utf16be.swap16();
  const textCases=[
   ['charset-header',Buffer.from([99,97,102,233,32,147,121,101,115,148,32,128]),'text/html; charset="ISO-8859-1"','café “yes” €'],
   ['charset-meta',Buffer.concat([Buffer.from('<meta content="text/html; charset=windows-1252" http-equiv="Content-Type"><p>'),Buffer.from([233])]),'text/html','<meta content="text/html; charset=windows-1252" http-equiv="Content-Type"><p>é'],
   ['charset-utf8-bom',Buffer.concat([Buffer.from([239,187,191]),Buffer.from('café')]),'text/plain; charset=windows-1252','café'],
   ['charset-utf16le-bom',Buffer.concat([Buffer.from([255,254]),utf16le]),'text/html','A😀 café'],
   ['charset-utf16be-bom',Buffer.concat([Buffer.from([254,255]),utf16be]),'text/html','A😀 café'],
   ['charset-unlabelled',Buffer.from([233,32,151,32,128]),'text/html','é — €'],
   ['charset-bad-utf8',Buffer.from([195,40,255]),'text/plain; charset=utf-8','�(�'],
  ];
  for(const [name,bytes,type,expected] of textCases){
   const input=path.join(directory,name+'.in');fs.writeFileSync(input,bytes);
   await verify(name,out=>['decode',input,out,type],Buffer.from(expected));
  }
  const unsupported=path.join(directory,'unsupported.in');fs.writeFileSync(unsupported,'abc');
  await verify('charset-unsupported',out=>['decode',unsupported,out,'text/html; charset=shift_jis'],null,'character encoding');
  if(badAccept)throw Error('native client did not advertise the implemented gzip, deflate profile');
  console.log('PASS '+count+' native content cases; '+requests+' loopback HTTP requests; fixture server stopped');
 }finally{await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error.stack);process.exitCode=1;});
