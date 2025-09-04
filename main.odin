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

// -------------------------------
// TODO: Move to GAME section:
Key :: enum {
    UP, DOWN, LEFT, RIGHT,
}

// State of the keys shall be checked at the start of each frame.
KeyState :: struct {
    isDown: bool,

    // Number of times, the given key went from up->down, or down->up
    // This field shall be reset to 0 at the start of the frame when the key-input is processed.
    transitionCount: u8,
}


KeyInput: [Key]KeyState = {}

// isDown          |  F  |  F  |  T  |  T  |
// ----------------+-----+-----+-----+-----+
// trans.Count % 2 |  F  |  T  |  F  |  T  |
// ----------------+-----+-----+-----+-----+
// ================ EXAMPLE ================
// key up          |xx   | xxx |   xx|x  xx|
// key down        |  xxx|x   x|xxx  | xx  |
// trans.Count     |0 1  |01  2|0  1 |01 2 |
// WasKeyDown      |  F  |  T  |  T  |  F  |
// Frame Count       <-1th <-2nd <-3rd <-4th
WasKeyDown :: proc(key: Key) -> bool {
    return (KeyInput[key].isDown != ((KeyInput[key].transitionCount % 2) == 0)) && KeyInput[key].transitionCount != 0
}

IsKeyDown :: proc(key: Key) -> bool {
    return KeyInput[key].isDown || KeyInput[key].transitionCount != 0
}
IsKeyPressed :: proc(key: Key) -> bool {
    return KeyInput[key].isDown
}
// -------------------------------

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

    #partial switch event.type {
    case .QUIT: {
        appState.running = false
    }
    case .KEY_DOWN: fallthrough
    case .KEY_UP: {
        switch event.key.key {
        case SDL.K_A:
            if (event.type == .KEY_DOWN) != KeyInput[.LEFT].isDown {
                KeyInput[.LEFT].transitionCount += 1
            }
            KeyInput[.LEFT].isDown = (event.type == .KEY_DOWN)

        case SDL.K_W:
            if (event.type == .KEY_DOWN) != KeyInput[.UP].isDown {
                KeyInput[.UP].transitionCount += 1
            }
            KeyInput[.UP].isDown = (event.type == .KEY_DOWN)
        case SDL.K_S:
            if (event.type == .KEY_DOWN) != KeyInput[.DOWN].isDown {
                KeyInput[.DOWN].transitionCount += 1
            }
            KeyInput[.DOWN].isDown = (event.type == .KEY_DOWN)
        case SDL.K_D:
            if (event.type == .KEY_DOWN) != KeyInput[.RIGHT].isDown {
                KeyInput[.RIGHT].transitionCount += 1
            }
            KeyInput[.RIGHT].isDown = (event.type == .KEY_DOWN)
        }
    }
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
    // Get keyboard state:
    //SavedKeyInput = KeyInput
    for &input in KeyInput do input.transitionCount = 0

    // Render
    gameScreen: [GAME_WIDTH * GAME_HEIGHT]Pixel
    for y in 0..<GAME_HEIGHT {
        for x in 0..<GAME_WIDTH {
            color := Pixel{}
            if KeyInput[.UP].isDown {
                color.r = u8(x % 0xFF)
                color.g = u8(y % 0xFF)
                color.a = 0xFF
            } else {
                color.r = u8(y % 0xFF)
                color.g = u8(x % 0xFF)
                color.a = 0xFF
            }

            if KeyInput[.LEFT].isDown {
                color.b = u8(int(f32(color.r)*0.25 + f32(color.g)*0.75) % 256)
            } else {
                color.b = u8(int(f32(color.r)*0.75 + f32(color.g)*0.25) % 256)
            }

                gameScreen[y*GAME_WIDTH + x] = color
        }
    }

    // Really bad way to feed audio (sin wave) to the audio device buffer thinggy
    // We try to keep feeding data to the buffer, as long as it has less than half a second's sample data
    // one second has spec.freq amount of samples that are f32
    minimumAudio := (appState.spec.freq * size_of(f32) / 2)
    if SDL.GetAudioStreamQueued(appState.stream) < minimumAudio {
        @static samples: [170]f32
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
    buffer := SDL.CreateTexture(appState.renderer, .ABGR8888, .STREAMING, GAME_WIDTH, GAME_HEIGHT); assert(buffer != nil, "Failed to create frame buffer texture")
    defer SDL.DestroyTexture(buffer)

    // Set buffer/pixels in it to be drawn
    {
        pixels: [^]Pixel
        pitch: c.int
        SDL.LockTexture(buffer, nil, cast(^rawptr)(&pixels), &pitch); assert(pixels != nil, "Failed to lock texture")
        defer SDL.UnlockTexture(buffer)

        for y in 0..<GAME_HEIGHT {
            for x in 0..<GAME_WIDTH {
                pixels[y * GAME_WIDTH + x] = gameScreen[y * GAME_WIDTH + x]
            }
        }
    }

    // Prepare target rectangle where the gameScreen will be located:
    scaler := min(windowSize.x/GAME_WIDTH, windowSize.y/GAME_HEIGHT)
    scaledWidth  := GAME_WIDTH * scaler
    scaledHeight := GAME_HEIGHT * scaler
    dstRect := SDL.FRect{
        f32(windowSize.x - scaledWidth)  / 2,
        f32(windowSize.y - scaledHeight) / 2,
        f32(scaledWidth), f32(scaledHeight),
    }

    // Render all the pixels put into the buffer texture:
    SDL.SetRenderDrawColor(appState.renderer, 0, 0, 0, 255)
    SDL.RenderClear(appState.renderer)
    SDL.RenderTexture(appState.renderer, buffer, nil, &dstRect)
    SDL.RenderPresent(appState.renderer)

    // Delay according to the current frame's time:
    frameTime: u64 = SDL.GetTicks() - frameStart
    frameDelay: u32 = 1000 / appState.framsPerSec
    if frameTime < u64(frameDelay) {
        SDL.Delay(frameDelay - u32(frameTime))
    } else {
        fmt.println("LONG FRAME!!", frameTime - u64(frameDelay), "ms longer")
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
