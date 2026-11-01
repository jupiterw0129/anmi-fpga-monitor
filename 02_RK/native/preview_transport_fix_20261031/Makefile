CC ?= gcc
CFLAGS ?= -O2 -march=armv8-a+crc -Wall -Wextra -Werror -pthread
LDLIBS = -ljpeg -Wl,-l:libcrypto.so.3

all: publish_preview

publish_preview: publish_live1585.c publish_jpg1585.c receiver_jpg735.c record_writer1326.h wire_writer1299.h feedback1585.h
	$(CC) $(CFLAGS) -o $@ publish_live1585.c $(LDLIBS)
