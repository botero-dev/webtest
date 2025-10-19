#! /bin/bash
# Copyright Andrés Botero 2025
#
set -ex

# first ensure that you have:
#  - clang
#  - odin
#  - cmake
#  - emsdk install latest
#  - source emsdk_env
#  - clone https://github.com/libsdl-org/SDL.git
#  - cd SDL && git checkout release-3.2.24
#

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ODIN_PATH="$SCRIPT_PATH/../odin"
SDL_PATH="$SCRIPT_PATH/../SDL"
SDLIMG_PATH="$SCRIPT_PATH/../SDL_image"
SDLTTF_PATH="$SCRIPT_PATH/../SDL_ttf"

# git clone emsdk
# ./emsdk install latest
# ./emsdk activate latest
# you don't need to source emsdk_env as we do here manually
EMSDK_PATH="$SCRIPT_PATH/../emsdk"



# ensure that SDL is built for web
BUILD_PATH="./build"
PREFIX_PATH="./prefix"

SDL_LIBRARY="sdl/libSDL3.a"
SDLIMG_LIBRARY="sdl_image/libSDL3_image.a"
SDLTTF_LIBRARY="sdl_ttf/libSDL3_ttf.a"

if [ ! -e "$BUILD_PATH/$SDL_LIBRARY" ]; then

    mkdir -p "$BUILD_PATH/sdl"
    pushd "$BUILD_PATH/sdl"

    if [ -z "$EMSDK" ]; then
        echo "Loading emsdk environment"
        source "$EMSDK_PATH/emsdk_env.sh"
    fi
    emcmake cmake "$SDL_PATH"
    make "-j$(nproc)"
fi

if [ ! -e "$BUILD_PATH/$SDLIMG_LIBRARY" ]; then
    if [ -z "$EMSDK" ]; then
        echo "Loading emsdk environment"
        source "$EMSDK_PATH/emsdk_env.sh"
    fi
    mkdir -p "$BUILD_PATH/sdl_image"
    pushd "$BUILD_PATH/sdl_image"
    emcmake cmake "$SDLIMG_PATH" -DSDL3_DIR="$BUILD_PATH/sdl"
    popd
    make "-j$(nproc)"
fi

if [ ! -e "$BUILD_PATH/$SDLTTF_LIBRARY" ]; then
    if [ -z "$EMSDK" ]; then
        echo "Loading emsdk environment"
        source "$EMSDK_PATH/emsdk_env.sh"
    fi
    mkdir -p "$BUILD_PATH/sdl_ttf"
    pushd "$BUILD_PATH/sdl_ttf"
    emcmake cmake "$SDLTTF_PATH" -DSDL3_DIR="$BUILD_PATH/sdl" -DSDLTTF_VENDORED=true -DSDLTTF_SAMPLES=false
    popd
    make "-j$(nproc)"
fi

echo "Compiling"

"$ODIN_PATH/odin" build src \
    -target:js_wasm32 \
    -define:ODIN_DEFAULT_TO_EMSCRIPTEN_ALLOCATOR=true \
    -build-mode:obj \
    -debug \
    -out:game.wasm.o \
#    -show-system-calls \


echo "Linking"

if [ -z "$EMSDK" ]; then
    echo "Loading emsdk environment"
    source "$EMSDK_PATH/emsdk_env.sh"
fi

emcc \
    -o "index.html" \
    "game.wasm.o" \
    "src/clay-odin/wasm/clay.o" \
    "$BUILD_PATH/$SDL_LIBRARY" \
    "$BUILD_PATH/$SDLIMG_LIBRARY" \
    "$BUILD_PATH/$SDLTTF_LIBRARY" \
    --shell-file "index_template.html" \
    -sERROR_ON_UNDEFINED_SYMBOLS=0 \
    -sFETCH \
    -g

