CC = g++
CFLAGS = -shared -fPIC -std=c++17 -O2 -Wall -Wextra
OUT = libs

ONNX_INC = /data/venv/onnxruntime-linux-x64-gpu-1.26.0/include
ONNX_LIB = /data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib/libonnxruntime.so
LLAMA_INC = /opt/llama.cpp/include
GGML_INC = /opt/llama.cpp/ggml/include
LLAMA_LIB = /opt/llama.cpp/build/bin/libllama.so.0

.PHONY: all qwen3_asr voice_engine clean

all: qwen3_asr voice_engine

qwen3_asr:
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) \
	  -I$(ONNX_INC) -I$(LLAMA_INC) -I$(GGML_INC) \
	  wrappers/qwen3_asr_bridge.cpp \
	  /opt/friday/agent/qwen3_asr_engine.cpp \
	  $(ONNX_LIB) \
	  -L/opt/llama.cpp/build/bin -lllama \
	  -lpthread -ldl -lm \
	  -o $(OUT)/libqwen3_asr.so
	@echo "  -> $(OUT)/libqwen3_asr.so"

voice_engine:
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) \
	  wrappers/voice_engine.cpp \
	  -lasound -lpthread \
	  -o $(OUT)/libvoice_engine.so
	@echo "  -> $(OUT)/libvoice_engine.so"

clean:
	rm -f $(OUT)/libqwen3_asr.so $(OUT)/libvoice_engine.so
