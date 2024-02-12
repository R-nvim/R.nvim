CC ?= gcc
CFLAGS = -pthread -std=gnu99 -O2 -Wall
TARGET = rnvimserver
SRCS = rnvimserver.c utilities.c data_structures.c logging.c

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $(TARGET)

clean:

