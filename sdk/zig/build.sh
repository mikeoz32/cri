#!/bin/sh
set -eu

project="${1:?usage: sdk/zig/build.sh EXTENSION_DIR [OUTPUT] }"
output="${2:-$project/plugin.wasm}"
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
case "$project" in /*) project_path="$project" ;; *) project_path="$root/$project" ;; esac
case "$output" in /*) output_path="$output" ;; *) output_path="$root/$output" ;; esac

cd "$root"
zig build-exe \
  -target wasm32-freestanding \
  -O ReleaseSmall \
  -fno-entry \
  --export-memory \
  --export=alloc \
  --export=cri_init \
  --export=cri_free \
  --export=cri_call \
  --export=cri_resume \
  --export=cri_result_len \
  --export=cri_free_result \
  --dep cri_sdk \
  --dep cri_effects \
  -Mroot="$project_path/src/main.zig" \
  -Mcri_sdk="$root/sdk/zig/src/cri_sdk.zig" \
  -Mcri_effects="$root/sdk/zig/src/effects.zig" \
  -femit-bin="$output_path"
