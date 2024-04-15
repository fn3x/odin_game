package main

import "core:fmt"
import "core:math/linalg"
import SDL "vendor:sdl2"

WINDOW_WIDTH :: 1024
WINDOW_HEIGHT :: 960
WINDOW_FLAGS :: SDL.WINDOW_SHOWN | SDL.WINDOW_RESIZABLE
RENDER_FLAGS :: SDL.RENDERER_ACCELERATED

GRAVITY :: 1
JUMP_MULTIPLIER :: 3
JUMP_COUNTER :: 150
VELOCITY_GAIN :: 1

Game :: struct {
	renderer:             ^SDL.Renderer,
	time:                 f64,
	dt:                   f64,
	keyboard:             []u8,
	jump_button_released: bool,
	entities:             [dynamic]Entity,
}

EntityType :: enum {
	PLAYER,
}

Entity :: struct {
	type:         EntityType,
	pos:          [2]f32,
	vel:          [2]f32,
	jumping:      bool,
	grounded:     bool,
	jump_counter: f32,
}

render_entity :: proc(entity: ^Entity, game: ^Game) {
	switch entity.type {
	case .PLAYER:
		SDL.SetRenderDrawColor(game.renderer, 255, 0, 255, 0)
		SDL.RenderDrawRectF(
			game.renderer,
			&SDL.FRect{x = entity.pos.x, y = entity.pos.y, w = 50, h = 50},
		)
	}
}

update_entity :: proc(entity: ^Entity, game: ^Game) {
	dt := f32(game.dt)

	switch entity.type {
	case .PLAYER:
		can_jump := !entity.jumping && entity.grounded && game.jump_button_released
		jump_pressed :=
			b8(game.keyboard[SDL.SCANCODE_W]) |
			b8(game.keyboard[SDL.SCANCODE_UP]) |
			b8(game.keyboard[SDL.SCANCODE_SPACE])

		if can_jump && jump_pressed && entity.jump_counter == 0 {
			entity.jumping = true
			entity.vel.y = -JUMP_MULTIPLIER
			entity.jump_counter += JUMP_COUNTER
		} else {
			entity.jump_counter = max(entity.jump_counter - dt, 0)
		}

		if entity.jump_counter == 0 {
			entity.vel.y += GRAVITY
		}

		dir: f32 = 0.0
		if b8(game.keyboard[SDL.SCANCODE_D]) | b8(game.keyboard[SDL.SCANCODE_RIGHT]) {
			dir += 1
		}

		if b8(game.keyboard[SDL.SCANCODE_A]) | b8(game.keyboard[SDL.SCANCODE_LEFT]) {
			dir -= 1
		}

		entity.pos.x += dir * VELOCITY_GAIN * dt
		entity.pos.y += entity.vel.y * dt

		entity.pos.x = clamp(entity.pos.x, 0, WINDOW_WIDTH - 50)
		entity.pos.y = clamp(entity.pos.y, 0, WINDOW_HEIGHT - 50)

		if entity.pos.y >= WINDOW_HEIGHT - 50 {
			entity.grounded = true
		} else {
			entity.grounded = false
		}
	}
}

// Find first occurence of entity in game
find_entity :: proc(type: EntityType, game: ^Game) -> ^Entity {
	for _, i in game.entities {
		if game.entities[i].type == type {
			return &game.entities[i]
		}
	}

	return nil
}

get_time :: proc() -> f64 {
	return f64(SDL.GetPerformanceCounter()) * 1000 / f64(SDL.GetPerformanceFrequency())
}

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

	tickrate := 144.0
	ticktime := 1000.0 / tickrate

	dt := 0.0

	game := Game {
		renderer             = SDL.CreateRenderer(window, -1, RENDER_FLAGS),
		time                 = get_time(),
		dt                   = ticktime,
		jump_button_released = true,
	}

	defer {
		fmt.println("Deleting game entities..")
		delete(game.entities)
		fmt.println("Deleting game keyboard..")
		delete(game.keyboard)
	}

	assert(game.renderer != nil, SDL.GetErrorString())
	defer {
		fmt.println("Destroying renderer..")
		SDL.DestroyRenderer(game.renderer)
	}

	append(
		&game.entities,
		Entity{type = .PLAYER, pos = {0, 0}, vel = {0, 0}, jumping = false, grounded = false},
	)

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

		time := get_time()
		dt += time - game.time

		game.keyboard = SDL.GetKeyboardStateAsSlice()
		game.time = time

		// Running on the same thread as rendering so in the end still limited by the rendering FPS
		for dt >= ticktime {
			dt -= ticktime

			for _, i in game.entities {
				update_entity(&game.entities[i], &game)
			}
		}

		SDL.SetRenderDrawColor(game.renderer, 0, 0, 0, 0)
		SDL.RenderClear(game.renderer)

		for _, i in game.entities {
			render_entity(&game.entities[i], &game)
		}

		SDL.RenderPresent(game.renderer)
	}
}
