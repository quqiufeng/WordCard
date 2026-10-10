CC = g++
CC_C = gcc
CFLAGS = -shared -fPIC -std=c++17 -O2 -Wall -Wextra

PKGS := opencv4
CFLAGS += $(shell pkg-config --cflags $(PKGS))
LDLIBS := $(shell pkg-config --libs $(PKGS)) -lpthread

.PHONY: all dotui wordcard wordpick txt2png automation clean

all: dotui wordpick wordcard automation

automation:
	$(CC_C) -shared -fPIC -O2 -Wall -Wextra automation/automation_ctl.c -o libwordcard_ctl.so
	@echo "  -> libwordcard_ctl.so"

wordcard:
	$(CC_C) -shared -fPIC -O2 -Wall -Wextra wordcard.c modes.c -o libwordcard.so -lpthread
	@echo "  -> libwordcard.so"

dotui:
	$(CC) $(CFLAGS) dotui_bridge.cpp -o libdotui.so $(LDLIBS)
	@echo "  -> libdotui.so"

txt2png:
	$(CC) $(CFLAGS) $(shell pkg-config --cflags freetype2) txt2png/txt2png_bridge.cpp -o libtxt2png.so $(LDLIBS) -lharfbuzz -lcairo $(shell pkg-config --libs freetype2) $(shell pkg-config --libs icu-i18n icu-uc) -lhyphen
	@echo "  -> libtxt2png.so"

wordpick:
	$(CC) $(CFLAGS) wordpick/wordpick.cpp -o libwordpick.so
	@echo "  -> libwordpick.so"

clean:
	rm -f libdotui.so libtxt2png.so libwordpick.so libwordcard.so libwordcard_ctl.so *.o
