CC ?= gcc
CFLAGS = -pthread -std=gnu99 -O2 -Wall
TARGET = rnvimserver
SRCS = complete.c data_structures.c logging.c rnvimserver.c obbr.c tcp.c utilities.c ../common.c

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $(TARGET)

clean:

