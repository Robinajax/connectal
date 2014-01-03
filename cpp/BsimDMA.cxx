#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <assert.h>
#include <stdio.h>
#include <sys/mman.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>

#include <portal.h>

#include "sock_fd.h"
#include "sock_utils.h"

static struct portal p_fd = iport;
static int fd[16];
static unsigned char *buffer[16];
static unsigned long buffer_len[16];

extern "C" {

  void init_pareff(){

    pthread_t tid;

    struct channel* rc;
    struct channel* wc;

    fprintf(stderr, "BsimDMA::init_pareff()\n");

    rc = &(p_fd.read);
    snprintf(rc->path, sizeof(rc->path), "fd_sock_rc");

    wc = &(p_fd.write);
    snprintf(wc->path, sizeof(wc->path), "fd_sock_wc");

    if(pthread_create(&tid, NULL,  init_socket, (void*)rc)){
      fprintf(stderr, "error creating init thread\n");
      //exit(1);
    }

    if(pthread_create(&tid, NULL,  init_socket, (void*)wc)){
      fprintf(stderr, "error creating init thread\n");
      //exit(1);
    }

  }

  void write_pareff32(unsigned long pref, unsigned long offset, unsigned int data){
    if(buffer_len[pref-1] <= offset)
      fprintf(stderr, "write_pareff(pref=%08lx, offset=%08lx) going off the reservation \n", pref, offset);
    *(unsigned int *)&buffer[pref-1][offset] = data;
  }

  unsigned int read_pareff32(unsigned long pref, unsigned long offset){
    if(buffer_len[pref-1] <= offset)
      fprintf(stderr, "read_pareff(pref=%08lx, offset=%08lx) going off the reservation \n", pref, offset);
    return *(unsigned int *)&buffer[pref-1][offset];
  }

  void write_pareff64(unsigned long pref, unsigned long offset, unsigned long long data){
    if(buffer_len[pref-1] <= offset)
      fprintf(stderr, "write_pareff(pref=%08lx, offset=%08lx) going off the reservation \n", pref, offset);
    *(unsigned long long *)&buffer[pref-1][offset] = data;
  }

  unsigned long long read_pareff64(unsigned long pref, unsigned long offset){
    if(buffer_len[pref-1] <= offset)
      fprintf(stderr, "read_pareff(pref=%08lx, offset=%08lx) going off the reservation \n", pref, offset);
    return *(unsigned long long *)&buffer[pref-1][offset];
  }

  void pareff(unsigned long pref, unsigned long size){
    assert(pref < 16);
    sock_fd_read(p_fd.write.s2, &(fd[pref-1]));
    buffer[pref-1] = (unsigned char *)mmap(0, size, PROT_WRITE|PROT_WRITE|PROT_EXEC, MAP_SHARED, fd[pref-1], 0);
    //fprintf(stderr, "BsimDMA::pareff pref=%ld, buffer=%08lx\n", pref, buffer[pref]);
    buffer_len[pref-1] = size/sizeof(unsigned char);
  }

}
