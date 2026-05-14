CC = gcc
CFLAGS = -Wall -Wextra -O2 -fPIC -std=c11 -D_GNU_SOURCE
LDFLAGS = -shared -lpthread

TARGET = libwordcard.so
OBJS = wordcard.o modes.o

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c wordcard.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)

test: $(TARGET) test_sm2.c
	$(CC) $(CFLAGS) test_sm2.c -L. -lwordcard -o test_sm2
	LD_LIBRARY_PATH=. ./test_sm2

.PHONY: all clean test
