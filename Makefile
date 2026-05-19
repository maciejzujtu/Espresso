# It is important to note that this is a
# Makefile made strictly for Darwin OS therefore
# using it on other OS will result in a failure

ASM	= as	# assembler
LD	= ld	# linker

SDK_PATH = $(shell xcrun -sdk macosx --show-sdk-path) 
LDFLAGS = -lSystem -syslibroot $(SDK_PATH) -arch arm64
LDFLAGS_MAIN = -lSystem -syslibroot $(SDK_PATH) -e _main -arch arm64

BUILD = build

MAIN_OBJS = build/main.o build/alloc.o build/parser.o build/build.o build/minimize.o

all: main

main: $(MAIN_OBJS)
	$(LD) -o $@ $^ $(LDFLAGS_MAIN)

build/%.o: src/%.s
	@mkdir -p build
	$(ASM) -o $@ $<

single: build/$(FILE).o
	$(LD) -o $(FILE) build/$(FILE).o $(LDFLAGS)

clean:
	rm -rf build/*.o main
