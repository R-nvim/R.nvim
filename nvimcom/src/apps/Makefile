CC ?= gcc
CFLAGS = -pthread -O2 -Wall
TARGET = rnvimserver
SRCS = complete.c resolve.c hover.c definition.c signature.c rhelp.c chunk.c data_structures.c logging.c rnvimserver.c obbr.c tcp.c utilities.c ../common.c

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $(TARGET)

clean:

