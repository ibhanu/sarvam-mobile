#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"

echo "==> [1/4] Syncing sarvam-gen codegen (including packages/rust-core/src/generated.rs)..."
node "$ROOT_DIR/codegen/src/cli.mjs"

echo "==> [2/4] Running Rust Core unit & conformance tests..."
cargo test --manifest-path "$ROOT_DIR/packages/rust-core/Cargo.toml"

echo "==> [3/4] Building native release binary (cdylib + staticlib)..."
cargo build --release --manifest-path "$ROOT_DIR/packages/rust-core/Cargo.toml"

echo "==> [4/4] Building WebAssembly release binary (wasm32-unknown-unknown)..."
cargo build --release --target wasm32-unknown-unknown --manifest-path "$ROOT_DIR/packages/rust-core/Cargo.toml"

ls -lh \
  "$ROOT_DIR/packages/rust-core/target/release/libsarvam_rust_core."* \
  "$ROOT_DIR/packages/rust-core/target/wasm32-unknown-unknown/release/sarvam_rust_core.wasm"
