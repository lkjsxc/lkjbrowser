/* Temporary capability bridge. No libc, no Wayland protocol knowledge.
 * Framed TCP input: little-endian uint32 length, uint32 attach_fd (0 or 1),
 * then opaque bytes. The one optional descriptor is the read-write file named
 * on argv[2]. Unix input is forwarded byte for byte; received descriptors close.
 * syscall numbers/layouts are Linux x86-64 only.
 */
typedef unsigned long U;
typedef unsigned int U32;
typedef unsigned short U16;
typedef long I;
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
static unsigned char data[65536];
static unsigned char control[4096];
static I unixfd, tcpfd, framefd;
void bridge_main(U *sp) {
 U argc=sp[0]; char **argv=(char **)(sp+1);
 if(argc!=3) fail("usage: byte-descriptor-bridge UNIX_SOCKET FRAME_FILE\n");
 struct { U16 family; char path[108]; } un={1,{0}};
 U n=len(argv[1]); if(n==0||n>=108) fail("Unix socket path too long\n");
 for(U i=0;i<n;i++) un.path[i]=argv[1][i];
 unixfd=call(41,1,524289,0,0,0,0); if(unixfd<0) fail("Unix socket failed\n");
 if(call(42,unixfd,(I)&un,n+3,0,0,0)<0) fail("Unix connect failed\n");
 framefd=call(257,-100,(I)argv[2],524290,0,0,0);
 if(framefd<0) fail("frame open failed\n");
 I listener=call(41,2,524289,0,0,0,0);
 if(listener<0) fail("TCP socket failed\n");
 struct { U16 family; U16 port; U32 address; U pad; } addr={2,0,0x0100007f,0};
 if(call(49,listener,(I)&addr,16,0,0,0)<0) fail("loopback bind failed\n");
 if(call(50,listener,1,0,0,0,0)<0) fail("listen failed\n");
 U32 asz=16; if(call(51,listener,(I)&addr,(I)&asz,0,0,0)<0) fail("getsockname failed\n");
 U port=((addr.port&255)<<8)|(addr.port>>8);
 char out[8]; U p=7; out[p]='\n'; do {out[--p]='0'+port%10; port/=10;}while(port);
 writeall(1,out+p,8-p);
 tcpfd=call(288,listener,0,0,524288,0,0);
 call(3,listener,0,0,0,0,0);
 if(tcpfd<0) fail("accept failed\n");
 int one=1; call(54,tcpfd,6,1,(I)&one,4,0);
 for(;;) {
  struct Poll poll[2]={{(int)tcpfd,1,0},{(int)unixfd,1,0}};
  I z=call(7,(I)poll,2,-1,0,0,0);
  if(z==-4) continue;
  if(z<0) fail("poll failed\n");
  if(poll[0].revents&1) {
   U32 hdr[2]; if(readall(tcpfd,hdr,8)<0) end(0);
   if(hdr[0]==0||hdr[0]>sizeof(data)||hdr[1]>1) fail("invalid transport frame\n");
   if(readall(tcpfd,data,hdr[0])<0) end(0);
   if(hdr[1]) {
    struct Io io={data,hdr[0]};
    struct Cmsg cm={20,1,1,(int)framefd,0};
    struct Msg m={0,0,0,&io,1,&cm,24,0,0};
    I r; do {r=call(46,unixfd,(I)&m,16384,0,0,0);}while(r==-4);
    if(r<=0) fail("sendmsg failed\n");
    if((U)r<hdr[0]&&writeall(unixfd,data+r,hdr[0]-r)<0) end(0);
   } else if(writeall(unixfd,data,hdr[0])<0) end(0);
  }
  if(poll[1].revents&1) {
   struct Io io={data,sizeof(data)};
   struct Msg m={0,0,0,&io,1,control,sizeof(control),0,0};
   I r=call(47,unixfd,(I)&m,1073741824,0,0,0);
   if(r==-4) continue;
 if(r<=0) end(0);
   U off=0;
   while(off+16<=m.controls) {
    struct Cmsg *cm=(struct Cmsg*)(control+off);
    if(cm->n<16||cm->n>m.controls-off) break;
    if(cm->level==1&&cm->type==1) {
     int *fds=(int*)(control+off+16);
     for(U j=0;j<(cm->n-16)/4;j++) call(3,fds[j],0,0,0,0,0);
    }
    off+=(cm->n+7)&~7UL;
   }
   if(writeall(tcpfd,data,r)<0) end(0);
  }
  if((poll[0].revents|poll[1].revents)&(8|16|32)) end(0);
 }
}
__asm__(".global _start\n_start:\nmov %rsp,%rdi\nand $-16,%rsp\ncall bridge_main\nmov $60,%rax\nxor %rdi,%rdi\nsyscall\n");
