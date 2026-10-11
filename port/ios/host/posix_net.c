/* Darwin implementation of the socket helpers the POSIX port declares. */
/* Adapt Linux socket helpers to Darwin's sockaddr length byte and socket flags. */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <pthread.h>
#include <unistd.h>

#include "host.h"

#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 0x80000
#endif
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif
static struct sockaddr_storage sockaddr_inward(const void *input,socklen_t size) {
    struct sockaddr_storage address={0};
    if(size>sizeof(address))size=sizeof(address);
    if(input && size>=2){memcpy(&address,input,size);uint16_t family;memcpy(&family,input,2);address.ss_len=size;address.ss_family=family;}
    return address;
}
static void sockaddr_outward(void *address,socklen_t size) {
    if(address && size>=2){uint16_t family=((struct sockaddr *)address)->sa_family;memcpy(address,&family,2);}
}
/* iOS defuncts the sockets of an app it suspends: the descriptors stay,
but every operation on them fails (a datagram socket's receive with
ENOTCONN, and poll calls it readable). The game's own sockets (the server
browser's search, a hosted game's) and internet play's tunnel and stand-ins
outlive the background, so a datagram socket found defunct is made again in
place: a new socket with the options set on the old one, at the same
descriptor (dup2 closes the old one, releasing its port, with no moment in
which another thread could take the number), bound to the old address. A
stream's connection is lost with its socket, as any lost connection is. */
enum {REVIVABLE_DESCRIPTORS=1024,REVIVABLE_OPTIONS=8};
struct revivable {
    int datagram,protocol,bound,option_count;
    struct sockaddr_in address;
    struct {int level,name,value;} options[REVIVABLE_OPTIONS];
};
static struct revivable revivables[REVIVABLE_DESCRIPTORS];
static pthread_mutex_t revivable_lock=PTHREAD_MUTEX_INITIALIZER;
static int revivable_index(int fd) {return fd>=0 && fd<REVIVABLE_DESCRIPTORS;}
/* 1 if fd was a defunct datagram socket, now made again (the failed call
may be tried again); 0 if it is not one */
static int revive_datagram(int fd) {
    struct revivable entry;char byte;int fresh,flags,index,one=1;
    if(!revivable_index(fd))return 0;
    pthread_mutex_lock(&revivable_lock);
    entry=revivables[fd];
    /* (another thread may have revived it since its own call failed) */
    if(!entry.datagram || recv(fd,&byte,1,MSG_PEEK|MSG_DONTWAIT)>=0 || errno!=ENOTCONN) {
        pthread_mutex_unlock(&revivable_lock);return entry.datagram;
    }
    flags=fcntl(fd,F_GETFL);
    fresh=socket(AF_INET,SOCK_DGRAM,entry.protocol);
    if(fresh<0 || dup2(fresh,fd)<0) {
        int error=errno;if(fresh>=0)close(fresh);
        pthread_mutex_unlock(&revivable_lock);
        host_logf(HOST_LOG_ERROR,"socket %d was reclaimed in the background and cannot be made again: %s",fd,strerror(error));
        errno=ENOTCONN;return 0;
    }
    close(fresh);
    fcntl(fd,F_SETFD,FD_CLOEXEC);
    if(flags>=0)fcntl(fd,F_SETFL,flags);
    setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
    for(index=0;index<entry.option_count;index++)
        setsockopt(fd,entry.options[index].level,entry.options[index].name,&entry.options[index].value,sizeof(int));
    if(entry.bound && bind(fd,(struct sockaddr *)&entry.address,sizeof(entry.address))<0)
        host_logf(HOST_LOG_ERROR,"socket %d made again after the background cannot take port %u again: %s",
            fd,ntohs(entry.address.sin_port),strerror(errno));
    else
        host_logf(HOST_LOG_INFO,"socket %d (UDP port %u) was reclaimed in the background; made again",
            fd,ntohs(entry.address.sin_port));
    pthread_mutex_unlock(&revivable_lock);
    return 1;
}
static int ios_socket(int family,int type,int protocol) {
    int fd=socket(family,type&~SOCK_CLOEXEC,protocol);
    if(fd>=0){int one=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));fcntl(fd,F_SETFD,FD_CLOEXEC);}
    if(revivable_index(fd)) {
        pthread_mutex_lock(&revivable_lock);
        memset(&revivables[fd],0,sizeof(revivables[fd]));
        revivables[fd].datagram=family==AF_INET && (type&~SOCK_CLOEXEC)==SOCK_DGRAM;
        revivables[fd].protocol=protocol;
        pthread_mutex_unlock(&revivable_lock);
    }
    return fd;
}
static int ios_close(int fd) {
    if(revivable_index(fd)){pthread_mutex_lock(&revivable_lock);revivables[fd].datagram=0;pthread_mutex_unlock(&revivable_lock);}
    return close(fd);
}
/* the address a datagram socket has (with the port the system chose, for
one bound to port 0 or by its first send), to bind its revival to */
static void remember_address(int fd) {
    struct sockaddr_in address;socklen_t length=sizeof(address);
    if(!revivable_index(fd) || getsockname(fd,(struct sockaddr *)&address,&length) || address.sin_family!=AF_INET)return;
    pthread_mutex_lock(&revivable_lock);
    if(revivables[fd].datagram){revivables[fd].address=address;revivables[fd].bound=1;}
    pthread_mutex_unlock(&revivable_lock);
}
static int ios_bind(int fd,const void *p,socklen_t n) {
    struct sockaddr_storage a=sockaddr_inward(p,n);int r=bind(fd,(struct sockaddr *)&a,n);
    if(!r)remember_address(fd);
    return r;
}
static int ios_setsockopt(int fd,int level,int name,const void *value,socklen_t size) {
    int r=setsockopt(fd,level,name,value,size);
    if(!r && size==sizeof(int) && revivable_index(fd)) {
        struct revivable *entry=&revivables[fd];int index;
        pthread_mutex_lock(&revivable_lock);
        for(index=0;index<entry->option_count && (entry->options[index].level!=level || entry->options[index].name!=name);index++);
        if(entry->datagram && index<REVIVABLE_OPTIONS) {
            entry->options[index].level=level;entry->options[index].name=name;memcpy(&entry->options[index].value,value,sizeof(int));
            if(index==entry->option_count)entry->option_count++;
        }
        pthread_mutex_unlock(&revivable_lock);
    }
    return r;
}
static int ios_connect(int fd,const void *p,socklen_t n) {struct sockaddr_storage a=sockaddr_inward(p,n);return connect(fd,(struct sockaddr *)&a,n);}
static int ios_accept4(int fd,void *p,socklen_t *n,int flags) {
    (void)flags;int out=accept(fd,p,n);if(out>=0){fcntl(out,F_SETFD,FD_CLOEXEC);if(n)sockaddr_outward(p,*n);}return out;
}
static ssize_t ios_sendto(int fd,const void *p,size_t n,int flags,const void *address,socklen_t size) {
    struct sockaddr_storage a=sockaddr_inward(address,size);
    ssize_t out=sendto(fd,p,n,flags,(struct sockaddr *)&a,size);
    if(out<0 && (errno==ENOTCONN || errno==EPIPE) && revive_datagram(fd))out=sendto(fd,p,n,flags,(struct sockaddr *)&a,size);
    /* (a socket the send bound: its port, read once) */
    if(out>=0 && revivable_index(fd) && revivables[fd].datagram && !revivables[fd].bound)remember_address(fd);
    return out;
}
static ssize_t ios_recvfrom(int fd,void *p,size_t n,int flags,void *address,socklen_t *size) {
    ssize_t out=recvfrom(fd,p,n,flags,address,size);if(out>=0 && size)sockaddr_outward(address,*size);return out;
}
/* The shared helper uses recvmsg to detect truncated datagrams, not recvfrom. */
static ssize_t ios_recvmsg(int fd,struct msghdr *message,int flags) {
    socklen_t capacity=message->msg_namelen;
    ssize_t result=recvmsg(fd,message,flags);
    if(result<0 && errno==ENOTCONN && revive_datagram(fd)){message->msg_namelen=capacity;result=recvmsg(fd,message,flags);}
    if(result>=0)sockaddr_outward(message->msg_name,message->msg_namelen);
    return result;
}
static int ios_getsockname(int fd,void *p,socklen_t *n) {int r=getsockname(fd,p,n);if(!r)sockaddr_outward(p,*n);return r;}
static int ios_getpeername(int fd,void *p,socklen_t *n) {int r=getpeername(fd,p,n);if(!r)sockaddr_outward(p,*n);return r;}
static ssize_t ios_getrandom(void *p,size_t size,unsigned flags) {(void)flags;arc4random_buf(p,size);return size;}
#define socket ios_socket
#define close ios_close
#define bind ios_bind
#define setsockopt ios_setsockopt
#define connect ios_connect
#define accept4 ios_accept4
#define sendto ios_sendto
#define recvfrom ios_recvfrom
#define recvmsg ios_recvmsg
#define getsockname ios_getsockname
#define getpeername ios_getpeername
#define getrandom ios_getrandom
#include "../../linux/src/posix_net.c"

/* Native clients use upstream STUN/hole punching. Router forwarding is not enabled. */
int posix_upnp_forward_udp(unsigned short port, unsigned short preferred_port,
    posix_ulong *address, unsigned short *external_port, char *error, int error_size)
{
    (void)port; (void)preferred_port;
    if (address) *address = 0;
    if (external_port) *external_port = 0;
    if (error && error_size > 0) snprintf(error, (size_t)error_size, "Router port forwarding is unavailable on this Apple build");
    return 0;
}
void posix_upnp_stop_forwarding_udp(unsigned short port) { (void)port; }
