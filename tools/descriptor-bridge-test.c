/* Independent Linux descriptor-bridge test. Every byte and descriptor is synthetic. */
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <sys/wait.h>
#include <unistd.h>

static unsigned char record[65536], bytes[1048592];
static int client, wire;
static unsigned char auth_key[32];
static void exact_read(int fd, void *p, size_t n) {
    unsigned char *at=p;
    while(n) { ssize_t r=read(fd,at,n); if(r<0 && errno==EINTR) continue; assert(r>0);at+=r;n-=r; }
}
static void exact_write(int fd,const void *p,size_t n) {
    const unsigned char *at=p;
    while(n) { ssize_t r=write(fd,at,n); if(r<0 && errno==EINTR) continue; assert(r>0);at+=r;n-=r; }
}
static int tcp_connect(const struct sockaddr_in *dest) {
    int fd=socket(AF_INET,SOCK_STREAM|SOCK_CLOEXEC,0);assert(fd>=0);
    assert(connect(fd,(const void*)dest,sizeof(*dest))==0);return fd;
}
static void rejected_candidate(const struct sockaddr_in *dest,int unix_listener,int mode) {
    int fd=tcp_connect(dest);unsigned char wrong[32]={0};
    if(mode==0) exact_write(fd,wrong,sizeof(wrong));
    else if(mode==1) {exact_write(fd,auth_key,7);assert(shutdown(fd,SHUT_WR)==0);}
    struct pollfd candidate={.fd=fd,.events=POLLIN};
    assert(poll(&candidate,1,1000)>0);
    unsigned char byte;ssize_t n=read(fd,&byte,1);assert(n==0 || (n<0 && errno==ECONNRESET));
    close(fd);
    struct pollfd compositor={.fd=unix_listener,.events=POLLIN};
    assert(poll(&compositor,1,0)==0);
}
static uint32_t num(const void *p) { uint32_t n;memcpy(&n,p,4);return n; }
static void command(uint32_t op,const void *p,uint32_t n) {
    uint32_t h[2]={n,op};exact_write(client,h,8);exact_write(client,p,n);
}
static uint32_t receive(size_t *length) {
    uint32_t h[2];exact_read(client,h,8);assert(h[0]==0);
    *length=(h[1]>>16)-8;assert(*length<sizeof(record));exact_read(client,record,*length);
    return h[1]&65535;
}
static void send_fd(const void *p,size_t n,int fd) {
    struct iovec iov={(void*)p,n};
    char control[CMSG_SPACE(sizeof(int))]={0};
    struct msghdr msg={.msg_iov=&iov,.msg_iovlen=1,.msg_control=control,.msg_controllen=sizeof(control)};
    struct cmsghdr *c=CMSG_FIRSTHDR(&msg);c->cmsg_len=CMSG_LEN(sizeof(int));c->cmsg_level=SOL_SOCKET;c->cmsg_type=SCM_RIGHTS;
    memcpy(CMSG_DATA(c),&fd,sizeof(fd));assert(sendmsg(wire,&msg,0)==(ssize_t)n);
}
static int receive_fd(const void *expected,size_t n) {
    unsigned char data[64];char control[CMSG_SPACE(sizeof(int))];
    struct iovec iov={data,sizeof(data)};
    struct msghdr msg={.msg_iov=&iov,.msg_iovlen=1,.msg_control=control,.msg_controllen=sizeof(control)};
    ssize_t r=recvmsg(wire,&msg,0);assert(r==(ssize_t)n && !memcmp(data,expected,n));
    struct cmsghdr *c=CMSG_FIRSTHDR(&msg);assert(c && c->cmsg_level==SOL_SOCKET && c->cmsg_type==SCM_RIGHTS);
    int fd;memcpy(&fd,CMSG_DATA(c),sizeof(fd));return fd;
}
static uint32_t descriptor_token(const unsigned char *expected,size_t n,int fd) {
    send_fd(expected,n,fd);
    size_t size;assert(receive(&size)==4);assert(num(record)==n && num(record+4)==1);
    assert(!memcmp(record+12,expected,n));return num(record+8);
}
static void pipe_transfer(size_t count,int should_fail) {
    uint32_t token=0x80000010U+(uint32_t)should_fail;
    unsigned char request[7]={4,3,2,1,255,0,127};
    memcpy(bytes,&token,4);memcpy(bytes+4,request,sizeof(request));command(2,bytes,4+sizeof(request));
    int fd=receive_fd(request,sizeof(request));
    pid_t writer=fork();assert(writer>=0);
    if(!writer) {
        close(client);close(wire);
        unsigned char *chunk=malloc(count);assert(chunk);for(size_t i=0;i<count;i++)chunk[i]=(unsigned char)(i%251);
        size_t at=0;
        while(at<count) {
            size_t wanted=count-at;if(wanted>8192)wanted=8192;
            ssize_t r=write(fd,chunk+at,wanted);if(r<0 && errno==EINTR)continue;if(r<0 && errno==EPIPE)_exit(0);
            assert(r>0);at+=r;
        }
        close(fd);_exit(0);
    }
    close(fd);
    size_t total=0;int finished=0;
    while(!finished) {
        size_t size;uint32_t kind=receive(&size);assert(num(record)==token);
        if(kind==1) {
            size_t n=num(record+4);assert(n<=8192 && size>=n+8);
            for(size_t i=0;i<n;i++) { assert(record[8+i]==(unsigned char)((total+i)%251)); }
            total+=n;
        } else {
            assert(kind==2 && size==8);
            assert(num(record+4)==(uint32_t)(should_fail ? 2 : 0));finished=1;
        }
    }
    assert(should_fail ? total<=1048576 : total==count);
    int status;waitpid(writer,&status,0);assert(WIFEXITED(status) && WEXITSTATUS(status)==0);
}
int main(int argc,char **argv) {
    assert(argc==2);alarm(20);signal(SIGPIPE,SIG_IGN);
    char temp[]="target/descriptor-bridge.XXXXXX";assert(mkdtemp(temp));
    char socket_path[108],frame_path[160];
    snprintf(socket_path,sizeof(socket_path),"%s/socket",temp);snprintf(frame_path,sizeof(frame_path),"%s/frame",temp);
    int frame=open(frame_path,O_CREAT|O_RDWR|O_CLOEXEC,0600);assert(frame>=0);exact_write(frame,"frame",5);
    int listener=socket(AF_UNIX,SOCK_STREAM|SOCK_CLOEXEC,0);assert(listener>=0);
    struct sockaddr_un address={.sun_family=AF_UNIX};strcpy(address.sun_path,socket_path);
    assert(bind(listener,(void*)&address,sizeof(address))==0);assert(listen(listener,1)==0);
    int output[2];assert(pipe(output)==0);
    int auth[2];assert(pipe(auth)==0);
    for(size_t i=0;i<sizeof(auth_key);i++)auth_key[i]=(unsigned char)(i*17+3);
    exact_write(auth[1],auth_key,sizeof(auth_key));close(auth[1]);
    pid_t bridge=fork();assert(bridge>=0);
    if(!bridge) {
        close(output[0]);assert(dup2(output[1],STDOUT_FILENO)>=0);close(output[1]);
        assert(dup2(auth[0],STDIN_FILENO)>=0);close(auth[0]);
        execl(argv[1],argv[1],socket_path,frame_path,(char*)0);_exit(127);
    }
    close(output[1]);close(auth[0]);
    char port_text[16];size_t pos=0;do {exact_read(output[0],port_text+pos,1);assert(pos<sizeof(port_text)-1);}while(port_text[pos++]!='\n');
    close(output[0]);port_text[pos]=0;
    struct sockaddr_in dest={.sin_family=AF_INET,.sin_port=htons((uint16_t)atoi(port_text)),.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
    struct pollfd untouched={.fd=listener,.events=POLLIN};
    assert(poll(&untouched,1,0)==0);
    rejected_candidate(&dest,listener,0); /* Incorrect full key. */
    rejected_candidate(&dest,listener,1); /* Correct prefix, then EOF. */
    rejected_candidate(&dest,listener,2); /* No bytes, total deadline. */
    client=tcp_connect(&dest);exact_write(client,auth_key,sizeof(auth_key));
    wire=accept4(listener,NULL,NULL,SOCK_CLOEXEC);assert(wire>=0);close(listener);
    size_t n;assert(receive(&n)==3 && n==4 && num(record)==1);

    /* A frame descriptor is still the original backing inode. */
    const unsigned char opaque[8]={0,255,2,3,4,5,0,7};
    command(1,opaque,8);int passed=receive_fd(opaque,8);
    struct stat a,b;assert(fstat(frame,&a)==0 && fstat(passed,&b)==0);assert(a.st_ino==b.st_ino && a.st_dev==b.st_dev);close(passed);
    command(0,opaque,8);exact_read(wire,bytes,8);assert(!memcmp(bytes,opaque,8));

    /* Arbitrary partial bytes survive before the read carrying an ancillary FD. */
    exact_write(wire,opaque,3);assert(receive(&n)==4 && num(record)==3 && num(record+4)==0);assert(!memcmp(record+8,opaque,3));
    int pair[2];assert(pipe(pair)==0);
    uint32_t token=descriptor_token(opaque+3,5,pair[1]);assert(token);close(pair[1]);
    memcpy(bytes,&token,4);
    const size_t written=65536;
    for(size_t i=0;i<written;i++)bytes[4+i]=(unsigned char)(i%251);
    command(3,bytes,4+written);
    unsigned char incoming[65536];exact_read(pair[0],incoming,sizeof(incoming));
    for(size_t i=0;i<written;i++)assert(incoming[i]==(unsigned char)(i%251));
    assert(read(pair[0],incoming,1)==0);close(pair[0]);

    assert(pipe(pair)==0);token=descriptor_token(opaque,8,pair[1]);close(pair[1]);
    command(4,&token,4);assert(read(pair[0],incoming,1)==0);close(pair[0]);

    pipe_transfer(65536,0);
    pipe_transfer(1048577,1);
    /* An EPIPE from an outgoing descriptor must not kill the transport. */
    assert(pipe(pair)==0);token=descriptor_token(opaque,8,pair[1]);close(pair[1]);close(pair[0]);
    memcpy(bytes,&token,4);memcpy(bytes+4,opaque,8);command(3,bytes,12);
    command(0,opaque,8);exact_read(wire,bytes,8);assert(!memcmp(bytes,opaque,8));

    close(client);close(wire);close(frame);kill(bridge,SIGTERM);waitpid(bridge,NULL,0);
    unlink(socket_path);unlink(frame_path);rmdir(temp);
    puts("PASS descriptor bridge: wrong/short/stalled authentication refused before Unix connect, same-listener recovery, opaque fragmentation, frame FD, received FD write/close, pipe transfer, oversize rejection and broken-pipe survival");
    return 0;
}
