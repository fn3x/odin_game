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

WALL_HEIGHT :: 200
WALL_WIDTH :: 200

GRAVITY :: 0.1
JUMP_SPEED :: 1.8
JUMP_ACCELERATION :: 0.1
MAX_JUMP_TIME_THRESHOLD :: 140
MIN_JUMP_TIME_THRESHOLD :: 10

VELOCITY_GAIN :: 1.0
STOPPING_SPEED_GROUND :: 0.05
STOPPING_SPEED_AIR :: 0.005

CollisionBox :: struct {
	x, y: f32,
	w, h: f32,
	draw: bool,
}

Collider :: union {
	^Entity,
	^Block,
}

CollisionSide :: enum {
	TOP,
	BOTTOM,
	LEFT,
	RIGHT,
}

Collision :: struct {
	collider:       Collider,
	other_collider: Collider,
	side:           CollisionSide,
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
	dir:               i8,
	prev_dir:          i8,
	prev_pos:          [2]f32,
	pos:               [2]f32,
	prev_vel:          [2]f32,
	vel:               [2]f32,
	grounded:          bool,
	facing:            u8,
	collision_box:     ^CollisionBox,
}

BlockType :: enum {
	WALL,
	GROUND,
}

Block :: struct {
	type:          BlockType,
	x, y:          f32,
	w, h:          f32,
	texture:       ^SDL.Texture,
	collision_box: ^CollisionBox,
}

Game :: struct {
	renderer: ^SDL.Renderer,
	time:     f64,
	dt:       f64,
	keyboard: []u8,
	entities: [dynamic]Entity,
	blocks:   [dynamic]Block,
}

render_entity :: proc(entity: ^Entity, game: ^Game) {
	switch entity.type {
	case .PLAYER:
		rect := &SDL.FRect{x = entity.pos.x, y = entity.pos.y, w = PLAYER_WIDTH, h = PLAYER_HEIGHT}
		texture: ^SDL.Texture

		if entity.facing == 1 {
			texture = entity.texture_right
		} else {
			texture = entity.texture_left
		}

		SDL.SetRenderDrawColor(game.renderer, 255, 0, 255, 0)
		SDL.RenderCopyF(game.renderer, texture, nil, rect)

		if entity.collision_box.draw {
			SDL.SetRenderDrawColor(game.renderer, 255, 255, 0, 255)
			SDL.RenderDrawRectF(
				game.renderer,
				&SDL.FRect {
					x = entity.collision_box.x,
					y = entity.collision_box.y,
					w = entity.collision_box.w,
					h = entity.collision_box.h,
				},
			)
		}
	}
}

render_block :: proc(block: ^Block, game: ^Game) {
	switch block.type {
	case .GROUND, .WALL:
		rect := &SDL.FRect{x = block.x, y = block.y, w = block.w, h = block.h}

		SDL.SetRenderDrawColor(game.renderer, 255, 0, 255, 0)
		SDL.RenderCopyF(game.renderer, block.texture, nil, rect)

		if block.collision_box.draw {
			SDL.SetRenderDrawColor(game.renderer, 255, 255, 0, 255)
			SDL.RenderDrawRectF(
				game.renderer,
				&SDL.FRect {
					x = block.collision_box.x,
					y = block.collision_box.y,
					w = block.collision_box.w,
					h = block.collision_box.h,
				},
			)
		}
	}
}

have_collided :: proc(entity_a: ^Entity, entity_b: ^Entity) -> bool {
	// TODO
	return false
}

has_collided :: proc(entity: ^Entity, block: ^Block) -> (Collision, bool) {
	collision := Collision{}
	switch block.type {
	case .WALL, .GROUND:
		if entity.collision_box.y + entity.collision_box.h < block.collision_box.y {
			return collision, false
		}

		collision.collider = entity
		collision.other_collider = block

		if entity.collision_box.y + entity.collision_box.h <= block.collision_box.y {
			collision.side = .BOTTOM
			return collision, true
		} else if entity.collision_box.y >= block.collision_box.y + block.collision_box.h {
			collision.side = .TOP
			return collision, true
		}

		if entity.collision_box.x + entity.collision_box.w < block.collision_box.x ||
		   entity.collision_box.x > block.collision_box.x + block.collision_box.w {
			return collision, false
		}

		if entity.collision_box.x + entity.collision_box.w >= block.collision_box.x {
			collision.side = .RIGHT
		} else if entity.collision_box.x <= block.collision_box.x + block.collision_box.w {
			collision.side = .LEFT
		}

		return collision, true
	}

	return collision, false
}

update_entity :: proc(entity: ^Entity, game: ^Game) {
	switch entity.type {
	case .PLAYER:
		entity.prev_pos = entity.pos
		entity.prev_vel = entity.vel
		entity.prev_dir = entity.dir

		apply_movement(entity, game)

		entity.collision_box.x = entity.pos.x
		entity.collision_box.y = entity.pos.y
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
		entity.grounded = false
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
		entity.facing = 0
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

	entity.pos.x += f32(entity.dir) * entity.vel.x * dt
	entity.pos.y -= entity.vel.y * dt

	entity.pos.x = clamp(entity.pos.x, 0, WINDOW_WIDTH - PLAYER_WIDTH)
	entity.pos.y = clamp(entity.pos.y, 0, WINDOW_HEIGHT - GROUND_HEIGHT - PLAYER_HEIGHT)

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

	tickrate := 244.0 // how many ticks per second
	ticktime := 1000.0 / tickrate // tick duration

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
			grounded = false,
			collision_box = &CollisionBox{w = PLAYER_WIDTH, h = PLAYER_HEIGHT, draw = true},
		},
	)

	append(
		&game.blocks,
		Block {
			type = .WALL,
			texture = wall,
			x = WINDOW_WIDTH - WALL_WIDTH,
			y = WINDOW_HEIGHT - 50 - WALL_HEIGHT,
			w = WALL_WIDTH,
			h = WALL_HEIGHT - 50,
			collision_box = &CollisionBox {
				x = WINDOW_WIDTH - WALL_WIDTH,
				y = WINDOW_HEIGHT - 50 - WALL_HEIGHT,
				w = WALL_WIDTH,
				h = WALL_HEIGHT - 50,
				draw = true,
			},
		},
		Block {
			type = .GROUND,
			texture = wall,
			x = 0,
			y = WINDOW_HEIGHT - 100,
			w = WINDOW_WIDTH,
			h = WALL_HEIGHT,
			collision_box = &CollisionBox {
				x = 0,
				y = WINDOW_HEIGHT - 100,
				w = WINDOW_WIDTH,
				h = WALL_HEIGHT,
				draw = true,
			},
		},
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

				for j := i + 1; j < len(game.entities); j += 1 {
					have_collided(&game.entities[i], &game.entities[j])
				}

				for _, k in game.blocks {
					if collision, ok := has_collided(&game.entities[i], &game.blocks[k]); ok {
						switch collision.side {
						case .BOTTOM:
							game.entities[i].grounded = true
							game.entities[i].pos.y = game.entities[i].prev_pos.y
						case .RIGHT, .LEFT, .TOP:
							game.entities[i].pos.x = game.entities[i].prev_pos.x
						}
					}
				}
			}
		}

		SDL.RenderCopy(game.renderer, background, nil, nil)

		for _, i in game.blocks {
			render_block(&game.blocks[i], &game)
		}

		for _, i in game.entities {
			render_entity(&game.entities[i], &game)
		}

		SDL.RenderPresent(game.renderer)
		SDL.RenderClear(game.renderer)
	}
}
