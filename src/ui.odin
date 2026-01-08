
package main

import "core:fmt"

import SDL "vendor:sdl3"
import TTF "vendor:sdl3/ttf"

import clay "clay-odin"

render_layout :: proc(render_commands: ^clay.ClayArray(clay.RenderCommand)) {
	for idx in 0..<i32(render_commands.length) {
        render_command := clay.RenderCommandArray_Get(render_commands, idx)
        #partial switch render_command.commandType {
        case .Rectangle:
            //fmt.println(render_command)
            rect := render_command.renderData.rectangle
            color := rect.backgroundColor
            SDL.SetRenderDrawColor(renderer, u8(color[0]), u8(color[1]), u8(color[2]), u8(color[3]))
			SDL.SetRenderDrawBlendMode(renderer, {.BLEND})
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

			rect := render_command.renderData.rectangle
            color := rect.backgroundColor

			tex := (^SDL.Texture)(render_command.renderData.image.imageData)
            SDL.SetTextureColorMod(tex, u8(color[0]), u8(color[1]), u8(color[2]))
			SDL.SetTextureAlphaMod(tex, u8(color[3]))
			SDL.SetTextureBlendMode(tex, {.BLEND})

            box := render_command.boundingBox
            rect2 := SDL.FRect{
                w = box.width,
                h = box.height,
                x = box.x,
                y = box.y,
            }
            SDL.RenderTexture(renderer, tex, nil, &rect2)

        case:
        	// hello
        	fmt.println(render_command)
        }

    }
}
