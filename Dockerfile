# =============================================================================
# Stage 1: Builder
# Using Alpine to provide a clean environment with the necessary build tools.
# =============================================================================
FROM alpine:latest AS builder

# Install NASM, Make, and Binutils (required for the 'ld' linker)
RUN apk add --no-cache nasm make binutils

# Set the working directory
WORKDIR /build

# Copy all source code and the Makefile
COPY . .

# Compile the project using our Makefile (now generating 'rules-engine')
RUN make

# =============================================================================
# Stage 2: Final Production Image
# Using 'scratch' (completely empty). Zero dependencies, maximum security,
# and an ultra-minimalist footprint.
# =============================================================================
FROM scratch

# Set the working directory
WORKDIR /app

# Copy ONLY the compiled static binary from the builder stage
# Updated to point to the new 'rules-engine' binary
COPY --from=builder /build/bin/rules-engine /app/rules-engine

# Expose the HTTP router port
EXPOSE 8080

# Startup command
CMD ["/app/rules-engine"]