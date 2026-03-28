# =============================================================================
# Makefile for La Roca Rules Engine
# Toolchain: NASM + LD (x86_64)
# Architecture: Modular (Net, Compiler, Engine, ALU, Utils)
# =============================================================================

# Tools
ASM = nasm
LD = ld

# Flags
# -f elf64: Generate 64-bit ELF object files
# -g: Include debug symbols
ASMFLAGS = -f elf64 -g
LDFLAGS = -m elf_x86_64 -static

# Directories
SRC_DIR = src
NET_DIR = src/net
COMPILER_DIR = src/compiler
ENGINE_DIR = src/engine
ALU_DIR = src/alu
UTILS_DIR = src/utils
BUILD_DIR = build
BIN_DIR = bin

# Target Executable
TARGET = $(BIN_DIR)/rules-engine

# Find all .asm files in the source directories
SOURCES = $(wildcard $(SRC_DIR)/*.asm) \
          $(wildcard $(NET_DIR)/*.asm) \
          $(wildcard $(COMPILER_DIR)/*.asm) \
          $(wildcard $(ENGINE_DIR)/*.asm) \
          $(wildcard $(ALU_DIR)/*.asm) \
          $(wildcard $(UTILS_DIR)/*.asm)

# Generate a list of .o files in the build directory based on source filenames
OBJECTS = $(patsubst %.asm, $(BUILD_DIR)/%.o, $(notdir $(SOURCES)))

# VPATH allows make to find dependencies across multiple source directories
VPATH = $(SRC_DIR):$(NET_DIR):$(COMPILER_DIR):$(ENGINE_DIR):$(ALU_DIR):$(UTILS_DIR)

# Default target
all: dirs $(TARGET)

# Create build and bin directories if they don't exist
dirs:
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(BIN_DIR)

# Linking stage: Combines object files into the final executable
$(TARGET): $(OBJECTS)
	$(LD) $(LDFLAGS) -o $@ $^
	@echo "---------------------------------------------------------"
	@echo "✅ Build complete! Executable is at: $(TARGET)"
	@echo "---------------------------------------------------------"

# Assembly stage: Compiles .asm source files into .o object files
# -i flags allow the compiler to resolve 'extern' and includes globally
$(BUILD_DIR)/%.o: %.asm
	$(ASM) $(ASMFLAGS) -i $(SRC_DIR)/ -i $(NET_DIR)/ -i $(COMPILER_DIR)/ -i $(ENGINE_DIR)/ -i $(ALU_DIR)/ -i $(UTILS_DIR)/ -o $@ $<

# Clean up build artifacts and binaries
clean:
	@rm -rf $(BUILD_DIR) $(BIN_DIR)
	@echo "🧹 Cleaned build/ and bin/ directories."

# Build and run the engine locally
run: all
	./$(TARGET)

.PHONY: all dirs clean run