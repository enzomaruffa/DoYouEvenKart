# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

DoYouEvenKart is a simple kart racing game built with Godot 4.2.

## Running the Game

- Open the project in Godot Engine
- Press F5 or click the Play button to run the game
- Main scene: res://scenes/track_1.tscn

## Code Style

- Class names: PascalCase (RaceLine, GameManager)
- Variables: snake_case (race_line, player_laps)
- Constants: SCREAMING_SNAKE_CASE (MAX_SPEED, FRICTION)
- Functions: snake_case (start_race, handle_collision)
- Private functions: Prefixed with underscore (_ready, _physics_process)
- Node names: PascalCase
- Use @export for editor-exposed properties
- Use @onready for variables initialized at _ready
- Declare signals at the top of the class
- Connect signals with function naming pattern _on_signal_name
- Comments: Use # for single-line comments

## Project Structure

- Components organized by functionality in /components
- Main scenes in /scenes directory
- Utility scripts in /utils directory
- Scene files (.tscn) with corresponding script files (.gd)

## Game Architecture

- Car physics handled in car_controller.gd
- Track built from track segments (track_segment.gd)
- Race line controls checkpoints and lap tracking
- GameManager tracks race state and player progress

## Commit Guidelines

- Follow conventional commits format
- Types: feat, fix, docs, style, refactor, perf, test, chore
- Example: feat: Add new power-up system