/* Independent isolated test peer: actual wl_data_device source/sink.
 * No browser code or clipboard API is reused. Only a caller-owned private
 * Wayland socket with the proof marker is accepted. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

static int connection, source_mode, selected, configured, done, got_sync;
static int manager, compositor, shm, wm, seat, input_fds[64], fd_count;
static int transfer_fd = -1, out_fd = -1;
static uint32_t selection_offer;
static unsigned char payload[1048576], incoming[131072];
static size_t payload_len, incoming_len, transferred;
static uint32_t offers[128]; static int plain[128], utf8[128], offer_count;
static uint32_t DISPLAY=1, REGISTRY=2, SYNC=3, next_id=4;
static uint32_t COMPOSITOR, SHM, WM, SEAT, MANAGER, KEYBOARD, DEVICE, SURFACE, XDG, TOP, POOL, BUFFER, SOURCE;
static void fail(const char *what) { perror(what); exit(1); }
static uint32_t num(const unsigned char *p) { uint32_t n; memcpy(&n,p,4); return n; }
static void put(unsigned char *p, uint32_t n) { memcpy(p,&n,4); }
static long milliseconds(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t);
    return t.tv_sec*1000L+t.tv_nsec/1000000L;
}
static size_t wire_string(unsigned char *p, const char *s) {
    size_t n=strlen(s)+1, z=(n+3)&~3u; put(p,(uint32_t)n);
    memcpy(p+4,s,n); memset(p+4+n,0,z-n); return z+4;
}
static void send_message(uint32_t object, uint16_t op, const void *body, size_t n, int fd) {
    unsigned char packet[4096], control[CMSG_SPACE(sizeof(int))];
    if(n+8>sizeof(packet)) {errno=EOVERFLOW;fail("message size");}
    put(packet,object);put(packet+4,((uint32_t)(n+8)<<16)|op);
    if(n)memcpy(packet+8,body,n);
    struct iovec iov={packet,n+8};
    struct msghdr msg={0};msg.msg_iov=&iov;msg.msg_iovlen=1;
    if(fd>=0) {
        memset(control,0,sizeof(control));msg.msg_control=control;msg.msg_controllen=sizeof(control);
        struct cmsghdr *c=CMSG_FIRSTHDR(&msg);c->cmsg_level=SOL_SOCKET;c->cmsg_type=SCM_RIGHTS;c->cmsg_len=CMSG_LEN(sizeof(int));
        memcpy(CMSG_DATA(c),&fd,sizeof(fd));
    }
    ssize_t count=sendmsg(connection,&msg,MSG_NOSIGNAL);
    if(count!=(ssize_t)(n+8))fail("sendmsg");
}
static void words(uint32_t object,uint16_t op,const uint32_t *values,size_t count) {
    send_message(object,op,values,count*4,-1);
}
#define W(o,p,...) do {uint32_t v[]={__VA_ARGS__};words(o,p,v,sizeof(v)/4);} while(0)
static void empty(uint32_t object,uint16_t op){send_message(object,op,NULL,0,-1);}
static void bind_global(uint32_t name,const char *interface,uint32_t version,uint32_t id) {
    unsigned char b[256];put(b,name);size_t n=4+wire_string(b+4,interface);
    put(b+n,version);put(b+n+4,id);send_message(REGISTRY,0,b,n+8,-1);
}
static void string_message(uint32_t object,uint16_t op,const char *s) {
    unsigned char b[1024];size_t n=wire_string(b,s);send_message(object,op,b,n,-1);
}
static int take_fd(void) {
    if(!fd_count){errno=EPROTO;fail("missing event fd");}
    int fd=input_fds[0];memmove(input_fds,input_fds+1,(size_t)(--fd_count)*sizeof(int));return fd;
}
static int offer_index(uint32_t id) {
    for(int i=0;i<offer_count;i++)if(offers[i]==id)return i;
    return -1;
}
static void request_transfer(void) {
    if(source_mode||transfer_fd>=0||!selection_offer)return;
    int i=offer_index(selection_offer);if(i<0||(!plain[i]&&!utf8[i]))return;
    int fds[2];if(pipe2(fds,O_CLOEXEC|O_NONBLOCK))fail("pipe");
    unsigned char b[256];const char *mime=utf8[i]?"text/plain;charset=utf-8":"text/plain";
    size_t n=wire_string(b,mime);send_message(selection_offer,1,b,n,fds[1]);close(fds[1]);
    transfer_fd=fds[0];printf("RECEIVE offer=%u mime=%s\n",selection_offer,mime);fflush(stdout);
}
static void dispatch(uint32_t object,uint16_t op,unsigned char *a,size_t n) {
    if(object==DISPLAY&&op==0) {
        fprintf(stderr,"Wayland protocol error object=%u code=%u: %s\n",num(a),num(a+4),n>=12?(char*)a+12:"");
        exit(1);
    }
    if(object==SYNC&&op==0){got_sync=1;return;}
    if(object==REGISTRY&&op==0&&n>=12) {
        uint32_t name=num(a),len=num(a+4);if(len>n-8||!len)return;
        char *s=(char*)a+8;size_t end=8+((len+3)&~3u);if(end+4>n)return;uint32_t version=num(a+end);
        if(!strcmp(s,"wl_compositor")){COMPOSITOR=next_id++;bind_global(name,s,version<4?version:4,COMPOSITOR);compositor=1;}
        else if(!strcmp(s,"wl_shm")){SHM=next_id++;bind_global(name,s,1,SHM);shm=1;}
        else if(!strcmp(s,"xdg_wm_base")){WM=next_id++;bind_global(name,s,1,WM);wm=1;}
        else if(!strcmp(s,"wl_seat")){SEAT=next_id++;bind_global(name,s,1,SEAT);seat=1;}
        else if(!strcmp(s,"wl_data_device_manager")){MANAGER=next_id++;bind_global(name,s,1,MANAGER);manager=1;}
    } else if(object==WM&&op==0&&n>=4){W(WM,3,num(a));}
    else if(object==SEAT&&op==0&&n>=4) {
        static int keyboard;
        if((num(a)&2)&&!keyboard){KEYBOARD=next_id++;W(SEAT,1,KEYBOARD);keyboard=1;}
    } else if(object==KEYBOARD&&op==0){close(take_fd());}
    else if(object==KEYBOARD&&op==1){printf("KEYBOARD_ENTER serial=%u\n",num(a));fflush(stdout);}
    else if(object==KEYBOARD&&op==2){printf("KEYBOARD_LEAVE\n");fflush(stdout);}
    else if(object==KEYBOARD&&op==3&&n>=16) {
        printf("KEY serial=%u key=%u state=%u\n",num(a),num(a+8),num(a+12));fflush(stdout);
        if(source_mode&&!selected&&num(a+12)) {
            W(DEVICE,1,SOURCE,num(a));selected=1;
            printf("SELECTION_SET bytes=%zu serial=%u\n",payload_len,num(a));fflush(stdout);
        }
    } else if(object==XDG&&op==0&&n>=4) {
        W(XDG,4,num(a));W(SURFACE,1,BUFFER,0,0);W(SURFACE,2,0,0,320,160);empty(SURFACE,6);
        if(!configured){configured=1;printf("MAPPED synthetic clipboard %s\n",source_mode?"source":"sink");fflush(stdout);}
    } else if(object==TOP&&op==1){done=1;}
    else if(object==SOURCE&&op==1) {
        int fd=take_fd();size_t offset=0;long until=milliseconds()+5000;
        while(offset<payload_len&&milliseconds()<until) {
            ssize_t count=write(fd,payload+offset,payload_len-offset);
            if(count>0){offset+=(size_t)count;continue;}
            if(count<0&&(errno==EINTR||errno==EAGAIN)){struct pollfd p={fd,POLLOUT,0};poll(&p,1,100);continue;}
            break;
        }
        close(fd);
        printf("SEND mime=%s bytes=%zu complete=%s\n",n>=4?(char*)a+4:"",offset,offset==payload_len?"yes":"no");fflush(stdout);
        if(offset!=payload_len)exit(1);
    } else if(object==SOURCE&&op==2) {
        printf("SOURCE_CANCELLED\n");fflush(stdout);
    } else if(object==DEVICE&&op==0&&n>=4) {
        if(offer_count>=128){errno=EOVERFLOW;fail("too many offers");}
        offers[offer_count++]=num(a);
    } else if(object==DEVICE&&op==5&&n>=4) {
        selection_offer=num(a);printf("SELECTION_OFFER id=%u\n",selection_offer);fflush(stdout);request_transfer();
    } else if(op==0&&n>=4) {
        int i=offer_index(object);
        if(i>=0&&num(a)<=n-4) {
            const char *mime=(char*)a+4;
            if(!strcmp(mime,"text/plain"))plain[i]=1;
            if(!strcmp(mime,"text/plain;charset=utf-8"))utf8[i]=1;
            request_transfer();
        }
    }
}
static void receive_events(int timeout) {
    struct pollfd p[2]={{connection,POLLIN,0},{transfer_fd,POLLIN|POLLHUP,0}};
    int count=poll(p,transfer_fd>=0?2:1,timeout);if(count<0&&errno!=EINTR)fail("poll");
    if(p[0].revents&POLLIN) {
        unsigned char control[CMSG_SPACE(32*sizeof(int))];
        struct iovec iov={incoming+incoming_len,sizeof(incoming)-incoming_len};
        struct msghdr msg={0};msg.msg_iov=&iov;msg.msg_iovlen=1;msg.msg_control=control;msg.msg_controllen=sizeof(control);
        ssize_t n=recvmsg(connection,&msg,0);if(n<=0)fail("recvmsg");incoming_len+=(size_t)n;
        if(msg.msg_flags&MSG_CTRUNC){errno=EOVERFLOW;fail("fd truncation");}
        for(struct cmsghdr *c=CMSG_FIRSTHDR(&msg);c;c=CMSG_NXTHDR(&msg,c))if(c->cmsg_level==SOL_SOCKET&&c->cmsg_type==SCM_RIGHTS) {
            size_t nn=(c->cmsg_len-CMSG_LEN(0))/sizeof(int);
            if(fd_count+(int)nn>64){errno=EOVERFLOW;fail("fd queue");}
            memcpy(input_fds+fd_count,CMSG_DATA(c),nn*sizeof(int));fd_count+=(int)nn;
        }
        size_t used=0;
        while(incoming_len-used>=8) {
            uint32_t h=num(incoming+used+4);size_t bytes=h>>16;
            if(bytes<8||(bytes&3)){errno=EPROTO;fail("wire size");}
            if(bytes>incoming_len-used)break;
            dispatch(num(incoming+used),(uint16_t)h,incoming+used+8,bytes-8);used+=bytes;
        }
        memmove(incoming,incoming+used,incoming_len-used);incoming_len-=used;
    }
    if(transfer_fd>=0&&p[1].revents) {
        unsigned char b[4096];
        for(;;) {
            ssize_t n=read(transfer_fd,b,sizeof(b));
            if(n>0){if(write(out_fd,b,(size_t)n)!=n)fail("write sink");transferred+=(size_t)n;continue;}
            if(n==0){printf("RECEIVED bytes=%zu\n",transferred);fflush(stdout);close(transfer_fd);transfer_fd=-1;done=1;break;}
            if(errno==EAGAIN)break;
            if(errno==EINTR)continue;
            fail("read transfer");
        }
    }
}
static void guard_socket(const char *path) {
    char marker[512];size_t n=strlen(path);if(n>=sizeof(marker)-32){errno=EINVAL;fail("socket path");}
    strcpy(marker,path);char *slash=strrchr(marker,'/');if(!slash){errno=EINVAL;fail("absolute socket required");}
    strcpy(slash+1,"address-proof-owned");
    struct stat s;if(stat(marker,&s)||s.st_uid!=getuid()||!S_ISREG(s.st_mode)){errno=EPERM;fail("not a private proof runtime");}
}
int main(int argc,char **argv) {
    if(argc!=4||(!strcmp(argv[2],"source")?0:strcmp(argv[2],"sink"))) {
        fprintf(stderr,"usage: %s PRIVATE_SOCKET source INPUT | PRIVATE_SOCKET sink OUTPUT\n",argv[0]);return 2;
    }
    setvbuf(stdout,NULL,_IOLBF,0);guard_socket(argv[1]);source_mode=!strcmp(argv[2],"source");
    if(source_mode){int fd=open(argv[3],O_RDONLY|O_CLOEXEC);if(fd<0)fail("fixture");ssize_t n=read(fd,payload,sizeof(payload));if(n<0)fail("fixture read");payload_len=(size_t)n;close(fd);}
    else {out_fd=open(argv[3],O_WRONLY|O_CREAT|O_EXCL|O_CLOEXEC,0600);if(out_fd<0)fail("sink output");}
    connection=socket(AF_UNIX,SOCK_STREAM|SOCK_CLOEXEC,0);if(connection<0)fail("socket");
    struct sockaddr_un a={.sun_family=AF_UNIX};if(strlen(argv[1])>=sizeof(a.sun_path)){errno=ENAMETOOLONG;fail("socket");}strcpy(a.sun_path,argv[1]);
    if(connect(connection,(struct sockaddr*)&a,sizeof(a)))fail("connect");
    W(DISPLAY,1,REGISTRY);W(DISPLAY,0,SYNC);
    long deadline=milliseconds()+5000;while(!got_sync&&milliseconds()<deadline)receive_events(100);
    if(!got_sync||!compositor||!shm||!wm||!seat||!manager){fprintf(stderr,"required compositor globals unavailable\n");return 1;}
    DEVICE=next_id++;W(MANAGER,1,DEVICE,SEAT);if(source_mode){SOURCE=next_id++;W(MANAGER,0,SOURCE);string_message(SOURCE,0,"text/plain;charset=utf-8");string_message(SOURCE,0,"text/plain");}
    SURFACE=next_id++;W(COMPOSITOR,0,SURFACE);XDG=next_id++;W(WM,2,XDG,SURFACE);TOP=next_id++;W(XDG,1,TOP);
    string_message(TOP,2,source_mode?"Isolated synthetic clipboard source":"Isolated clipboard sink");string_message(TOP,3,"address-proof-peer");
    W(TOP,7,320,160);W(TOP,8,320,160);
    int frame=memfd_create("address-proof-peer",MFD_CLOEXEC);if(frame<0||ftruncate(frame,320*160*4))fail("frame");
    uint32_t *pixels=mmap(NULL,320*160*4,PROT_READ|PROT_WRITE,MAP_SHARED,frame,0);if(pixels==MAP_FAILED)fail("mmap");
    for(int i=0;i<320*160;i++)pixels[i]=0xff303030u;
    POOL=next_id++;uint32_t pool_args[]={POOL,320*160*4};send_message(SHM,0,pool_args,sizeof(pool_args),frame);close(frame);
    BUFFER=next_id++;W(POOL,0,BUFFER,0,320,160,320*4,1);empty(SURFACE,6);
    deadline=milliseconds()+(source_mode?180000:15000);
    while(!done&&milliseconds()<deadline)receive_events(100);
    close(connection);if(out_fd>=0)close(out_fd);
    if(!source_mode&&!done){fprintf(stderr,"clipboard transfer timed out\n");return 1;}
    return 0;
}
