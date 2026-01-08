
package main

import SDL "vendor:sdl3"
import IMG "vendor:sdl3/image"
import TTF "vendor:sdl3/ttf"


import "core:fmt"
import "core:c"
import "core:strings"
import "core:log"

import "base:runtime"

import "emscripten"

import clay "clay-odin"

ctx: runtime.Context


window: ^SDL.Window
renderer: ^SDL.Renderer
engine: ^TTF.TextEngine
font: ^TTF.Font
text: ^TTF.Text


clay_memory: []byte

win_size: [2]i32 = {640, 480}

///////////////////////////////////////////////////////
// desktop/wasm handling

when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {

	@export
	main_start :: proc "c" () {
		sdl_app_init(nil, 0, nil)
	}

	@export
	web_window_size_changed :: proc "c" (w: c.int, h: c.int) {
		SDL.SetWindowSize(window, w, h)
	}

	@export
	main_update :: proc "c" () -> bool {
		event: SDL.Event
		context = ctx
		for (SDL.PollEvent(&event)) {
			sdl_app_event(nil, &event)
		}
		return sdl_app_iterate(nil) == .CONTINUE
	}


	@export
	main_end :: proc "c" () {
		sdl_app_quit(nil, {})
	}
}

main :: proc () {
	fmt.println("main")
	context.logger = log.create_console_logger()
    ctx = context
    //args := os.args
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	} else {
        SDL.EnterAppMainCallbacks(0, nil, sdl_app_init, sdl_app_iterate, sdl_app_event, sdl_app_quit)
    }
}


///////////////////////////////////////////////////////

RequestResult :: struct {
	success: bool,
	bytes: []byte,
	user_data: rawptr,
}

RequestHandler :: struct {
	ctx: runtime.Context,
	user_handler: proc(result: RequestResult),
	user_data: rawptr,
}


// async on web, synchronous on desktop
request_data :: proc (url: cstring, user_data: rawptr, callback: proc(result: RequestResult)) {
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		fetch_attr := emscripten.emscripten_fetch_attr_t {}
		emscripten.emscripten_fetch_attr_init(&fetch_attr)
		fetch_attr.onsuccess = fetch_success
		fetch_attr.onerror = fetch_error
		fetch_attr.attributes = emscripten.EMSCRIPTEN_FETCH_LOAD_TO_MEMORY

		callback_info := new(RequestHandler)
		callback_info.user_handler = callback
		callback_info.user_data = user_data
		callback_info.ctx = context

		fetch_attr.userData = callback_info
		emscripten.emscripten_fetch(&fetch_attr, url)
	} else {

		file_size: uint = ---
		file_data :=  ([^]byte) (SDL.LoadFile(url, &file_size))

		result := RequestResult {
			success = true,
			bytes = file_data[0:file_size],
			user_data = user_data,
		}

		callback(result)

	}
}


fetch_error :: proc "c" (fetch_result: ^emscripten.emscripten_fetch_t) {
	request_handler := (^RequestHandler)(fetch_result.userData)
	context = request_handler.ctx
	result := RequestResult {
		success = false,
		user_data = request_handler.user_data,
	}
    request_handler.user_handler(result)
	free(request_handler)
}


fetch_success :: proc "c" (fetch_result: ^emscripten.emscripten_fetch_t) {
	request_handler := (^RequestHandler)(fetch_result.userData)
	context = request_handler.ctx
	result := RequestResult {
		success = true,
		user_data = request_handler.user_data,
		bytes = (([^]byte)(fetch_result.data))[0:fetch_result.numBytes],
	}

    request_handler.user_handler(result)
	free(request_handler)
}



///////////////////////////////////////////////////////

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

GalleryImage :: struct {
	img_path: string,
	bytes: []byte,
	texture: ^SDL.Texture,
}

images: [dynamic]GalleryImage

parse_files :: proc (result: RequestResult) {
	bytes := result.bytes
    file := string(bytes)

    for path in strings.split_iterator(&file, "\n") {
		image := GalleryImage {
			img_path = path
		}
		ImgPath :: struct {
			index: uint
		}
		img_idx := uint(len(images))

        append(&images, image) // crash on web
        full_path := fmt.tprintf("content/%s", path)

		c_path := strings.clone_to_cstring(full_path)

		img_path := new(ImgPath)
		img_path^ = {img_idx}
		request_data(c_path, img_path, proc(result: RequestResult) {
			img_path := (^ImgPath)(result.user_data)
			bytes := result.bytes
			io := SDL.IOFromConstMem(&bytes[0], len(bytes))
			image := &images[img_path.index]
			image.texture = IMG.LoadTexture_IO(renderer, io, false)
		})
    }
}

assign_font :: proc (result: RequestResult) {
	bytes := result.bytes
    io := SDL.IOFromConstMem(&bytes[0], len(bytes))
    font = TTF.OpenFontIO(io, false, 16)

    if font == nil {
        fmt.println("unable to load font:", SDL.GetError())
    }

    text = TTF.CreateText(engine, font, "My Text", 0)
    TTF.SetTextColor(text, 255, 255, 255, 255)
}




sdl_app_init :: proc "c" (appstate: ^rawptr, argc: i32, argv: [^]cstring) -> SDL.AppResult {
    context = ctx
    fmt.println("hello")
    _ = SDL.SetAppMetadata("Example", "1.0", "com.example")

    if (!SDL.Init(SDL.INIT_VIDEO)) {
        return .FAILURE
    }

    if !TTF.Init() {
        fmt.println("Failed to initialize TTF engine")
        return .FAILURE
    }

    if (!SDL.CreateWindowAndRenderer("examples", win_size.x, win_size.y, {}, &window, &renderer)){
        return .FAILURE
    }
	SDL.SetWindowResizable(window, true)

    engine = TTF.CreateRendererTextEngine(renderer)


    context = ctx
    request_data("Play-Regular.ttf", nil, assign_font)
    request_data("content/files.txt", nil, parse_files)

    min_size := clay.MinMemorySize()

    clay_memory = make([]byte, min_size)
    clay_arena := clay.CreateArenaWithCapacityAndMemory(uint(min_size), &clay_memory[0])
    clay.Initialize(clay_arena, {f32(win_size.x), f32(win_size.y)}, { handler = clay_error_handler })
    clay.SetMeasureTextFunction(clay_measure_text, nil)

    return .CONTINUE
}


sdl_app_quit :: proc "c" (appstate: rawptr, result: SDL.AppResult) {
	context = ctx
    fmt.println("quit")
}


sdl_app_event :: proc "c" (appstate: rawptr, event: ^SDL.Event) -> SDL.AppResult {
    context = ctx
	ui_dirty = true
    retval := SDL.AppResult.CONTINUE
	#partial switch event.type {
	case .MOUSE_MOTION :
			clay.SetPointerState({event.motion.x, event.motion.y}, (event.motion.state & SDL.BUTTON_LMASK) != {} )
	case .MOUSE_BUTTON_DOWN:
			if event.button.button == SDL.BUTTON_LEFT {
				clay.SetPointerState({event.button.x, event.button.y}, true)
			}
	case .MOUSE_BUTTON_UP:
			if event.button.button == SDL.BUTTON_LEFT {
				clay.SetPointerState({event.button.x, event.button.y}, false)
			}
	case .QUIT:
		retval = .SUCCESS
	case .WINDOW_RESIZED:
		//fmt.println("event windiw_resized:", event.window)
		win_size = {event.window.data1, event.window.data2}
	case:
		//fmt.println("event.type:", event.type)

	}
    return retval
}


last_ticks : u64 = 0

desired_delay_ticks: u64 = 1_000_000_000 / 60

next_iterate_ticks: u64 = 0




sdl_app_iterate :: proc "c" (appstate: rawptr) -> SDL.AppResult {
    context = ctx

	current_ticks := SDL.GetTicksNS()
	missing_ticks: i64 = i64(next_iterate_ticks) - i64(current_ticks)

	if missing_ticks > 0 {
		SDL.DelayNS(u64(missing_ticks))
	}

	actual_ticks := SDL.GetTicksNS()
	delta_ticks := actual_ticks - last_ticks
	last_ticks = actual_ticks
	next_iterate_ticks = actual_ticks + desired_delay_ticks

	delta_time := f64(delta_ticks) / 1000000000.0

	app_tick(delta_time)

	app_draw()
	return .CONTINUE
}

SlideState :: enum {
	Showing,
	Transitioning,
}

current_state: SlideState

current_show_time: f64
max_show_time: f64 = 5.0

current_transition_time: f64
transition_time: f64 = 1.0

current_img_idx := 0


app_tick :: proc (dt: f64) {
	if current_state == .Showing {
		current_show_time += dt
		if current_show_time >= max_show_time {
			current_transition_time = 0
			current_state = .Transitioning
		}
	} else if current_state == .Transitioning {
		current_transition_time += dt
		ui_dirty = true
		if current_transition_time >= transition_time {
			current_state = .Showing
			current_show_time = 0
			current_img_idx = get_next_img_idx(current_img_idx)
		}
	}
}

get_next_img_idx :: proc(idx: int) -> int {
	return (idx + 1) % len(images)
}


app_draw :: proc () {
	if ui_dirty {
		ui_dirty = false

/*
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

*/
		clay.SetLayoutDimensions({f32(win_size.x), f32(win_size.y)})
		free_all(context.temp_allocator)
		render_commands := create_layout()
		render_layout(&render_commands)

		SDL.RenderPresent(renderer)
	}
}






ui_dirty: bool = true

// Define some colors.
COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}
COLOR_ORANGE :: clay.Color{0, 138, 50, 255}
COLOR_ORANGE_LIGHT :: clay.Color{50, 188, 100, 255}
COLOR_BLACK :: clay.Color{0, 0, 0, 255}

COLOR_IMAGES := []clay.Color {
	{255,    0,    0, 255},
	{255,  255,    0, 255},
	{  0,  255,    0, 255},
	{  0,  255,  255, 255},
	{  0,    0,  255, 255},
	{255,    0,  255, 255},
}

// Layout config is just a struct that can be declared statically, or inline


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
		backgroundColor = {0, 0, 0, 255}
    }) {

		if len(images) > 0 {

			back_color := clay.Color{255, 255, 255, 255}
			curr_img_tex := images[current_img_idx].texture
			if clay.UI(clay.ID("Background"))({
				floating = {
					attachTo = .Parent,
					attachment = {
						element = .CenterCenter,
						parent = .CenterCenter,
					},
				},
				layout = {
					sizing = {
						width = clay.SizingPercent(1),
						height = clay.SizingPercent(1),
					},
				},
				backgroundColor = back_color,
				image = {
					imageData = curr_img_tex
				},
				aspectRatio = {f32(curr_img_tex.w) / f32(curr_img_tex.h)}
			}) {

			}

			if current_state == .Transitioning {
				next_img_idx := get_next_img_idx(current_img_idx)
				next_img_tex := images[next_img_idx].texture
				front_color := clay.Color{255, 255, 255, 255}
				progress := current_transition_time / transition_time
				alpha := f32(progress * 255)
				front_color.a = alpha
				if clay.UI(clay.ID("BlendIn"))({
					floating = {
						attachTo = .Parent,
						attachment = {
							element = .CenterCenter,
							parent = .CenterCenter,
						},
					},
					layout = {
						sizing = {
							width = clay.SizingPercent(1),
							height = clay.SizingPercent(1),
						},
					},
					backgroundColor = front_color,
					image = {
						imageData = next_img_tex
					},
					aspectRatio = {f32(next_img_tex.w) / f32(next_img_tex.h)}
				}) { }

			}
		}


        if clay.UI(clay.ID("ToolBar"))({
            layout = {
                layoutDirection = .LeftToRight,
                sizing = { width = clay.SizingFit(), height = clay.SizingFit() },
                childGap = 16,
            },
			floating = {
				attachTo = .Parent,
				attachment = {
					element = .CenterBottom,
					parent = .CenterBottom,
				},
				offset = {0, -16},
			},
        }) {

			toolbar := clay.ElementDeclaration {
				layout = { layoutDirection = .TopToBottom },
				backgroundColor = COLOR_LIGHT,
			}

			if clay.UI(clay.ID("ToolBarSection"))(toolbar) {
				clay.Text(
                    "Gallery Config",
                    clay.TextConfig({ textColor = COLOR_RED, fontSize = 16 }),
                )

				if clay.UI()({
					layout = {layoutDirection = .LeftToRight}
				}){
					sidebar_item_component("Select Folder", proc(c: rawptr) {
						select_directory()
					})
					sidebar_item_component("Config Online Src")
				}
			}

			if clay.UI(clay.ID("ToolBarSection2"))(toolbar) {
				clay.Text(
                    "Slideshow",
                    clay.TextConfig({ textColor = COLOR_RED, fontSize = 16 }),
                )
				if clay.UI()({
					layout = {layoutDirection = .LeftToRight}
				}){
					sidebar_item_component("First", proc(c: rawptr) { playback_first()})
					sidebar_item_component("Previous", proc(c: rawptr) { playback_previous()})
					sidebar_item_component("PlayPause", proc(c: rawptr) { playback_playpause()})
					sidebar_item_component("Next", proc(c: rawptr) { playback_next()})
					sidebar_item_component("Last", proc(c: rawptr) { playback_last()})
				}
			}

        }
    }

    // Returns a list of render commands
    return clay.EndLayout()
}

select_directory :: proc() {
	fmt.println("select_directory")
	SDL.ShowOpenFolderDialog(select_directory_callback, nil, nil, nil, true)
}

select_directory_callback: SDL.DialogFileCallback : proc "c" (userdata: rawptr, filelist: [^]cstring, filter: c.int) {
	context = ctx
	if filelist == nil {
		error := SDL.GetError()
		fmt.println("got error:", error)
	} else {
		fmt.println("got file list: ", filelist)
	}

}

playback_first :: proc() {
	fmt.println("first")
}
playback_previous :: proc() {
	fmt.println("previous")
}
playback_playpause :: proc() {
	fmt.println("playpause")
}
playback_next :: proc() {
	fmt.println("next")
}
playback_last :: proc() {
	fmt.println("last")
}


// ClayButtonHandlerType :: #type proc(id: clay.ElementId, pointerData: clay.PointerData, userdata: rawptr)
ButtonHandlerType :: #type proc(userdata: rawptr)

HandlerInfo :: struct {
	handler: ButtonHandlerType,
	ctx: runtime.Context,
	data: rawptr,
}

button_handler :: proc(a: clay.ElementId, b: clay.PointerData, c: rawptr) {
	if (b.state == .PressedThisFrame) {
		fmt.println("Just pressed!")
	}
}

HandleButton :: proc "c" (id: clay.ElementId, pointerData: clay.PointerData, userData: rawptr) {
	if (pointerData.state == .PressedThisFrame) {

		handler_data := (^HandlerInfo)(userData)
		context = handler_data.ctx
		if handler_data.handler != nil {
			handler_data.handler(handler_data.data)
		}
	}
}

// Re-useable components are just normal procs.
sidebar_item_component :: proc($label: string, callback: ButtonHandlerType = nil, user_data: rawptr = nil) {
    sidebar_item_layout := clay.LayoutConfig {
        sizing = {
            width = clay.SizingFixed(50),
            height = clay.SizingFixed(50),
        },
    }

	colors := []clay.Color {COLOR_ORANGE, COLOR_ORANGE_LIGHT}
	if clay.UI(clay.ID(label))({
        layout = sidebar_item_layout,
        backgroundColor = colors[clay.Hovered() ? 1 : 0],
    }) {

		if callback != nil {
			info := new(HandlerInfo, context.temp_allocator)
			info.handler = callback
			info.ctx = context
			info.data = user_data
			clay.OnHover(HandleButton, info)
		}
		clay.Text(
            label,
            clay.TextConfig({ textColor = COLOR_RED, fontSize = 16 }),
        )
	}
}


