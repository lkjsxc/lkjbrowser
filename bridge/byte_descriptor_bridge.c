/* Temporary capability bridge. No libc and no Wayland protocol knowledge.
 *
 * A fresh 32-byte launch key is read from inherited stdin. Before any command,
 * each TCP candidate must supply that exact preamble within 250 ms. Rejected
 * candidates are closed and the listener remains available. The Unix socket and
 * frame file are opened only after authentication. The key is never printed.
 *
 * Client commands: uint32 byte_length, uint32 operation, then opaque payload.
 * 0 forwards bytes; 1 forwards bytes with the frame descriptor; 2 takes a client
 * token followed by bytes and attaches a fresh pipe's write end; 3 takes a
 * received-descriptor token followed by bytes to write and close; 4 closes a
 * token. All integers are little endian.
 *
 * Server records: uint32 zero, uint32 ((total_length << 16) | kind), payload.
 * 3 announces descriptor capability version 1. 4 carries Unix stream bytes:
 * uint32 byte_length, uint32 descriptor_count, descriptor tokens, opaque bytes.
 * 1 carries pipe bytes: token, byte_length, bytes. 2 carries token and status
 * (zero is EOF). Records are zero-padded to four-byte alignment. Unix reads
 * remain independently framed, so an ancillary descriptor never corrupts a
 * partially received protocol message. Protocol interpretation stays native.
 *
 * Descriptor work is bounded to 64 live handles, 1 MiB per transfer and five
 * seconds of inactivity. A failed transfer closes its pipe without partial
 * success. Syscall numbers/layouts are Linux x86-64 only.
 */
typedef unsigned long U;
typedef unsigned int U32;
typedef unsigned short U16;
typedef long I;

/* GCC can lower initialization to memset even in a freestanding build. */
void *memset(void *memory, int value, U count) {
 volatile unsigned char *bytes=memory;
 for(U i=0;i<count;i++) bytes[i]=(unsigned char)value;
 return memory;
}

static I call(I n,I a,I b,I c,I d,I e,I f) {
 register I r10 __asm__("r10")=d;
 register I r8 __asm__("r8")=e;
 register I r9 __asm__("r9")=f;
 I ret;
 __asm__ volatile("syscall":"=a"(ret):"a"(n),"D"(a),"S"(b),"d"(c),
                  "r"(r10),"r"(r8),"r"(r9):"rcx","r11","memory");
 return ret;
}
static void end(I code) { call(60,code,0,0,0,0,0); for (;;) {} }
static U len(const char *s) { U n=0; while(s[n]) ++n; return n; }
static I writeall(I fd,const void *p,U n) {
 const char *b=p; while(n) { I r=call(1,fd,(I)b,n,0,0,0);
 if(r==-4) continue;
 if(r<=0) return -1;
 b+=r; n-=r; } return 0;
}
static I readall(I fd,void *p,U n) {
 char *b=p; while(n) { I r=call(0,fd,(I)b,n,0,0,0);
 if(r==-4) continue;
 if(r<=0) return -1;
 b+=r; n-=r; } return 0;
}
static void fail(const char *s) { writeall(2,s,len(s)); end(1); }
struct Io { void *base; U n; };
struct Msg { void *name; U32 namesz; U32 pad; struct Io *iov; U niov; void *control; U controls; U32 flags; U32 pad2; };
struct Cmsg { U n; U32 level; U32 type; int fd; U32 padding; };
struct Poll { int fd; short events; short revents; };
#define LIMIT 1048576UL
#define SLOTS 64
struct Transfer { I fd; U32 token, kind; unsigned char *bytes; U count, offset, total, touched; };
static struct Transfer slots[SLOTS];
static unsigned char data[LIMIT+16], input[32768], record[33312], control[4096];
static I unixfd, tcpfd, framefd;
static U32 next_token=1;
static U now_ms(void) {
 struct {I seconds,nanos;} ts;
 if(call(228,1,(I)&ts,0,0,0,0)<0) fail("monotonic clock failed\n");
 return (U)ts.seconds*1000+(U)ts.nanos/1000000;
}
static I authenticate(I fd,const unsigned char *token) {
 unsigned char candidate[32]; U have=0, deadline=now_ms()+250;
 while(have<32) {
  U now=now_ms(); if(now>=deadline) return 0;
  struct Poll p={(int)fd,1,0};
  I ready=call(7,(I)&p,1,(I)(deadline-now),0,0,0);
  if(ready==-4) continue;
  if(ready<=0 || !(p.revents&1)) return 0;
  I n=call(0,fd,(I)(candidate+have),32-have,0,0,0);
  if(n==-4) continue;
  if(n<=0) return 0;
  have+=(U)n;
 }
 unsigned char different=0;
 for(U i=0;i<32;i++) different|=candidate[i]^token[i];
 return different==0 && now_ms()<deadline;
}
static void record_send(U32 kind,const void *payload,U n) {
 U size=(8+n+3)&~3UL;
 if(size>65532) fail("transport record too large\n");
 U32 hdr[2]={0,((U32)size<<16)|kind};
 if(writeall(tcpfd,hdr,8)<0 || writeall(tcpfd,payload,n)<0) end(0);
 U32 zero=0;
 if(size>n+8 && writeall(tcpfd,&zero,size-n-8)<0) end(0);
}
static void done(U32 token,U32 status) {
 U32 payload[2]={token,status}; record_send(2,payload,8);
}
static struct Transfer *find(U32 token) {
 for(U i=0;i<SLOTS;i++) if(slots[i].kind && slots[i].token==token) return &slots[i];
 return 0;
}
static struct Transfer *adopt(I fd,U32 token,U32 kind) {
 for(U i=0;i<SLOTS;i++) if(!slots[i].kind) {
  struct Transfer *s=&slots[i];
  s->fd=fd; s->token=token; s->kind=kind; s->bytes=0;
  s->count=0; s->offset=0; s->total=0; s->touched=now_ms();
  I flags=call(72,fd,3,0,0,0,0);
  if(flags<0 || call(72,fd,4,flags|2048,0,0,0)<0) { s->kind=0; return 0; }
  return s;
 }
 return 0;
}
static void release(struct Transfer *s) {
 if(s->bytes) call(11,(I)s->bytes,s->count,0,0,0,0);
 call(3,s->fd,0,0,0,0,0);
 s->kind=0; s->bytes=0;
}
static I send_descriptor(const void *bytes,U n,I fd) {
 struct Io io={(void*)bytes,n};
 struct Cmsg cm={20,1,1,(int)fd,0};
 struct Msg m={0,0,0,&io,1,&cm,24,0,0};
 I r; do {r=call(46,unixfd,(I)&m,16384,0,0,0);}while(r==-4);
 if(r<=0) return -1;
 return (U)r<n ? writeall(unixfd,(const char*)bytes+r,n-r) : 0;
}
void bridge_main(U *sp) {
 U argc=sp[0]; char **argv=(char **)(sp+1);
 if(argc!=3) fail("usage: byte-descriptor-bridge UNIX_SOCKET FRAME_FILE\n");
 unsigned char token[32];
 if(readall(0,token,sizeof(token))<0) fail("missing launcher handoff key\n");
 call(3,0,0,0,0,0,0);
 struct {U handler,flags,restorer,mask;} ignored={1,0,0,0};
 if(call(13,13,(I)&ignored,0,8,0,0)<0) fail("SIGPIPE disposition failed\n");
 struct { U16 family; char path[108]; } un={1,{0}};
 U n=len(argv[1]); if(n==0||n>=108) fail("Unix socket path too long\n");
 for(U i=0;i<n;i++) un.path[i]=argv[1][i];
 I listener=call(41,2,524289,0,0,0,0);
 if(listener<0) fail("TCP socket failed\n");
 struct { U16 family; U16 port; U32 address; U pad; } addr={2,0,0x0100007f,0};
 if(call(49,listener,(I)&addr,16,0,0,0)<0) fail("loopback bind failed\n");
 if(call(50,listener,1,0,0,0,0)<0) fail("listen failed\n");
 U32 asz=16; if(call(51,listener,(I)&addr,(I)&asz,0,0,0)<0) fail("getsockname failed\n");
 U port=((addr.port&255)<<8)|(addr.port>>8);
 char out[8]; U p=7; out[p]='\n'; do {out[--p]='0'+port%10; port/=10;}while(port);
 writeall(1,out+p,8-p);
 for(;;) {
  I candidate=call(288,listener,0,0,524288,0,0);
  if(candidate==-4) continue;
  if(candidate<0) fail("accept failed\n");
  if(authenticate(candidate,token)) {tcpfd=candidate;break;}
  call(3,candidate,0,0,0,0,0);
 }
 call(3,listener,0,0,0,0,0);
 for(U i=0;i<sizeof(token);i++) token[i]=0;
 unixfd=call(41,1,524289,0,0,0,0); if(unixfd<0) fail("Unix socket failed\n");
 if(call(42,unixfd,(I)&un,n+3,0,0,0)<0) fail("Unix connect failed\n");
 framefd=call(257,-100,(I)argv[2],524290,0,0,0);
 if(framefd<0) fail("frame open failed\n");
 int one=1; call(54,tcpfd,6,1,(I)&one,4,0);
 U32 version=1; record_send(3,&version,4);
 for(;;) {
  struct Poll poll[SLOTS+2]={{(int)tcpfd,1,0},{(int)unixfd,1,0}};
  for(U i=0;i<SLOTS;i++) {
   poll[i+2].fd=slots[i].kind ? (int)slots[i].fd : -1;
   poll[i+2].events=slots[i].kind==2 ? 4 : slots[i].kind==3 ? 1 : 0;
  }
  I z=call(7,(I)poll,SLOTS+2,100,0,0,0);
  if(z==-4) continue;
  if(z<0) fail("poll failed\n");
  if(poll[0].revents&1) {
   U32 hdr[2]; if(readall(tcpfd,hdr,8)<0) end(0);
   if(hdr[0]==0||hdr[0]>sizeof(data)||hdr[1]>4) fail("invalid transport command\n");
   if(readall(tcpfd,data,hdr[0])<0) end(0);
   if(hdr[1]==0) { if(writeall(unixfd,data,hdr[0])<0) end(0); }
   else if(hdr[1]==1) { if(send_descriptor(data,hdr[0],framefd)<0) end(0); }
   else if(hdr[1]==2) {
    if(hdr[0]<5) fail("invalid pipe command\n");
    U32 token=*(U32*)data;
    if(!(token&0x80000000U) || find(token)) fail("invalid pipe token\n");
    int pair[2];
    if(call(293,(I)pair,524288,0,0,0,0)<0) {done(token,1);continue;}
    struct Transfer *s=adopt(pair[0],token,3);
    if(!s) {call(3,pair[0],0,0,0,0,0);call(3,pair[1],0,0,0,0,0);done(token,1);continue;}
    I result=send_descriptor(data+4,hdr[0]-4,pair[1]);
    call(3,pair[1],0,0,0,0,0);
    if(result<0) end(0);
   } else if(hdr[1]==3) {
    if(hdr[0]<4 || hdr[0]-4>LIMIT) fail("invalid descriptor write\n");
    struct Transfer *s=find(*(U32*)data);
    if(s && s->kind==1) {
     U count=hdr[0]-4;
     if(!count) release(s);
     else {
      I memory=call(9,0,count,3,34,-1,0);
      if(memory<0) release(s);
      else {
       s->bytes=(unsigned char*)memory; s->count=count; s->kind=2; s->touched=now_ms();
       for(U i=0;i<count;i++) s->bytes[i]=data[i+4];
      }
     }
    }
   } else if(hdr[1]==4) {
    if(hdr[0]!=4) fail("invalid descriptor close\n");
    struct Transfer *s=find(*(U32*)data); if(s) release(s);
   }
  }
  if(poll[1].revents&1) {
   struct Io io={input,sizeof(input)};
   struct Msg m={0,0,0,&io,1,control,sizeof(control),0,0};
   I r=call(47,unixfd,(I)&m,1073741824,0,0,0);
   if(r==-4) continue;
   if(r<=0) end(0);
   if(m.flags&8) fail("descriptor control truncated\n");
   U32 *words=(U32*)record;
   words[0]=(U32)r; words[1]=0;
   U off=0;
   while(off+16<=m.controls) {
    struct Cmsg *cm=(struct Cmsg*)(control+off);
    if(cm->n<16||cm->n>m.controls-off) fail("invalid descriptor control\n");
    if(cm->level==1&&cm->type==1) {
     int *fds=(int*)(control+off+16);
     for(U j=0;j<(cm->n-16)/4;j++) {
      if(words[1]>=64) {call(3,fds[j],0,0,0,0,0);fail("too many received descriptors\n");}
      U32 token=next_token++; if(next_token&0x80000000U) fail("descriptor token exhausted\n");
      if(!adopt(fds[j],token,1)) {call(3,fds[j],0,0,0,0,0);token=0;}
      words[2+words[1]++]=token;
     }
    }
    off+=(cm->n+7)&~7UL;
   }
   U begin=8+words[1]*4;
   for(U i=0;i<(U)r;i++) record[begin+i]=input[i];
   record_send(4,record,begin+(U)r);
  }
  U now=now_ms();
  for(U i=0;i<SLOTS;i++) {
   struct Transfer *s=&slots[i]; if(!s->kind) continue;
   short re=poll[i+2].revents;
   /* A slot may have been replaced since this poll; only operate its current FD. */
   if(poll[i+2].fd!=(int)s->fd) re=0;
   if(s->kind==2 && (re&4)) {
    I r=call(1,s->fd,(I)(s->bytes+s->offset),s->count-s->offset,0,0,0);
    if(r>0) {s->offset+=r;s->touched=now;if(s->offset==s->count) release(s);}
    else if(r!=-4 && r!=-11) release(s);
   } else if(s->kind==3 && (re&(1|16))) {
    I r=call(0,s->fd,(I)(record+8),8192,0,0,0);
    if(r>0) {
     s->total+=r; s->touched=now;
     if(s->total>LIMIT) {done(s->token,2);release(s);}
     else {*(U32*)record=s->token;*(U32*)(record+4)=(U32)r;record_send(1,record,(U)r+8);}
    } else if(r==0) {done(s->token,0);release(s);}
    else if(r!=-4 && r!=-11) {done(s->token,1);release(s);}
   }
   if(s->kind && ((re&(8|32)) || now-s->touched>=5000)) {
    if(s->kind==3) done(s->token,1);
    release(s);
   }
  }
  if((poll[0].revents|poll[1].revents)&(8|16|32)) end(0);
 }
}
__asm__(".global _start\n_start:\nmov %rsp,%rdi\nand $-16,%rsp\ncall bridge_main\nmov $60,%rax\nxor %rdi,%rdi\nsyscall\n");
