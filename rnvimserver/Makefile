CC ?= gcc
SRCS = complete.c resolve.c hover.c definition.c signature.c rhelp.c chunk.c roxygen.c data_structures.c logging.c rnvimserver.c obbr.c tcp.c utilities.c ../nvimcom/src/common.c

ifeq ($(OS),Windows_NT)
    TARGET = rnvimserver.exe
    CFLAGS = -mwindows -O3 -Wall -DWIN32
    LIBS = -lWs2_32
else
    TARGET = rnvimserver
    CFLAGS = -pthread -O2 -Wall
    LIBS =
endif

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $(TARGET) $(LIBS)

clean:

