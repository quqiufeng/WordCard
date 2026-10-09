CC = g++
CFLAGS = -shared -fPIC -std=c++17 -O2 -Wall -Wextra

PKGS := opencv4
CFLAGS += $(shell pkg-config --cflags $(PKGS))
LDLIBS := $(shell pkg-config --libs $(PKGS)) -lpthread

.PHONY: all dotui wordpick txt2png clean

all: dotui wordpick

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
	rm -f libdotui.so libtxt2png.so libwordpick.so
