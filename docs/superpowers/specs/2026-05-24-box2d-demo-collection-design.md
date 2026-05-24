# Box2D Physics Demo Collection — Design Spec

**Date:** 2026-05-24
**Status:** Approved (Phase 1: Menu + RigidBody)

## Overview

A playable interactive demo collection showcasing Box2D's physics capabilities in
Godot 4.6. Each Box2D feature gets its own small level where the player can
directly interact with physics bodies via mouse drag.

The project builds on the existing 2D Platformer Starter Kit which already has
the godot-box2d GDExtension (v0.9.11) installed as the physics server.

## Architecture

### Scene organization

```
Scenes/Demos/
├── demo_menu.tscn              — Main menu, grid of demo buttons
├── demo_base.tscn              — Base scene with shared UI layout (optional template)
├── demo_rigid_body.tscn        — Phase 1: RigidBody properties
├── demo_weld_joint.tscn        — Phase 2+: future demos
├── demo_spring_joint.tscn
├── demo_rope_joint.tscn
├── demo_pulley_joint.tscn
├── demo_motor_joint.tscn
├── demo_wheel_joint.tscn
├── demo_gear_joint.tscn
└── demo_mouse_joint.tscn

Scripts/Demos/
├── demo_level.gd               — Base class for all demos
├── demo_menu.gd                — Menu scene logic
└── demo_rigid_body.gd          — RigidBody demo logic (Phase 1)
```

### Base class: `demo_level.gd` (extends Node2D)

Centralizes everything shared across demos so individual demos are thin.

**UI responsibilities (via CanvasLayer):**
- Title bar showing demo name + short description
- Back button (returns to menu)
- Prev/Next buttons (navigate between demos in order)

**Interaction responsibilities:**
- Mouse-click raycast to pick RigidBody2D objects
- On pick: dynamically create a MouseJoint2D, attach to the picked body
- On drag: update MouseJoint2D.target to mouse position
- On release: destroy the MouseJoint2D

**Exported variables:**

| Variable | Type | Purpose |
|----------|------|---------|
| `title` | String | Display name of the demo |
| `description` | String | One-line explanation of what's being shown |
| `demo_index` | int | Position in the demo sequence (for prev/next) |

**Scene structure contract (children expected in derived scenes):**
- `%TitleLabel` — Label node for title
- `%DescriptionLabel` — Label node for description

### Demo menu: `demo_menu.gd`

A grid of styled buttons. Each button maps to a demo scene path.
Clicking loads that scene. The list is a dictionary `{index: {name, path, description}}`
so adding a new demo is a one-line entry.

### Scene transition

Use `SceneTransition.load_scene()` (existing project pattern) to keep
the fade-in/fade-out transition consistent with the rest of the game.

## Phase 1 Deliverables

### 1. Base class (`demo_level.gd`)
- Mouse drag-to-pick and MouseJoint2D interaction
- Title/description display
- Back-to-menu button
- Prev/Next buttons (functional but will skip to placeholder for now)

### 2. Main menu (`demo_menu.tscn` + `demo_menu.gd`)
- Button for "RigidBody Physics"
- Button for "Weld Joint" (disabled/greyed, placeholder for future)
- Clean grid layout

### 3. RigidBody demo (`demo_rigid_body.tscn` + `demo_rigid_body.gd`)
- Static platforms: flat ground + angled slope
- At least 4 RigidBody2D objects with varied properties:
  - Heavy cube (high mass/density)
  - Light cube (low mass/density)
  - Bouncy ball (high bounce/elasticity)
  - Non-bouncy ball (low bounce/elasticity)
- Player can drag any of them with mouse
- Title: "RigidBody 物理属性"
- Description: "拖拽物体 — 体验不同质量、弹性和摩擦力的表现"

## Interaction Design

### Mouse drag flow

```
MouseButton press (left)
  → PhysicsRayQuery2D from screen position
  → Hit a RigidBody2D?
    Yes: create MouseJoint2D, set node_a (static anchor), node_b (body)
    No:  ignore
Mouse move (while joint exists)
  → Update joint.target to current mouse global position
MouseButton release
  → Destroy MouseJoint2D
```

### MouseJoint2D configuration

| Property | Value | Reason |
|----------|-------|--------|
| `stiffness` | 100.0 | Strong enough to feel responsive, not sticky |
| `damping` | 0.7 | Smooth follow without oscillation |
| `max_force` | 5000.0 | Can lift heavy bodies but not absurd weights |

## Future Demos (Phase 2+, not in this spec)

| # | Demo | Feature | Concept |
|---|------|---------|---------|
| 1 | — | Main Menu | |
| 2 | RigidBody | RigidBody2D props | Density, friction, restitution |
| 3 | WeldJoint | WeldJoint2D | Rigid compound bodies |
| 4 | DampedSpring | DampedSpringJoint2D | Spring suspension, oscillation |
| 5 | RopeJoint | RopeJoint2D | Pendulum, length constraints |
| 6 | PulleyJoint | PulleyJoint2D | Counterweight systems |
| 7 | MotorJoint | MotorJoint2D | Linear motor to target |
| 8 | WheelJoint | WheelJoint2D | Wheel with suspension |
| 9 | GearJoint | GearJoint2D | Coupled rotation |
| 10 | MouseJoint | MouseJoint2D | Drag elasticity, trailing |

## File Changes Summary (Phase 1)

| Action | File |
|--------|------|
| Create | `Scenes/Demos/demo_base.tscn` |
| Create | `Scenes/Demos/demo_menu.tscn` |
| Create | `Scenes/Demos/demo_rigid_body.tscn` |
| Create | `Scripts/Demos/demo_level.gd` |
| Create | `Scripts/Demos/demo_menu.gd` |
| Create | `Scripts/Demos/demo_rigid_body.gd` |
| Modify | `project.godot` (add main scene toggle or autoload for demo entry) |
