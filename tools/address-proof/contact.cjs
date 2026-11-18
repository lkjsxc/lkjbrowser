#!/usr/bin/env node
// Unscaled toolbar crops from actual compositor PNGs, with state/width labels.
// Uses only Node's standard library; original captures remain unchanged.
const fs=require('fs'),path=require('path'),zlib=require('zlib');
const proof=path.resolve(process.argv[2]||fs.readFileSync('target/address-proof-last','utf8').trim());
const states=['01-middle-caret','02-partial-selection','03-start-caret','04-after-multiline-paste'];
function paeth(a,b,c){const p=a+b-c,aa=Math.abs(p-a),bb=Math.abs(p-b),cc=Math.abs(p-c);return aa<=bb&&aa<=cc?a:bb<=cc?b:c;}
function decode(file){
 const png=fs.readFileSync(file),idat=[];let width,height,channels;
 if(!png.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))throw Error('Not PNG: '+file);
 for(let at=8;at<png.length;){
  const n=png.readUInt32BE(at),kind=png.toString('ascii',at+4,at+8),data=png.subarray(at+8,at+8+n);
  if(kind==='IHDR'){
   width=data.readUInt32BE(0);height=data.readUInt32BE(4);channels=data[9]===2?3:data[9]===6?4:0;
   if(data[8]!==8||!channels||data[12]!==0)throw Error('Expected noninterlaced RGB/RGBA8: '+file);
  }
  if(kind==='IDAT')idat.push(data);
  at+=n+12;
 }
 const raw=zlib.inflateSync(Buffer.concat(idat)),stride=width*channels,pixels=Buffer.alloc(stride*height);
 for(let y=0;y<height;y++){
  const filter=raw[y*(stride+1)];
  for(let x=0;x<stride;x++){
   const a=x>=channels?pixels[y*stride+x-channels]:0,b=y?pixels[(y-1)*stride+x]:0,c=y&&x>=channels?pixels[(y-1)*stride+x-channels]:0;
   const predictor=filter===0?0:filter===1?a:filter===2?b:filter===3?(a+b)>>1:filter===4?paeth(a,b,c):NaN;
   if(!Number.isFinite(predictor))throw Error('Unknown PNG filter');
   pixels[y*stride+x]=(raw[y*(stride+1)+1+x]+predictor)&255;
  }
 }
 return{width,height,channels,pixels};
}
const outputWidth=1944,rowHeight=88,outputHeight=states.length*rowHeight,output=Buffer.alloc(outputWidth*outputHeight*3,255);
const digits={
 '0':'111101101101111','1':'010110010010111','2':'111001111100111','3':'111001111001111','4':'101101111001001',
 '5':'111100111001111','6':'111100111101111','7':'111001010010010','8':'111101111101111','9':'111101111001111','/':'001001010100100'
};
function label(s,left,top){
 for(const ch of s){const bits=digits[ch];if(bits)for(let y=0;y<5;y++)for(let x=0;x<3;x++)if(bits[y*3+x]==='1')for(let dy=0;dy<2;dy++)for(let dx=0;dx<2;dx++){
  const at=((top+y*2+dy)*outputWidth+left+x*2+dx)*3;output[at]=27;output[at+1]=42;output[at+2]=50;
 }left+=8;}
}
for(let row=0;row<states.length;row++)for(const viewport of [1440,480]){
 const image=decode(path.join(proof,String(viewport),states[row]+'.png'));
 if(image.width!==viewport||image.height!==760)throw Error('Unexpected capture size');
 const left=viewport===1440?0:1464,top=row*rowHeight;
 label((row+1)+' / '+viewport,left+8,top+5);
 for(let y=0;y<60;y++)for(let x=0;x<viewport;x++){
  const src=(y*viewport+x)*image.channels,dst=((top+24+y)*outputWidth+left+x)*3;
  image.pixels.copy(output,dst,src,src+3);
 }
}
function crc(b){let n=0xffffffff;for(const x of b){n^=x;for(let k=0;k<8;k++)n=(n>>>1)^((n&1)?0xedb88320:0);}return(n^0xffffffff)>>>0;}
function chunk(kind,data){const name=Buffer.from(kind),n=Buffer.alloc(4),c=Buffer.alloc(4);n.writeUInt32BE(data.length);c.writeUInt32BE(crc(Buffer.concat([name,data])));return Buffer.concat([n,name,data,c]);}
const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(outputWidth);ihdr.writeUInt32BE(outputHeight,4);ihdr[8]=8;ihdr[9]=2;
const scan=Buffer.alloc((outputWidth*3+1)*outputHeight);
for(let y=0;y<outputHeight;y++)output.copy(scan,y*(outputWidth*3+1)+1,y*outputWidth*3,(y+1)*outputWidth*3);
const file=path.join(proof,'acceptance-contact.png');
fs.writeFileSync(file,Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),chunk('IDAT',zlib.deflateSync(scan)),chunk('IEND',Buffer.alloc(0))]));
console.log(file);
