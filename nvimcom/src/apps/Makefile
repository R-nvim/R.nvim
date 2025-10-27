CC ?= gcc
# CFLAGS = -pthread -std=gnu99 -O2 -Wall
# TODO: back to above CPFLAGS
CFLAGS = -pthread -std=gnu99 -O0 -g -Wall
TARGET = rnvimserver
SRCS = complete.c rhelp.c chunk.c data_structures.c logging.c rnvimserver.c obbr.c tcp.c utilities.c ../common.c

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $(TARGET)

clean:

