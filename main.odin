package main

import "core:fmt"
import SDL "vendor:sdl2"

WINDOW_HEIGHT :: 960
WINDOW_WIDTH :: 1024
WINDOW_FLAGS :: SDL.WINDOW_SHOWN | SDL.WINDOW_RESIZABLE
RENDER_FLAGS :: SDL.RENDERER_ACCELERATED

Game :: struct {
	renderer: ^SDL.Renderer,
}

game := Game{}

main :: proc() {
	assert(SDL.Init(SDL.INIT_VIDEO) == 0, SDL.GetErrorString())
	defer {
		fmt.println("Quitting SDL..")
		SDL.Quit()
	}

	window := SDL.CreateWindow(
		"LFG",
		SDL.WINDOWPOS_CENTERED,
		SDL.WINDOWPOS_CENTERED,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		WINDOW_FLAGS,
	)
	assert(window != nil, SDL.GetErrorString())
	defer {
		fmt.println("Destroying window..")
		SDL.DestroyWindow(window)
	}

	game.renderer = SDL.CreateRenderer(window, -1, RENDER_FLAGS)
	assert(game.renderer != nil, SDL.GetErrorString())
	defer {
		fmt.println("Destroying renderer..")
		SDL.DestroyRenderer(game.renderer)
	}

	event := SDL.Event{}

	game_loop: for {
		if SDL.PollEvent(&event) {
			#partial switch event.type {
			case SDL.EventType.QUIT:
				break game_loop
			case SDL.EventType.KEYDOWN:
				if event.key.keysym.scancode == .ESCAPE {
					break game_loop
				}
			}
		}

    // ------------------------------------------------------
    // ----------------- RENDER SETUP START -----------------
    // Show renderer
		SDL.RenderPresent(game.renderer)
    // Set background color
		SDL.SetRenderDrawColor(game.renderer, 0, 0, 0, 100)
    // Clear renderer from previous scene
		SDL.RenderClear(game.renderer)
    // ------------------ RENDER SETUP END ------------------
    // ------------------------------------------------------

    // Place update code below this line

    // E.g. draw white line
		SDL.SetRenderDrawColor(game.renderer, 255, 255, 255, 100)
    SDL.RenderDrawLine(game.renderer, 0, 0, 300, 300)
	}
}
