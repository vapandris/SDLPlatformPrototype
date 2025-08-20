package platform

import "core:fmt"
import "core:c"
import SDL "vendor:sdl2"

WINDOW_WIDTH   :: 320*2
WINDOW_HEIGHT  :: 180*2

GAME_WIDTH  :: 320
GAME_HEIGHT :: 180

PxPos :: [2]int
IsPointInsideRect :: proc(point: PxPos, rectTopLeft: PxPos, rectSize: PxPos) -> bool {
    xCollision := rectTopLeft.x <= point.x && point.x < rectTopLeft.x + rectSize.x
    yCollision := rectTopLeft.y <= point.y && point.y < rectTopLeft.y + rectSize.y
    return xCollision && yCollision
}

Pixel :: struct {
    r, g, b, a: u8
}

main :: proc() {
    SDL.Init({.VIDEO})

    window := SDL.CreateWindow("Buffer example", SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED, WINDOW_WIDTH, WINDOW_HEIGHT, {})
    renderer := SDL.CreateRenderer(window, -1, {.ACCELERATED})

    buffer := SDL.CreateTexture(renderer, .ARGB8888, .STREAMING, WINDOW_WIDTH, WINDOW_HEIGHT)
    assert(buffer != nil)

    running := true
    event: SDL.Event
    for running {
        for SDL.PollEvent(&event) {
            if event.type == .QUIT do running = false
        }

        gameScreen: [GAME_WIDTH * GAME_HEIGHT]Pixel
        for y in 0..<GAME_HEIGHT {
            for x in 0..<GAME_WIDTH {
                    color := Pixel{}
                    color.r = u8(x % 256)
                    color.g = u8(y % 256)
                    color.b = u8(int(color.r + color.g) % 256)
                    color.a = 0xFF

                    gameScreen[y*GAME_WIDTH + x] = color
            }

        }

        pixels: [^]Pixel
        {
            pixelsPtr: rawptr
            pitch: c.int
            SDL.LockTexture(buffer, nil, &pixelsPtr, &pitch)
            defer SDL.UnlockTexture(buffer)

            pixels = cast([^]Pixel)pixelsPtr
            for y in 0..<WINDOW_HEIGHT {
                for x in 0..<WINDOW_WIDTH {
                    color := Pixel{}
                    xDiff := WINDOW_WIDTH - GAME_WIDTH
                    yDiff := WINDOW_HEIGHT - GAME_HEIGHT

                    // The two vertical blank bars (on the left and right)
                    // The two horisontal blank bars (on top and bottom)
                    // Will have the same size respectively
                    verticalBoxSize   := PxPos{ xDiff/2, WINDOW_HEIGHT }
                    horisontalBoxSize := PxPos{ WINDOW_WIDTH, yDiff/2 }

                    leftBoxPos := PxPos{ 0, 0 }
                    rightBoxPos := PxPos{ verticalBoxSize.x + GAME_WIDTH, 0 }
                    topBoxPos := PxPos{ 0, 0 }
                    botBoxPos := PxPos{ 0, horisontalBoxSize.y + GAME_HEIGHT }


                    leftBoxCollide := IsPointInsideRect( { x, y }, leftBoxPos, verticalBoxSize)
                    rightBoxCollide := IsPointInsideRect( { x, y }, rightBoxPos, verticalBoxSize)
                    topBoxCollide := IsPointInsideRect( { x, y }, topBoxPos, horisontalBoxSize)
                    botBoxCollide := IsPointInsideRect( { x, y }, botBoxPos, horisontalBoxSize)

                    if leftBoxCollide || rightBoxCollide  ||
                       topBoxCollide || botBoxCollide {
                        color.r = 255
                        color.g = 255
                        color.a = 255
                    } else {
                        shiftedLocation := (y-yDiff/2)*GAME_WIDTH + (x-xDiff/2)
                        //fmt.println(shiftedLocation, "= {x: ", x-xDiff/2, ", y: ", y-yDiff/2, "}", "| {x: ", x, ", y: ", y, "}")
                        color = gameScreen[shiftedLocation]
                    }

                    pixels[y * (int(pitch) / 4) + x] = color

                }
            }
        }

        SDL.RenderClear(renderer)
        SDL.RenderCopy(renderer, buffer, nil, nil)
        SDL.RenderPresent(renderer)

        SDL.Delay(16)

    }

    fmt.println("All done!")
}
