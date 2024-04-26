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

GROUND_HEIGHT :: 100

PLAYER_HEIGHT :: 100
PLAYER_WIDTH :: 100

WALL_HEIGHT :: WINDOW_HEIGHT
WALL_WIDTH :: 400

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
	blocks:   [dynamic]Block,
	collisions: [][]bool 
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
	can_jump:          bool,
	dir:               f32,
	prev_dir:          f32,
	prev_pos:          [2]f32,
	pos:               [2]f32,
	prev_vel:          [2]f32,
	vel:               [2]f32,
	grounded:          bool,
	facing:            i32,
	side_left:		   f32,
	side_right:	       f32,
	side_top:	       f32,
	side_bottom:	   f32,
}

BlockType :: enum {
	WALL,
}

Block :: struct {
	type:    BlockType,
	x, y:    f32,
	w, h:    f32,
	texture: ^SDL.Texture,
	side_left:		   f32,
	side_right:	       f32,
	side_top:	       f32,
	side_bottom:	   f32,
}

render_entity :: proc(entity: ^Entity, game: ^Game) {
	switch entity.type {
	case .PLAYER:
		entity_rect := &SDL.FRect {
			x = entity.pos.x,
			y = entity.pos.y,
			w = PLAYER_WIDTH,
			h = PLAYER_HEIGHT,
		}
		texture: ^SDL.Texture

		if entity.facing == 1 {
			texture = entity.texture_right
		} else {
			texture = entity.texture_left
		}

		// Collision box
		entity.side_left = entity_rect.x
		entity.side_right = entity_rect.x + entity_rect.w
		entity.side_top = entity_rect.y
		entity.side_bottom = entity_rect.y + entity_rect.h

		SDL.SetRenderDrawColor(game.renderer, 255, 0, 255, 0)
		SDL.RenderCopyF(game.renderer, texture, nil, entity_rect)
	}
}

render_block :: proc(block: ^Block, game: ^Game) {
	switch block.type {
	case .WALL:
		wall_rect := &SDL.FRect{x = block.x, y = block.y, w = block.w, h = block.h}

		// Collision box
		block.side_left = wall_rect.x
		block.side_right = wall_rect.x + wall_rect.w
		block.side_top = wall_rect.y
		block.side_bottom = wall_rect.y + wall_rect.h

		SDL.SetRenderDrawColor(game.renderer, 255, 0, 255, 0)
		SDL.RenderCopyF(game.renderer, block.texture, nil, wall_rect)
	}
}

check_collision :: proc(entity_a: ^Entity, entity_b: ^Entity) -> b8 {
	// If any of the sides from A are otside of B
	if entity_a.side_bottom <= entity_b.side_top {
		return false;
	}

	if entity_a.side_top >= entity_b.side_bottom {
		return false;
	}

	if entity_a.side_right <= entity_b.side_left {
		return false;
	}

	if entity_a.side_left >= entity_b.side_right {
		return false;
	}

	// If none of the sides from A are outside B
	return true;
}

check_collision_block :: proc(entity: ^Entity, block: ^Block) -> b8 {
	// If any of the sides from A are otside of B
	if entity.side_bottom <= block.side_top {
		return false;
	}

	if entity.side_top >= block.side_bottom {
		return false;
	}

	if entity.side_right <= block.side_left {
		return false;
	}

	if entity.side_left >= block.side_right {
		return false;
	}

	// If none of the sides from A are outside B
	return true;
}

update_entity :: proc(entity: ^Entity, game: ^Game) {
	#partial switch entity.type {
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

	if !jump_pressed && entity.grounded {
		entity.can_jump = true
	}

	if !jump_pressed {
		entity.jumped = false
	}

	if jump_pressed {
		entity.jump_pressed_time += game.dt
	} else {
		entity.jump_pressed_time = 0
	}

	if !entity.jumped &&
	   entity.can_jump &&
	   entity.grounded &&
	   jump_pressed &&
	   entity.state != .JUMPING {
		entity.vel.y = JUMP_SPEED
		entity.state = .JUMPING
		entity.jumped = true
		entity.can_jump = false
	}

	if entity.jumped &&
	   entity.state == .JUMPING &&
	   entity.jump_pressed_time > MIN_JUMP_TIME_THRESHOLD &&
	   entity.jump_pressed_time < MAX_JUMP_TIME_THRESHOLD {
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

	entity.pos.x = clamp(entity.pos.x, 0, WINDOW_WIDTH - PLAYER_WIDTH)
	entity.pos.y = clamp(entity.pos.y, 0, WINDOW_HEIGHT - GROUND_HEIGHT - PLAYER_HEIGHT)

	if entity.pos.y >= WINDOW_HEIGHT - GROUND_HEIGHT - PLAYER_HEIGHT {
		entity.grounded = true
	} else {
		entity.grounded = false
	}

	if entity.vel.x > 0 && entity.grounded {
		entity.state = .WALKING
	} else if entity.vel.x == 0 && entity.grounded {
		entity.state = .STANDING
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

	tickrate := 240.0
	ticktime := 1000.0 / tickrate

	dt := 0.0

	game := Game {
		renderer = SDL.CreateRenderer(window, -1, RENDER_FLAGS),
		time     = get_time(),
		dt       = ticktime,
	}

	defer {
		fmt.println("Clearing game entities..")
		clear(&game.entities)
    fmt.println("Clearing game blocks..")
    clear(&game.blocks)
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

	wall := SDL_IMG.LoadTexture(game.renderer, "assets/images/wall.png")
	assert(wall != nil, string(SDL_IMG.GetError()))
	defer {
		fmt.println("Destroying wall texture..")
		SDL.DestroyTexture(wall)
	}

	append(
		&game.entities,
		Entity {
			type = .PLAYER,
			texture_right = texture_right,
			texture_left = texture_left,
			facing = 1,
		},
	)

	append(
		&game.blocks,
		Block {
			type = .WALL,
			texture = wall,
			x = WINDOW_WIDTH - WALL_WIDTH,
			y = 0,
			w = WALL_WIDTH,
			h = WALL_HEIGHT,
		},
	)

	wall_rect := &SDL.FRect{x = WINDOW_WIDTH - WALL_WIDTH, y = 0, w = WALL_WIDTH, h = WALL_HEIGHT}

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

				for j := i + 1; j < len(game.entities); j += 1 {
					check_collision(&game.entities[i], &game.entities[j])
				}

        for _, k in game.blocks {
          check_collision_block(&game.entities[i], &game.blocks[k])
        }
			}
		}

		SDL.RenderCopy(game.renderer, background, nil, nil)

		for _, i in game.entities {
			render_entity(&game.entities[i], &game)
		}

		for _, i in game.blocks {
			render_block(&game.blocks[i], &game)
		}

		SDL.RenderPresent(game.renderer)
		SDL.RenderClear(game.renderer)
	}
}
