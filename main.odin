package platform

import "core:fmt"
import "core:c"
import "base:runtime"
import SDL "vendor:sdl3"

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

AppState :: struct {
    window: ^SDL.Window,
    renderer: ^SDL.Renderer,
    running: bool,
    appContext: runtime.Context,
}

GlobalContext: runtime.Context;

AppInit: SDL.AppInit_func : proc "c" (rawAppState: ^rawptr, argc: c.int, argv: [^]cstring) -> SDL.AppResult {
    GlobalContext = runtime.default_context()
    context = GlobalContext

    appState := new(AppState); assert(appState != nil, "Failed to allocate appState")

    ok := SDL.Init({.VIDEO}); assert(ok, "Failed to init SDL")

    ok = SDL.CreateWindowAndRenderer(
        "Buffer example with callbacks",
        WINDOW_WIDTH, WINDOW_HEIGHT,
        {.RESIZABLE},
        &appState.window, &appState.renderer,
    ); assert(ok, "Failed to create window and renderer")
    ok = SDL.SetWindowMinimumSize(appState.window, GAME_WIDTH, GAME_HEIGHT); assert(ok, "Failed to set window min size")

    appState.running = true

    rawAppState^ = appState

    return .CONTINUE
}

AppEvent: SDL.AppEvent_func : proc "c" (rawAppState: rawptr, event: ^SDL.Event) -> SDL.AppResult {
    context = GlobalContext
    appState := cast(^AppState)rawAppState

    if event.type == .QUIT {
        appState.running = false
    }

    return .CONTINUE
}

AppIterate: SDL.AppIterate_func : proc "c" (rawAppState: rawptr) -> SDL.AppResult {
    context = GlobalContext
    appState := cast(^AppState)rawAppState

    if !appState.running do return .SUCCESS

    // =========================================
    // TODO: Put (call to) gameplay code here ||
    // =========================================
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

    // =======================
    // NOTE: Rendering code ||
    // =======================
    windowSize := PxPos{}
    SDL.GetWindowSize(appState.window, cast(^c.int)&windowSize.x, cast(^c.int)&windowSize.y)

    // Pixel color order is reversed because of endianness and historycal stuff (that's why ABRG instead if RGBA)
    buffer := SDL.CreateTexture(appState.renderer, .ABGR8888, .STREAMING, c.int(windowSize.x), c.int(windowSize.y)); assert(buffer != nil, "Failed to create frame buffer texture")
    defer SDL.DestroyTexture(buffer)

    // Set buffer/pixels in it to be drawn
    {
        pixels: [^]Pixel
        pitch: c.int
        SDL.LockTexture(buffer, nil, cast(^rawptr)(&pixels), &pitch); assert(pixels != nil, "Failed to lock texture")
        defer SDL.UnlockTexture(buffer)

        scaler := min(windowSize.x/GAME_WIDTH, windowSize.y/GAME_HEIGHT)
        gameAreaSize := PxPos{ GAME_WIDTH, GAME_HEIGHT } * scaler
        xDiff := windowSize.x - gameAreaSize.x
        yDiff := windowSize.y - gameAreaSize.y


        for y in 0..<windowSize.y {
            for x in 0..<windowSize.x {
                color: Pixel

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
                    // • y * GAME_WIDTH + x
                    // When we add the black-border-offset to the mix, it will be:
                    // • (y-yDiff/2) GAME_WIDTH + x
                    // When we add scaling to the mix, it will STILL use the original GAME_WIDTH, and scale down the indexing:
                    // • ((y-yDiff/2)/scaler)*GAME_WIDTH + ((x-xDiff/2)/scaler)
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

    // Render all the pixels put into the buffer texture:
    SDL.RenderClear(appState.renderer)
    SDL.RenderTexture(appState.renderer, buffer, nil, nil)
    SDL.RenderPresent(appState.renderer)
    SDL.Delay(16)

    return .CONTINUE
}

AppQuit: SDL.AppQuit_func : proc "c" (appstate: rawptr, result: SDL.AppResult) {
    context = GlobalContext

    fmt.println("Application exited with:", result)
}


main :: proc() {
    argc := cast(i32)len(runtime.args__);
    argv := raw_data(runtime.args__);

    SDL.EnterAppMainCallbacks(argc, argv, AppInit, AppIterate, AppEvent, AppQuit);
}
