/* XTest input for an owned Xvfb/Weston test session. It deliberately injects
 * at the compositor's X11 backend, never directly into the browser. */
#define _GNU_SOURCE
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

typedef struct _XDisplay Display;
typedef unsigned long Window;
extern Display *XOpenDisplay(const char *);
extern int XCloseDisplay(Display *);
extern Window XDefaultRootWindow(Display *);
extern int XQueryTree(Display *,Window,Window *,Window *,Window **,unsigned int *);
extern int XFetchName(Display *,Window,char **);
extern int XFree(void *);
extern int XSetInputFocus(Display *,Window,int,unsigned long);
extern int XRaiseWindow(Display *,Window);
extern int XSync(Display *,int);
extern int XTestFakeKeyEvent(Display *,unsigned int,int,unsigned long);
extern int XTestFakeButtonEvent(Display *,unsigned int,int,unsigned long);
extern int XTestFakeMotionEvent(Display *,int,int,int,unsigned long);

static Display *display;
static void fail(const char *s){perror(s);exit(1);}
static void pause_ms(unsigned long n) {struct timespec t={(time_t)(n/1000),(long)((n%1000)*1000000)};while(nanosleep(&t,&t)&&errno==EINTR){}}
static void key(unsigned int evdev,int down) {
    if(!XTestFakeKeyEvent(display,evdev+8,down,0)){fprintf(stderr,"XTest key failed\n");exit(1);}
    XSync(display,0);
}
static void tap(unsigned int evdev){key(evdev,1);pause_ms(12);key(evdev,0);pause_ms(12);}
static void ascii(char c) {
    const char *base="1234567890-=qwertyuiop[]asdfghjkl;'\x60\\zxcvbnm,./";
    const unsigned int codes[]={2,3,4,5,6,7,8,9,10,11,12,13,16,17,18,19,20,21,22,23,24,25,26,27,30,31,32,33,34,35,36,37,38,39,40,41,43,44,45,46,47,48,49,50,51,52,53};
    const char *shifted="!@#$%^&*()_+QWERTYUIOP{}ASDFGHJKL:\"~|ZXCVBNM<>?";
    if(c==' '){tap(57);return;}
    const char *p=strchr(base,c);if(p){tap(codes[p-base]);return;}
    p=strchr(shifted,c);if(p){key(42,1);tap(codes[p-shifted]);key(42,0);return;}
    fprintf(stderr,"text supports printable ASCII only, got 0x%02x\n",(unsigned char)c);exit(1);
}
static void focus(void) {
    Window root=XDefaultRootWindow(display),r,parent,*children=NULL;unsigned int count=0;
    if(!XQueryTree(display,root,&r,&parent,&children,&count))fail("XQueryTree");
    Window found=0;
    for(unsigned int i=0;i<count;i++) {
        char *name=NULL;XFetchName(display,children[i],&name);
        if(name){if(strstr(name,"Weston"))found=children[i];XFree(name);}
    }
    if(!found&&count==1)found=children[0];
    if(children)XFree(children);
    if(!found){fprintf(stderr,"no isolated Weston X11 window\n");exit(1);}
    XRaiseWindow(display,found);XSetInputFocus(display,found,2,0);XSync(display,0);
    printf("FOCUS Weston X11 window=%lu\n",found);
}
int main(int argc,char **argv) {
    const char *runtime=getenv("XDG_RUNTIME_DIR");char marker[1024];struct stat s;
    if(!runtime||snprintf(marker,sizeof(marker),"%s/address-proof-owned",runtime)>=(int)sizeof(marker)||stat(marker,&s)||s.st_uid!=getuid()) {
        fprintf(stderr,"requires owned address-proof runtime marker\n");return 2;
    }
    display=XOpenDisplay(NULL);if(!display)fail("XOpenDisplay");setvbuf(stdout,NULL,_IOLBF,0);
    FILE *input=stdin;if(argc==2){input=fopen(argv[1],"r");if(!input)fail("input script");}
    if(argc>2){fprintf(stderr,"usage: %s [SCRIPT]\n",argv[0]);return 2;}
    char line[4096];
    while(fgets(line,sizeof(line),input)) {
        line[strcspn(line,"\r\n")]=0;if(!line[0]||line[0]=='#')continue;
        printf("INPUT %s\n",line);
        unsigned int code,down;int x,y;unsigned long wait;
        if(!strcmp(line,"focus"))focus();
        else if(sscanf(line,"key %u %u",&code,&down)==2){key(code,!!down);}
        else if(sscanf(line,"tap %u",&code)==1){tap(code);}
        else if(sscanf(line,"wait %lu",&wait)==1){if(wait>10000){fprintf(stderr,"wait too long\n");return 2;}pause_ms(wait);}
        else if(sscanf(line,"move %d %d",&x,&y)==2){XTestFakeMotionEvent(display,-1,x,y,0);XSync(display,0);pause_ms(25);}
        else if(sscanf(line,"button %u %u",&code,&down)==2){XTestFakeButtonEvent(display,code,!!down,0);XSync(display,0);pause_ms(25);}
        else if(!strncmp(line,"text ",5)){for(char *p=line+5;*p;p++)ascii(*p);}
        else {fprintf(stderr,"unknown input command: %s\n",line);return 2;}
    }
    if(input!=stdin)fclose(input);
    XCloseDisplay(display);return 0;
}
