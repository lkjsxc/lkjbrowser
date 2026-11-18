#!/usr/bin/env node
// Assemble only retained compositor captures; this is a proof tool, not browser code.
const fs=require('fs');
const path=require('path');
let sharp;
try { sharp=require(process.env.LKJBROWSER_SHARP || path.resolve('.deps/pages-tools/node_modules/sharp')); }
catch { sharp=require('sharp'); }
const round=process.argv[2]||'after';
if(!/^[A-Za-z0-9_-]+$/.test(round))throw Error('Invalid round');
const names=fs.readFileSync('docs/pages/pages.tsv','utf8').trim().split('\n').filter(x=>x&&!x.startsWith('#')).map(x=>x.split('\t')[0]);
const labels={python:'Python tutorial',sqlite:'SQLite',wikipedia:'Wikipedia',w3c:'W3C tables',curl:'curl FAQ',git:'Git Book',hn:'Hacker News',paulgraham:'Paul Graham',mailarchive:'PostgreSQL mailing list',freebsd:'FreeBSD'};
const escape=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
const label=(text,width)=>Buffer.from('<svg width="'+width+'" height="32"><rect width="100%" height="32" fill="#193443"/><text x="12" y="22" font-family="Liberation Sans,Arial,sans-serif" font-size="17" fill="#ffffff">'+escape(text)+'</text></svg>');
(async()=>{
 const pairs='shots/pages/pairs-'+round;fs.mkdirSync(pairs,{recursive:true});const tiles=[];
 for(let i=0;i<names.length;i++){
  const name=names[i],title=labels[name]||name,before='shots/pages/before/'+name+'.png',after='shots/pages/'+round+'/'+name+'.png';
  for(const file of [before,after]){const m=await sharp(file).metadata();if(m.width!==1000||m.height!==760)throw Error('Unexpected capture dimensions: '+file);}
  const pair=await sharp({create:{width:2000,height:792,channels:3,background:'#ffffff'}}).composite([
   {input:label(title+' — before',1000),left:0,top:0},{input:label(title+' — after',1000),left:1000,top:0},
   {input:before,left:0,top:32},{input:after,left:1000,top:32}]).png().toBuffer();
  fs.writeFileSync(pairs+'/'+name+'.png',pair);
  const reduced=await sharp(pair).resize(1000,396).toBuffer();
  tiles.push({input:reduced,left:(i%2)*1000,top:Math.floor(i/2)*406});
 }
 const output='shots/pages/contact-'+round+'.png';
 await sharp({create:{width:2000,height:Math.ceil(names.length/2)*406,channels:3,background:'#d8e1e6'}}).composite(tiles).png().toFile(output);
 console.log(output,'2000x'+Math.ceil(names.length/2)*406,names.length+' actual before/after pairs');
})().catch(e=>{console.error(e);process.exitCode=1;});
