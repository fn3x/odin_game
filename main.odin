package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import SDL "vendor:sdl2"
import SDL_IMG "vendor:sdl2/image"

WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080
WINDOW_FLAGS :: SDL.WINDOW_SHOWN | SDL.WINDOW_RESIZABLE
RENDER_FLAGS :: SDL.RENDERER_ACCELERATED

GRAVITY :: 0.1
JUMP_SPEED :: 1.8
JUMP_ACCELERATION :: 0.1
MAX_JUMP_TIME_THRESHOLD :: 140
MIN_JUMP_TIME_THRESHOLD :: 10

VELOCITY_GAIN :: 1.0
STOPPING_SPEED_GROUND :: 0.05
STOPPING_SPEED_AIR :: 0.005

Game :: struct {
	renderer: ^SDL.Renderer,
	time:     f64,
	dt:       f64,
	keyboard: []u8,
	entities: [dynamic]Entity,
}

EntityState :: enum {
	STANDING,
	WALKING,
	JUMPING,
	FALLING,
}

EntityType :: enum {
	PLAYER,
}

Entity :: struct {
	type:              EntityType,
	state:             EntityState,
	texture_left:      ^SDL.Texture,
	texture_right:     ^SDL.Texture,
	jump_pressed_time: f64,
	jumped:            bool,
	dir:               f32,
	prev_dir:          f32,
	prev_pos:          [2]f32,
	pos:               [2]f32,
	prev_vel:          [2]f32,
	vel:               [2]f32,
	grounded:          bool,
	facing:            i32,
}

render_entity :: proc(entity: ^Entity, game: ^Game) {
	switch entity.type {
	case .PLAYER:
		entity_rect := &SDL.FRect{x = entity.pos.x, y = entity.pos.y, w = 50, h = 50}
    texture : ^SDL.Texture

    if entity.facing == 1 {
      texture = entity.texture_right
    } else {
      texture = entity.texture_left
    }

		SDL.SetRenderDrawColor(game.renderer, 255, 0, 255, 0)
		SDL.RenderCopyF(game.renderer, texture, nil, entity_rect)
	}
}

update_entity :: proc(entity: ^Entity, game: ^Game) {
	switch entity.type {
	case .PLAYER:
		entity.prev_pos = entity.pos
		entity.prev_vel = entity.vel
		entity.prev_dir = entity.dir

		apply_movement(entity, game)
	}
}

apply_movement :: proc(entity: ^Entity, game: ^Game) {
	dt := f32(game.dt)

	jump_pressed :=
		b8(game.keyboard[SDL.SCANCODE_W]) |
		b8(game.keyboard[SDL.SCANCODE_UP]) |
		b8(game.keyboard[SDL.SCANCODE_SPACE])

	if !jump_pressed {
		entity.jumped = false
	}

	if jump_pressed {
		entity.jump_pressed_time += game.dt
	} else {
		entity.jump_pressed_time = 0
	}

	if entity.grounded && jump_pressed && entity.state != .JUMPING {
		entity.vel.y = JUMP_SPEED
		entity.state = .JUMPING
		entity.jumped = true
	}

	if entity.jumped &&
	   entity.state == .JUMPING &&
	   entity.jump_pressed_time < MAX_JUMP_TIME_THRESHOLD &&
	   entity.jump_pressed_time > MIN_JUMP_TIME_THRESHOLD {
		entity.vel.y += JUMP_ACCELERATION
	}

	if !entity.grounded {
		entity.vel.y -= GRAVITY
	}

	entity.dir = 0.0
	if b8(game.keyboard[SDL.SCANCODE_D]) | b8(game.keyboard[SDL.SCANCODE_RIGHT]) {
		entity.dir = 1
		entity.facing = 1
	}

	if b8(game.keyboard[SDL.SCANCODE_A]) | b8(game.keyboard[SDL.SCANCODE_LEFT]) {
		entity.dir = -1
		entity.facing = -1
	}

	if entity.dir != 0.0 {
		entity.vel.x += VELOCITY_GAIN
	}

	if entity.prev_vel.x > 0.0 && entity.dir == 0.0 {
		entity.dir = entity.prev_dir

		if entity.grounded {
			entity.vel.x -= STOPPING_SPEED_GROUND
		} else { 	// in air
			entity.vel.x -= STOPPING_SPEED_AIR
		}
	}

	entity.vel.x = clamp(entity.vel.x, 0, VELOCITY_GAIN)

	entity.pos.x += entity.dir * entity.vel.x * dt
	entity.pos.y -= entity.vel.y * dt

	entity.pos.x = clamp(entity.pos.x, 0, WINDOW_WIDTH - 50)
	entity.pos.y = clamp(entity.pos.y, 0, WINDOW_HEIGHT - 50)

	if entity.pos.y >= WINDOW_HEIGHT - 50 {
		entity.grounded = true
	} else {
		entity.grounded = false
	}

	if entity.vel.x > 0 && entity.grounded {
		entity.state = .WALKING
	} else if entity.vel.x == 0 && entity.grounded {
		entity.state = .STANDING
	} else if entity.vel.y > 0 {
		entity.state = .JUMPING
	} else if entity.vel.y < 0 {
		entity.state = .FALLING
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

	tickrate := 128.0
	ticktime := 1000.0 / tickrate

	dt := 0.0

	game := Game {
		renderer = SDL.CreateRenderer(window, -1, RENDER_FLAGS),
		time     = get_time(),
		dt       = ticktime,
	}

	defer {
		fmt.println("Deleting game entities..")
		clear(&game.entities)
		fmt.println("Deleting game keyboard..")
		delete(game.keyboard)
	}

	assert(game.renderer != nil, SDL.GetErrorString())
	defer {
		fmt.println("Destroying renderer..")
		SDL.DestroyRenderer(game.renderer)
	}

	texture_right := SDL_IMG.LoadTexture(game.renderer, "assets/images/player-right.png")
	assert(texture_right != nil, string(SDL_IMG.GetError()))
	defer {
		fmt.println("Destroying player right texture..")
		SDL.DestroyTexture(texture_right)
	}

	texture_left := SDL_IMG.LoadTexture(game.renderer, "assets/images/player-left.png")
	assert(texture_left != nil, string(SDL_IMG.GetError()))
	defer {
		fmt.println("Destroying player left texture..")
		SDL.DestroyTexture(texture_left)
	}

	background := SDL_IMG.LoadTexture(game.renderer, "assets/images/background.png")
	assert(background != nil, string(SDL_IMG.GetError()))
	defer {
		fmt.println("Destroying background texture..")
		SDL.DestroyTexture(background)
	}

	append(&game.entities, Entity{type = .PLAYER, texture_right = texture_right, texture_left = texture_left, facing = 1})

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

		SDL.RenderCopy(game.renderer, background, nil, nil)

		for _, i in game.entities {
			render_entity(&game.entities[i], &game)
		}

		SDL.RenderPresent(game.renderer)
		SDL.RenderClear(game.renderer)
	}
}
