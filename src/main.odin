
package main


import SDL "vendor:sdl3"
import IMG "vendor:sdl3/image"
import TTF "vendor:sdl3/ttf"


import "core:fmt"
import "core:c"
// import "core:os"

import "base:runtime"

import "emscripten"

import clay "clay-odin"

ctx: runtime.Context


window: ^SDL.Window
renderer: ^SDL.Renderer
texture: ^SDL.Texture
texture_size: [2]i32
engine: ^TTF.TextEngine
font: ^TTF.Font
text: ^TTF.Text

// @(export) emscripten_cancel_main_loop :: proc "c" () {

// }
// @(export) abort :: proc "c" () {

// }

clay_memory: []byte

win_size: [2]i32

@export
main_start :: proc "c" () {

    sdl_app_init(nil, 0, nil)


    context = ctx
    request_data("/sample.jpg", assign_texture)
    request_data("/Play-Regular.ttf", assign_font)

    min_size := clay.MinMemorySize()

    clay_memory = make([]byte, min_size)
    clay_arena := clay.CreateArenaWithCapacityAndMemory(uint(min_size), &clay_memory[0])
    clay.Initialize(clay_arena, {640, 480}, { handler = clay_error_handler })
    clay.SetMeasureTextFunction(clay_measure_text, nil)
}

clay_error_handler :: proc "c" (errorData: clay.ErrorData) {
    context = ctx
    fmt.println(errorData)
}

clay_measure_text :: proc "c" (
    text: clay.StringSlice,
    config: ^clay.TextElementConfig,
    userData: rawptr,
) -> clay.Dimensions {
    return {
        width = f32(text.length * i32(config.fontSize)) * 0.5,
        height = f32(config.fontSize),
    }
}

assign_texture :: proc (bytes: []byte) {
    io := SDL.IOFromConstMem(&bytes[0], len(bytes))
    texture = IMG.LoadTexture_IO(renderer, io, false)
}

assign_font :: proc (bytes: []byte) {
    io := SDL.IOFromConstMem(&bytes[0], len(bytes))
    font = TTF.OpenFontIO(io, false, 16)

    if font == nil {
        fmt.println("unable to load font:", SDL.GetError())
    }

    text = TTF.CreateText(engine, font, "My Text", 0)
    TTF.SetTextColor(text, 255, 255, 255, 255)

}

fetch_success :: proc "c" (result: ^emscripten.emscripten_fetch_t) {
    context = ctx

    data: [^]byte = ([^]byte)(result.data)
    size: int = (int)(result.numBytes)
    if size == 0 {
       return
    }

    bytes := data[0:size]
    callback := (proc(bytes: []byte))(result.userData)
    callback(bytes)
}


request_data :: proc (url: cstring, callback: proc(bytes: []byte)) {
    fetch_attr := emscripten.emscripten_fetch_attr_t {}
    emscripten.emscripten_fetch_attr_init(&fetch_attr)
    fetch_attr.onsuccess = fetch_success
    fetch_attr.attributes = emscripten.EMSCRIPTEN_FETCH_LOAD_TO_MEMORY
    fetch_attr.userData = rawptr(callback)
    emscripten.emscripten_fetch(&fetch_attr, url)
}

@export
main_update :: proc "c" () -> bool {
    return sdl_app_iterate(nil) == .CONTINUE
}

@export
main_end :: proc "c" () {
    sdl_app_quit(nil, {})
}

@export
web_window_size_changed :: proc "c" (w: c.int, h: c.int) {
    win_size = {w, h}
    SDL.SetWindowSize(window, w, h)
}



sdl_app_init :: proc "c" (appstate: ^rawptr, argc: i32, argv: [^]cstring) -> SDL.AppResult {
    context = ctx
    _ = SDL.SetAppMetadata("Example", "1.0", "com.example")

    if (!SDL.Init(SDL.INIT_VIDEO)) {
        return .FAILURE
    }

    if !TTF.Init() {
        fmt.println("Failed to initialize TTF engine")
        return .FAILURE
    }

    if (!SDL.CreateWindowAndRenderer("examples", 640, 480, {}, &window, &renderer)){
        return .FAILURE
    }

    engine = TTF.CreateRendererTextEngine(renderer)

    return .CONTINUE
}

sdl_app_event :: proc "c" (appstate: rawptr, event: ^SDL.Event) -> SDL.AppResult {
    context = ctx
    fmt.println(event)
    if event.type == .QUIT {
        return .SUCCESS
    }
    return .CONTINUE
}

sdl_app_iterate :: proc "c" (appstate: rawptr) -> SDL.AppResult {
    context = ctx
    //fmt.println("hello")

    SDL.SetRenderDrawColor(renderer, 0, 0, 0, 255)
    //SDL.RenderClear(renderer)

    rect := SDL.FRect{w = f32(texture_size.x), h = f32(texture_size.y)}
    rect.w = 100
    rect.h = 100

    //SDL.SetRenderDrawBlendMode(renderer, .ADD)
    SDL.SetRenderDrawColor(renderer, 255, 0, 0, 255)
    SDL.RenderFillRect(renderer, &rect)
    SDL.SetRenderDrawColor(renderer, 255, 0, 255, 255)
    SDL.RenderRect(renderer, &rect)

    if texture != nil {
       rect.w = f32(texture.w)
       rect.h = f32(texture.h)
       SDL.RenderTexture(renderer, texture, nil, &rect)
    }

    if text != nil {
        TTF.DrawRendererText(text, 100, 100)
    }

    clay.SetLayoutDimensions({f32(win_size.x), f32(win_size.y)})
    render_commands := create_layout()

    for idx in 0..<i32(render_commands.length) {
        render_command := clay.RenderCommandArray_Get(&render_commands, idx)
        #partial switch render_command.commandType {
        case .Rectangle:
            //fmt.println(render_command)
            rect := render_command.renderData.rectangle
            color := rect.backgroundColor
            SDL.SetRenderDrawColor(renderer, u8(color[0]), u8(color[1]), u8(color[2]), u8(color[3]))

            box := render_command.boundingBox
            rect2 := SDL.FRect{
                w = box.width,
                h = box.height,
                x = box.x,
                y = box.y,
            }
            SDL.RenderFillRect(renderer, &rect2)
        case .Text:
            //fmt.println(render_command)
            box := render_command.boundingBox
            text_data := render_command.renderData.text
            color := text_data.textColor

            if text != nil {
                TTF.SetTextColor(text, u8(color[0]), u8(color[1]), u8(color[2]), u8(color[3]))
                string_slice := text_data.stringContents
                TTF.SetTextString(text, cstring(string_slice.chars), uint(string_slice.length))
                TTF.SetTextWrapWidth(text, i32(box.width))
                TTF.DrawRendererText(text, box.x, box.y)
            }
        case .Image:

            box := render_command.boundingBox
            rect2 := SDL.FRect{
                w = box.width,
                h = box.height,
                x = box.x,
                y = box.y,
            }
            tex := (^SDL.Texture)(render_command.renderData.image.imageData)
            SDL.RenderTexture(renderer, texture, nil, &rect2)

        case:
        	// hello
        	fmt.println(render_command)
        }

    }

    SDL.RenderPresent(renderer)



    return .CONTINUE
}

// Define some colors.
COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}
COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
COLOR_BLACK :: clay.Color{0, 0, 0, 255}

// Layout config is just a struct that can be declared statically, or inline


// Re-useable components are just normal procs.
sidebar_item_component :: proc(index: u32) {
    sidebar_item_layout := clay.LayoutConfig {
        sizing = {
            width = clay.SizingGrow({}),
            height = clay.SizingFixed(50)
        },
    }
    if clay.UI(clay.ID("SidebarBlob", index))({
        layout = sidebar_item_layout,
        backgroundColor = COLOR_ORANGE,
    }) {}
}


// An example function to create your layout tree
create_layout :: proc() -> clay.ClayArray(clay.RenderCommand) {
    // Begin constructing the layout.
    clay.BeginLayout()

    // An example of laying out a UI with a fixed-width sidebar and flexible-width main content
    // NOTE: To create a scope for child components, the Odin API uses `if` with components that have children
    if clay.UI(clay.ID("OuterContainer"))({
        layout = {
            sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) },
            padding = { 16, 16, 16, 16 },
            childGap = 16,
        },
        backgroundColor = { 250, 250, 255, 255 },
    }) {
        if clay.UI(clay.ID("SideBar"))({
            layout = {
                layoutDirection = .TopToBottom,
                sizing = { width = clay.SizingFixed(300), height = clay.SizingGrow({}) },
                padding = { 16, 16, 16, 16 },
                childGap = 16,
            },
            backgroundColor = COLOR_LIGHT,
        }) {
            if clay.UI(clay.ID("ProfilePictureOuter"))({
                layout = {
                    sizing = { width = clay.SizingGrow({}) },
                    padding = { 16, 16, 16, 16 },
                    childGap = 16,
                    childAlignment = { y = .Center },
                },
                backgroundColor = COLOR_RED,
                cornerRadius = { 6, 6, 6, 6 },
            }) {
                if clay.UI(clay.ID("ProfilePicture"))({
                    layout = {
                        sizing = { width = clay.SizingFixed(60), height = clay.SizingFixed(60) },
                    },
                    image = {
                        imageData = texture, //&profile_picture,
                    },
                }) {}

                clay.Text(
                    "Clay - UI Library",
                    clay.TextConfig({ textColor = COLOR_LIGHT, fontSize = 16 }),
                )
            }

            // Standard Odin code like loops, etc. work inside components.
            // Here we render 5 sidebar items.
            for i in u32(0)..<5 {
                sidebar_item_component(i)
            }
        }

        if clay.UI(clay.ID("MainContent"))({
            layout = {
                sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) },
            },
            backgroundColor = COLOR_LIGHT,
        }) {}
    }

    // Returns a list of render commands
    return clay.EndLayout()
}

sdl_app_quit :: proc "c" (appstate: rawptr, result: SDL.AppResult) {
    // fmt.println("quit")

}

main :: proc() {
ctx = context
}

//when ODIN_OS != .Freestanding {
/*
    main :: proc () {
        // fmt.println("main")
        ctx = context
        //args := os.args
        SDL.EnterAppMainCallbacks(0, nil, sdl_app_init, sdl_app_iterate, sdl_app_event, sdl_app_quit)
    }
*/
//}
