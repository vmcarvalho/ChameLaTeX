# Simple Makefile wrapper for build.sh
.PHONY: all build clean help

# Default target
all: build

# Build all CV versions using the shell script
build:
	@chmod +x build.sh
	@./build.sh build

# Clean using the shell script
clean:
	@./build.sh clean

# Show help
help:
	@./build.sh help