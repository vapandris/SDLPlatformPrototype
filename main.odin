package platform

import "core:fmt"
import "core:c"
import SDL "vendor:sdl2"

WINDOW_WIDTH   :: 718
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

    window := SDL.CreateWindow("Buffer example", SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED, WINDOW_WIDTH, WINDOW_HEIGHT, {.RESIZABLE})
    SDL.SetWindowMinimumSize(window, GAME_WIDTH, GAME_HEIGHT)
    renderer := SDL.CreateRenderer(window, -1, {.ACCELERATED})

    running := true
    event: SDL.Event
    for running {
        for SDL.PollEvent(&event) {
            if event.type == .QUIT {
                running = false
            }
        }

        gameScreen: [GAME_WIDTH * GAME_HEIGHT]Pixel
        for y in 0..<GAME_HEIGHT {
            for x in 0..<GAME_WIDTH {
                    color := Pixel{}
                    color.r = u8(x % 0xFF)
                    color.g = u8(y % 0xFF)
                    color.b = u8(int(color.r/2 + color.g/2) % 256)
                    color.a = 0xFF

                    gameScreen[y*GAME_WIDTH + x] = color
            }

        }

        windowSize := PxPos{}
        SDL.GetWindowSize(window, cast(^c.int)&windowSize.x, cast(^c.int)&windowSize.y)

        // Pixel color order is reversed because of endianness and historycal stuff (that's why ABRG instead if RGBA)
        buffer := SDL.CreateTexture(renderer, .ABGR8888, .STREAMING, c.int(windowSize.x), c.int(windowSize.y))
        assert(buffer != nil)


        pixels: [^]Pixel
        defer SDL.DestroyTexture(buffer)
        {
            pixelsPtr: rawptr
            pitch: c.int
            SDL.LockTexture(buffer, nil, &pixelsPtr, &pitch)
            defer SDL.UnlockTexture(buffer)

            scaler := min(windowSize.x/GAME_WIDTH, windowSize.y/GAME_HEIGHT)
            gameAreaSize := PxPos{ GAME_WIDTH, GAME_HEIGHT } * scaler
            xDiff := windowSize.x - gameAreaSize.x
            yDiff := windowSize.y - gameAreaSize.y

            //fmt.println(windowSize, "|", PxPos { xDiff, yDiff }, "|", gameAreaSize, "|", scaler)

            pixels = cast([^]Pixel)pixelsPtr
            for y in 0..<windowSize.y {
                for x in 0..<windowSize.x {
                    color := Pixel{}

                    // When the windowSize is odd, the right or bottom black bar will be 1px bigger
                    leftBoxSize   := PxPos{ xDiff/2, windowSize.y }
                    rightBoxSize   := PxPos{ xDiff/2 + xDiff%2, windowSize.y }
                    topBoxSize := PxPos{ windowSize.x, yDiff/2 }
                    botBoxSize := PxPos{ windowSize.x, yDiff/2+yDiff%2 }

                    leftBoxPos := PxPos{ 0, 0 }
                    rightBoxPos := PxPos{ leftBoxSize.x + gameAreaSize.x, 0 }
                    topBoxPos := PxPos{ 0, 0 }
                    botBoxPos := PxPos{ 0, topBoxSize.y + gameAreaSize.y }


                    leftBoxCollide := IsPointInsideRect( { x, y }, leftBoxPos, leftBoxSize)
                    rightBoxCollide := IsPointInsideRect( { x, y }, rightBoxPos, rightBoxSize)
                    topBoxCollide := IsPointInsideRect( { x, y }, topBoxPos, topBoxSize)
                    botBoxCollide := IsPointInsideRect( { x, y }, botBoxPos, botBoxSize)

                    if !(leftBoxCollide || rightBoxCollide  ||
                       topBoxCollide || botBoxCollide) {
                        // Normally indexing the gameScreen buffer would be:
                        // - y * GAME_WIDTH + x
                        // When we add the black-border-offset to the mix, it will be:
                        // - (y-yDiff/2) GAME_WIDTH + x
                        // When we add scaling to the mix, it will STILL use the original GAME_WIDTH, and scale down the indexing:
                        // - ((y-yDiff/2)/scaler)*GAME_WIDTH + ((x-xDiff/2)/scaler)
                        shiftedLocation := ((y-yDiff/2)/scaler)*GAME_WIDTH + ((x-xDiff/2)/scaler)
                        if shiftedLocation >= 57600 {
                            fmt.println(windowSize, "|", PxPos { xDiff, yDiff }, "|", gameAreaSize, "|", scaler)
                            fmt.println(shiftedLocation, "= {x: ", x-xDiff/2, ", y: ", y-yDiff/2, "}", "| {x: ", x, ", y: ", y, "}")
                        }
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
