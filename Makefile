# It is important to note that this is a
# Makefile made strictly for Darwin OS therefore
# using it on other OS will result in a failure

ASM	= as	# assembler
LD	= ld	# linker

SDK_PATH = $(shell xcrun -sdk macosx --show-sdk-path) 
LDFLAGS = -lSystem -syslibroot $(SDK_PATH) -e _main -arch arm64

TARGET = main
BUILD = build

SRCS = $(wildcard src/*.s)
OBJS = $(patsubst src/%.s, build/%.o, $(SRCS))

all: $(TARGET)

$(TARGET): $(OBJS)
	$(LD) -o $@ $^ $(LDFLAGS)


build/%.o: src/%.s
	@mkdir -p build
	$(ASM) -o $@ $<

clean:
	rm -rf build/*.o $(TARGET)