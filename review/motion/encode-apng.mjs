// Package real compositor PNG frames into APNG without changing their pixels.
import fs from "node:fs";
import path from "node:path";
const [manifest, output] = process.argv.slice(2);
if (!manifest || !output) throw new Error("usage: node encode-apng.mjs FRAMES_TSV OUTPUT.png");
const frames = fs.readFileSync(manifest, "utf8").trim().split("\n").filter(Boolean).map(line => {
    const [milliseconds, filename] = line.split("\t");
    const time = Number(milliseconds);
    if (!Number.isFinite(time) || !filename) throw new Error("invalid frame record");
    return {time, filename: path.resolve(path.dirname(manifest), filename)};
});
if (frames.length < 2) throw new Error("at least two frames are required");
const signature = Buffer.from([137,80,78,71,13,10,26,10]);
const table = new Uint32Array(256);
for (let n=0;n<256;n++) {
    let value=n;
    for(let k=0;k<8;k++) value=(value&1)?(0xedb88320^(value>>>1)):(value>>>1);
    table[n]=value>>>0;
}
function crc(bytes) {
    let value=0xffffffff;
    for(const byte of bytes) value=table[(value^byte)&255]^(value>>>8);
    return (value^0xffffffff)>>>0;
}
function chunk(type, bytes) {
    const kind=Buffer.from(type,"ascii");
    const header=Buffer.alloc(4);header.writeUInt32BE(bytes.length);
    const checksum=Buffer.alloc(4);checksum.writeUInt32BE(crc(Buffer.concat([kind,bytes])));
    return Buffer.concat([header,kind,bytes,checksum]);
}
function readPNG(filename) {
    const bytes=fs.readFileSync(filename);
    if(!bytes.subarray(0,8).equals(signature))throw new Error("not PNG: "+filename);
    let offset=8;const chunks=[];
    while(offset<bytes.length){
        if(offset+12>bytes.length)throw new Error("truncated PNG");
        const length=bytes.readUInt32BE(offset);
        if(length>bytes.length-offset-12)throw new Error("truncated PNG chunk");
        const type=bytes.toString("ascii",offset+4,offset+8);
        const data=bytes.subarray(offset+8,offset+8+length);
        if(crc(bytes.subarray(offset+4,offset+8+length))!==bytes.readUInt32BE(offset+8+length))throw new Error("PNG CRC mismatch");
        chunks.push({type,data});
        offset+=12+length;
        if(type==="IEND")break;
    }
    if(chunks[0]?.type!=="IHDR" || chunks[0].data.length!==13)throw new Error("invalid IHDR");
    if(!chunks.some(c=>c.type==="IDAT"))throw new Error("missing IDAT");
    if(chunks.some(c=>c.type==="acTL"))throw new Error("input is already animated");
    return chunks;
}
const first=readPNG(frames[0].filename);
const ihdr=first[0].data;
const width=ihdr.readUInt32BE(0),height=ihdr.readUInt32BE(4);
const pieces=[signature,chunk("IHDR",ihdr)];
for(const entry of first.slice(1)){
    if(entry.type==="IDAT")break;
    pieces.push(chunk(entry.type,entry.data));
}
const animation=Buffer.alloc(8);animation.writeUInt32BE(frames.length,0);animation.writeUInt32BE(0,4);
pieces.push(chunk("acTL",animation));
let sequence=0;
for(let i=0;i<frames.length;i++){
    const source=i===0?first:readPNG(frames[i].filename);
    if(!source[0].data.equals(ihdr))throw new Error("frame format changed");
    const delay=i+1<frames.length?Math.round(frames[i+1].time-frames[i].time):1000;
    if(delay<1 || delay>65535)throw new Error("frame times must increase, each by less than 65536 ms");
    const control=Buffer.alloc(26);
    control.writeUInt32BE(sequence++,0);control.writeUInt32BE(width,4);control.writeUInt32BE(height,8);
    control.writeUInt16BE(delay,20);control.writeUInt16BE(1000,22);
    // Full-canvas SOURCE replacement, with no disposal between frames.
    control[24]=0;control[25]=0;
    pieces.push(chunk("fcTL",control));
    for(const entry of source.filter(c=>c.type==="IDAT")){
        if(i===0)pieces.push(chunk("IDAT",entry.data));
        else{
            const prefix=Buffer.alloc(4);prefix.writeUInt32BE(sequence++);
            pieces.push(chunk("fdAT",Buffer.concat([prefix,entry.data])));
        }
    }
}
pieces.push(chunk("IEND",Buffer.alloc(0)));
fs.writeFileSync(output,Buffer.concat(pieces));
process.stdout.write("APNG: "+frames.length+" real compositor frames, "+width+"x"+height+", original compressed pixel streams preserved\n");
