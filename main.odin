package platform

import "core:fmt"
import "core:c"
import "core:math"
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
    appContext: runtime.Context,

    framsPerSec: u32,

    // Rendering:
    window: ^SDL.Window,
    renderer: ^SDL.Renderer,

    // Audio:
    spec: SDL.AudioSpec,
    stream: ^SDL.AudioStream,

    // Event data:
    running: bool,
}

AppInit: SDL.AppInit_func : proc "c" (rawAppState: ^rawptr, argc: c.int, argv: [^]cstring) -> SDL.AppResult {
    context = runtime.default_context()

    appState := new(AppState); assert(appState != nil, "Failed to allocate appState")
    appState.appContext = context
    appState.framsPerSec = 60

    ok := SDL.Init({.VIDEO, .AUDIO}); assert(ok, "Failed to init SDL")

    ok = SDL.CreateWindowAndRenderer(
        "Buffer example with callbacks",
        WINDOW_WIDTH, WINDOW_HEIGHT,
        {.RESIZABLE},
        &appState.window, &appState.renderer,
    ); assert(ok, "Failed to create window and renderer")
    ok = SDL.SetWindowMinimumSize(appState.window, GAME_WIDTH, GAME_HEIGHT); assert(ok, "Failed to set window min size")

    appState.spec = {
        channels = 1,
        format = .F32,
        freq = 8000,
    }
    appState.stream = SDL.OpenAudioDeviceStream(SDL.AUDIO_DEVICE_DEFAULT_PLAYBACK, &appState.spec, nil, nil); assert(appState.stream != nil, "Failed to Open AudioDevice and Stream")
    SDL.ResumeAudioStreamDevice(appState.stream)

    appState.running = true

    rawAppState^ = appState

    return .CONTINUE
}

AppEvent: SDL.AppEvent_func : proc "c" (rawAppState: rawptr, event: ^SDL.Event) -> SDL.AppResult {
    appState := cast(^AppState)rawAppState
    context = appState.appContext

    if event.type == .QUIT {
        appState.running = false
    }

    return .CONTINUE
}

AppIterate: SDL.AppIterate_func : proc "c" (rawAppState: rawptr) -> SDL.AppResult {
    appState := cast(^AppState)rawAppState
    context = appState.appContext

    if !appState.running do return .SUCCESS

    frameStart: u64 = SDL.GetTicks()

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

    // Really bad way to feed audio (sin wave) to the audio device buffer thinggy
    // We try to keep feeding data to the buffer, as long as it has less than half a second's sample data
    // one second has spec.freq amount of samples that are f32
    minimumAudio := (appState.spec.freq * size_of(f32) / 2)
    if SDL.GetAudioStreamQueued(appState.stream) < minimumAudio {
        @static samples: [512]f32
        @static currentSinSample: u16

        for i in 0..<len(samples) {
            // sin wave data:
            freq := 440
            phase := f32(currentSinSample) * f32(freq) / f32(appState.spec.freq)
            samples[i] = math.sin(f32(phase * 2 * math.PI))

            currentSinSample += 1
        }

        currentSinSample %= u16(appState.spec.freq)

        SDL.PutAudioStreamData(appState.stream, cast(rawptr)(&samples[0]), size_of(samples))
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
                // TODO: When resizing, this couses ~vibration in the position of the game window. FIX IT
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

    frameTime: u64 = SDL.GetTicks() - frameStart
    frameDelay: u32 = 1000 / appState.framsPerSec
    fmt.println(frameDelay, frameTime)
    if frameTime < u64(frameDelay) {
        SDL.Delay(frameDelay - u32(frameTime))
    }

    return .CONTINUE
}

AppQuit: SDL.AppQuit_func : proc "c" (rawAppState: rawptr, result: SDL.AppResult) {
    appState := cast(^AppState)rawAppState
    context = appState.appContext

    fmt.println("Application exited with:", result)
}


main :: proc() {
    argc := cast(i32)len(runtime.args__);
    argv := raw_data(runtime.args__);

    SDL.EnterAppMainCallbacks(argc, argv, AppInit, AppIterate, AppEvent, AppQuit);
}
