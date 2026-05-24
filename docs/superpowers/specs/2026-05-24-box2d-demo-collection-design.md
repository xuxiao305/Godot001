# Box2D 物理 Demo 合集 — 设计规格说明

**日期:** 2026-05-24
**状态:** 已确认（Phase 1：主菜单 + 刚体）

## 概述

一个可交互的 Demo 合集，用于展示 Box2D 在 Godot 4.6 中的物理能力。
每个 Box2D 特性都有自己独立的小关卡，玩家可以通过鼠标拖拽直接
与物理物体进行交互。

项目基于现有的 2D Platformer Starter Kit，该工程已安装了
godot-box2d GDExtension（v0.9.11）作为物理引擎。

## 架构设计

### 场景组织结构

```
Scenes/Demos/
├── demo_menu.tscn              — 主菜单，Demo 按钮网格
├── demo_base.tscn              — 基础场景，共享 UI 布局（可选模板）
├── demo_rigid_body.tscn        — Phase 1：刚体物理属性
├── demo_weld_joint.tscn        — Phase 2+：焊接关节
├── demo_spring_joint.tscn      — Phase 2+：弹簧关节
├── demo_rope_joint.tscn        — Phase 2+：绳索关节
├── demo_pulley_joint.tscn      — Phase 2+：滑轮关节
├── demo_motor_joint.tscn       — Phase 2+：马达关节
├── demo_wheel_joint.tscn       — Phase 2+：轮子关节
├── demo_gear_joint.tscn        — Phase 2+：齿轮关节
└── demo_mouse_joint.tscn       — Phase 2+：鼠标关节

Scripts/Demos/
├── demo_level.gd               — 所有 Demo 的基类脚本
├── demo_menu.gd                — 主菜单脚本
└── demo_rigid_body.gd          — 刚体 Demo 脚本（Phase 1）
```

### 基类设计：`demo_level.gd`（继承 Node2D）

将所有 Demo 共用的逻辑集中到基类，使每个具体的 Demo 脚本尽可能精简。

**UI 职责（通过 CanvasLayer 实现）：**
- 标题栏：显示 Demo 名称和简短说明
- 返回按钮：回到主菜单
- 上一项/下一项按钮：按顺序在 Demo 之间导航

**交互职责：**
- 鼠标点击时通过物理射线检测拾取 RigidBody2D 物体
- 拾取时：动态创建 MouseJoint2D，连接到被拾取的物体
- 拖拽时：更新 MouseJoint2D 的目标点到鼠标位置
- 释放时：销毁 MouseJoint2D

**导出变量：**

| 变量名 | 类型 | 用途 |
|--------|------|------|
| `title` | String | Demo 的显示名称 |
| `description` | String | 单行说明，解释正在展示的内容 |
| `demo_index` | int | 在 Demo 序列中的序号（用于上一页/下一页导航） |

**场景结构约定（子场景需要提供的节点）：**
- `%TitleLabel` — 显示标题的 Label 节点
- `%DescriptionLabel` — 显示说明的 Label 节点

### 主菜单：`demo_menu.gd`

一个网格排列的按钮布局。每个按钮映射到一个 Demo 场景路径。
点击按钮加载对应场景。关卡列表使用字典结构 `{index: {name, path, description}}`，
新增 Demo 只需添加一行条目即可。

### 场景切换方式

复用项目中已有的 `SceneTransition.load_scene()` 方法，保持与游戏
其他部分一致的淡入淡出过渡效果。

## Phase 1 交付内容

### 1. 基类（`demo_level.gd`）
- 鼠标拖拽拾取 + MouseJoint2D 交互
- 标题/说明文字展示
- 返回主菜单按钮
- 上一项/下一项按钮（当前功能暂时跳转到占位符）

### 2. 主菜单（`demo_menu.tscn` + `demo_menu.gd`）
- "刚体物理" 按钮
- "焊接关节" 按钮（禁用/灰色，作为后续功能的占位符）
- 简洁的网格布局

### 3. 刚体 Demo（`demo_rigid_body.tscn` + `demo_rigid_body.gd`）
- 静态平台：平面地面 + 倾斜坡道
- 至少 4 个属性各异的 RigidBody2D 物体：
  - 重方块（高密度）
  - 轻方块（低密度）
  - 高弹性球（高弹力系数）
  - 低弹性球（低弹力系数）
- 玩家可以用鼠标拖拽任意物体
- 标题："RigidBody 物理属性"
- 说明："拖拽物体 — 体验不同质量、弹性和摩擦力的表现"

## 交互设计

### 鼠标拖拽流程

```
鼠标左键按下
  → 从屏幕坐标发出 PhysicsRayQuery2D
  → 是否击中 RigidBody2D？
    是: 创建 MouseJoint2D，设置 node_a（静态锚点），node_b（被拾取物体）
    否: 忽略
鼠标移动（关节已创建时）
  → 更新 joint.target 为当前鼠标的世界坐标
鼠标左键释放
  → 销毁 MouseJoint2D
```

### MouseJoint2D 参数配置

| 属性 | 值 | 说明 |
|------|-----|------|
| `stiffness` | 100.0 | 足够灵敏，不会感觉粘滞 |
| `damping` | 0.7 | 平滑跟随，不产生振荡 |
| `max_force` | 5000.0 | 能提起重物，但不会超出合理范围 |

## 后续 Demo（Phase 2+，不在本规格范围内）

| 序号 | Demo | Box2D 特性 | 演示概念 |
|------|------|-----------|---------|
| 1 | — | 主菜单 | |
| 2 | RigidBody | RigidBody2D 属性 | 密度、摩擦力、弹性 |
| 3 | WeldJoint | WeldJoint2D | 刚体复合物体 |
| 4 | DampedSpring | DampedSpringJoint2D | 弹簧悬挂、振荡 |
| 5 | RopeJoint | RopeJoint2D | 摆锤、长度约束 |
| 6 | PulleyJoint | PulleyJoint2D | 滑轮对重系统 |
| 7 | MotorJoint | MotorJoint2D | 线性马达 |
| 8 | WheelJoint | WheelJoint2D | 带悬挂的轮子 |
| 9 | GearJoint | GearJoint2D | 旋转联动 |
| 10 | MouseJoint | MouseJoint2D | 拖拽弹性、拖尾效果 |

## Phase 1 文件变更清单

| 操作 | 文件 |
|------|------|
| 新建 | `Scenes/Demos/demo_base.tscn` |
| 新建 | `Scenes/Demos/demo_menu.tscn` |
| 新建 | `Scenes/Demos/demo_rigid_body.tscn` |
| 新建 | `Scripts/Demos/demo_level.gd` |
| 新建 | `Scripts/Demos/demo_menu.gd` |
| 新建 | `Scripts/Demos/demo_rigid_body.gd` |
| 修改 | `project.godot`（添加 Demo 入口，如主场景切换或 autoload） |


## 附录：Phase 3 实施变更（2026-05-24）

inspection of `addons/godot-box2d/bin/libgodot-box2d.windows.template_release.x86_64.dll` 显示该 GDExtension 是 PhysicsServer2D backend only —— 它不注册任何 Joint 节点类。spec 中编号 3-10 的 Box2D 扩展 joint 全部**不可用**：WeldJoint2D / RopeJoint2D / PulleyJoint2D / MotorJoint2D / WheelJoint2D / GearJoint2D / MouseJoint2D 均为图标。

可用 joint 类只有 Godot 内置三个：`PinJoint2D` / `GrooveJoint2D` / `DampedSpringJoint2D`。

**Phase 3 已交付：**
- 7 MotorJoint → GrooveJoint2D + sin 推力模拟
- 8 WheelJoint → PinJoint2D（轮转） + DampedSpringJoint2D（弹簧悬挂） + 摆臂模拟
- 9 GearJoint → 2 PinJoint2D + 脚本 angular_velocity 耦合
- 10 MouseDrag → DemoLevel velocity-drag + DragVisualizer（无 joint）

**Phase 3 已跳过：**
- 6 PulleyJoint → 需要等长约束 joint，无可行的伪造方案，菜单按钮保持灰色

如未来 godot-box2d 升级到注册更多 joint 类，可重做以上 demos 用真正的 Box2D joint，并启用 Pulley demo。
