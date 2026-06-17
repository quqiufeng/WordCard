CC = gcc
CFLAGS = -Wall -Wextra -O2 -fPIC -std=c11 -D_GNU_SOURCE -I../src -I/usr/local/include/luajit-2.1
LDFLAGS = -shared -lluajit-5.1 -ldl -lpthread -lm

TARGET = libwordcard_gui_cbridge.so

SRCS = cbridge/gui_tick.c cbridge/lua_engine.c
OBJS = $(SRCS:.c=.o)

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^ -L../src -lwordcard -lcache -Wl,-rpath,../src

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)
