#!/bin/bash
set -e

# Add cargo and rustup to PATH
export PATH="$HOME/.cargo/bin:$PATH"

echo "=== 1. Adding Windows target ==="
rustup target add x86_64-pc-windows-msvc

echo "=== 2. Installing cargo-xwin ==="
if ! command -v cargo-xwin &> /dev/null; then
    cargo install cargo-xwin
else
    echo "cargo-xwin already installed."
fi

echo "=== 3. Compiling Windows executable (.exe) ==="
npx tauri build --runner cargo-xwin --target x86_64-pc-windows-msvc --no-bundle

echo "=== 4. Copying built binary to project root ==="
mkdir -p dist
cp src-tauri/target/x86_64-pc-windows-msvc/release/locspoof-tauri.exe ./LocSpoofPro.exe

echo "=== SUCCESS! Compiled binary saved as LocSpoof-Tauri/LocSpoofPro.exe ==="
