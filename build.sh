#! /bin/bash
# Copyright Andrés Botero 2025
#
set -e

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


if [[ "$TARGET" = "" ]]; then
	TARGET="linux"
fi


#TARGET="linux"
#TARGET="web" # when it is web, cmake with emcmake

cmake_cmd() {
	if [[ "$TARGET" = "web" ]]; then
		if [ -z "$EMSDK" ]; then
			echo "Loading emsdk environment"
			source "$EMSDK_PATH/emsdk_env.sh"
		fi
		echo emcmake cmake "$@"
		emcmake cmake "$@"
	else
		echo cmake "$@"
		cmake "$@"
	fi
}

# ensure that SDL is built
BUILD_PATH="build/$TARGET"

BUILD_PATH="$(pwd)/$BUILD_PATH"

SDL_LIBRARY="sdl/libSDL3"
SDLIMG_LIBRARY="sdl_image/libSDL3_image"
SDLTTF_LIBRARY="sdl_ttf/libSDL3_ttf"

SUFFIX=".ext"
if [[ "$TARGET" = "linux" ]]; then
	SUFFIX=".so"
fi
if [[ "$TARGET" = "web" ]]; then
	SUFFIX=".a"
fi

SDL_LIBRARY="${SDL_LIBRARY}${SUFFIX}"
SDLIMG_LIBRARY="${SDLIMG_LIBRARY}${SUFFIX}"
SDLTTF_LIBRARY="${SDLTTF_LIBRARY}${SUFFIX}"



if [ ! -e "$BUILD_PATH/$SDL_LIBRARY" ]; then

    mkdir -p "$BUILD_PATH/sdl"
    pushd "$BUILD_PATH/sdl"

	cmake_cmd "$SDL_PATH" -DCMAKE_INSTALL_PREFIX="$(pwd)"
    make "-j$(nproc)"
	if [[ "$TARGET" = "linux" ]]; then
		make install
	fi
	popd
fi

if [ ! -e "$BUILD_PATH/$SDLIMG_LIBRARY" ]; then
    mkdir -p "$BUILD_PATH/sdl_image"
    pushd "$BUILD_PATH/sdl_image"
    cmake_cmd "$SDLIMG_PATH" -DSDL3_DIR="$BUILD_PATH/sdl" -DCMAKE_INSTALL_PREFIX="$(pwd)"
    make "-j$(nproc)"
    if [[ "$TARGET" = "linux" ]]; then
		make install
	fi
	popd
fi

if [ ! -e "$BUILD_PATH/$SDLTTF_LIBRARY" ]; then
    mkdir -p "$BUILD_PATH/sdl_ttf"
    pushd "$BUILD_PATH/sdl_ttf"
    cmake_cmd cmake "$SDLTTF_PATH" -DSDL3_DIR="$BUILD_PATH/sdl" -DSDLTTF_VENDORED=true -DSDLTTF_SAMPLES=false -DCMAKE_INSTALL_PREFIX="$(pwd)"
    make "-j$(nproc)"
	if [[ "$TARGET" = "linux" ]]; then
		make install
	fi
	popd
fi


echo "Compiling"

compile_cmd=("$ODIN_PATH/odin" build src)

if [[ "$TARGET" = "linux" ]]; then
	current_dir=$(pwd)
	# LD_LIBRARY_PATH="$current_dir/$BUILD_PATH/sdl:$LD_LIBRARY_PATH"
	# LD_LIBRARY_PATH="$current_dir/$BUILD_PATH/sdl_image:$LD_LIBRARY_PATH"
	# LD_LIBRARY_PATH="$current_dir/$BUILD_PATH/sdl_ttf:$LD_LIBRARY_PATH"

	# export LD_LIBRARY_PATH
	# echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
	linker_flags=""
	linker_flags="$linker_flags -L$BUILD_PATH/sdl/lib"
	linker_flags="$linker_flags -L$BUILD_PATH/sdl_image/lib"
	linker_flags="$linker_flags -L$BUILD_PATH/sdl_ttf/lib"

	compile_cmd+=(
		-extra-linker-flags:"$linker_flags"
	)
fi
if [[ "$TARGET" = "web" ]]; then
	compile_cmd+=(
		-target:js_wasm32
		-define:ODIN_DEFAULT_TO_EMSCRIPTEN_ALLOCATOR=true
		-build-mode:obj
		-debug
		-out:game.wasm.o
#      -show-system-calls
	)
fi

echo "${compile_cmd[@]}"
"${compile_cmd[@]}"

if [[ "$TARGET" = "web" ]]; then

	if [ -z "$EMSDK" ]; then
		echo "source $EMSDK_PATH/emsdk_env.sh"
		echo "  (this step can be skipped if you source beforehand)"
		source "$EMSDK_PATH/emsdk_env.sh" >/dev/null 2>&1
	fi

	link_cmd=(\
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
		-sASSERTIONS=1\
		-sALLOW_MEMORY_GROWTH\
		-g\
		-O1\
		)

	echo "${link_cmd[@]}"
	"${link_cmd[@]}"
fi
echo "done"
