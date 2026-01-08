#!/usr/bin/env bash



pushd clay/bindings/odin

cp ../../clay.h clay.c;



# Linux
echo "Compiling clay linux"

rm -f clay-odin/linux/clay.a && clang -c -DCLAY_IMPLEMENTATION -o clay.o -ffreestanding -static -target x86_64-unknown-linux-gnu clay.c -fPIC -O3 && ar r clay-odin/linux/clay.a clay.o;
# Linux Debug
#rm -f clay-odin/linux/clay.a && clang -c -DCLAY_IMPLEMENTATION -o clay.o -ffreestanding -static -target x86_64-unknown-linux-gnu clay.c -fPIC -O1 -g && ar r clay-odin/linux/clay.a clay.o;

# WASM
echo "Compiling clay wasm"

rm -f clay-odin/wasm/clay.o && clang -c -DCLAY_IMPLEMENTATION -o clay-odin/wasm/clay.o -target wasm32 -nostdlib -static -O3 clay.c;
popd

cp clay/bindings/odin/clay-odin/linux/clay.a ../src/clay-odin/linux
cp clay/bindings/odin/clay-odin/wasm/clay.o ../src/clay-odin/wasm
