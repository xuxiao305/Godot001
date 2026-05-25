# 概述：Rapier 是什么？

## 本章要解决什么问题

在开始写代码之前，你需要回答三个问题：
1. Rapier 是什么？它和 Godot 内置物理有什么不同？
2. 如何在项目中启用 Rapier？
3. 什么时候应该选 Rapier，什么时候选 godot-box2d？

---

## Rapier 简介

**Rapier** 是一个用 Rust 语言编写的开源物理引擎。它通过 GDExtension 机制被集成到 Godot 中，成为 Godot PhysicsServer2D 的一个可选后端。

你可以这样理解物理引擎在 Godot 中的位置：

```
你的游戏场景（RigidBody2D, CollisionShape2D, ...）
              |
     PhysicsServer2D（Godot 内置接口）
              |
     /--------+--------\
     |                 |
godot-box2d       godot-rapier
(Box2D 后端)      (Rapier 后端)
```

Godot 的场景节点（如 `RigidBody2D`、`CharacterBody2D`）不直接调用物理引擎，而是通过 `PhysicsServer2D` 这个中间接口。两个后端都实现了同样的接口，所以从场景节点的角度看，使用哪个后端 **写法完全一致**。

### 类比：打印机驱动

就像你的电脑可以通过不同驱动连接惠普或佳能打印机 -- 打印文档的操作一样，但内部原理和打印质量不同。Rapier 和 Box2D 就是两台不同的"物理打印机"。

---

## 如何启用 Rapier

### 1. 安装插件

从 Asset Library 或 GitHub Release 下载 `godot-rapier-physics` 插件，放入项目的 `addons/` 目录。

### 2. 在项目设置中切换

打开 `项目设置 > 通用 > 物理 > 2D`：

```
physics/2d/solver = "Rapier2D"
```

在 Godot 编辑器的项目设置搜索框中输入 `solver`，将 "Physics 2D Solver" 从默认的 "Box2D" 改为 "Rapier2D"。

### 3. 重启编辑器

切换物理后端后，**建议重启 Godot 编辑器**，确保所有场景重新加载并使用新的物理后端初始化。

### 4. 验证

在场景中添加一个 `RigidBody2D` 和一个 `StaticBody2D` 地板，运行游戏。如果物体正常下落，说明 Rapier 已成功启用。

---

## 为什么这个项目选择 Rapier

### 1. 流体模拟

Rapier 是唯一支持 **粒子流体（SPH Fluid）** 的 Godot 2D 物理后端。如果你的游戏需要水、熔岩、沙粒等效果，Rapier 是唯一选择。

> 详细见 [03-fluids.md](03-fluids.md)

### 2. 更现代的约束系统

Rapier 的关节（Joint）系统支持位置马达（Position Motor）-- 可以直接控制关节转到的目标角度，而不仅仅是维持速度。这对机器人手臂、摆锤之类需要精确角度控制的场景非常重要。

> 详细见 [02-joints.md](02-joints.md)

### 3. 活跃的开源社区

Rapier 由 Dimforge 组织维护，是 Rust 生态中最活跃的物理引擎之一。持续有性能优化和 bug 修复。

---

## Rapier vs godot-box2d 能力对比

| 能力 | godot-box2d | godot-rapier |
|------|-------------|--------------|
| RigidBody2D (Static/Kinematic/Dynamic) | 支持 | 支持 |
| CharacterBody2D | 支持 | 支持 |
| Area2D | 支持 | 支持 |
| PinJoint2D | **不支持**（仅有图标） | 支持 |
| DampedSpringJoint2D | 支持 | 支持 |
| GrooveJoint2D | 支持 | 支持 |
| 流体（Fluid2D） | 不支持 | **支持** |
| CCD（连续碰撞检测） | 支持 | 支持 |
| 空间查询（RayCast 等） | 支持 | 支持 |

> 注：godot-box2d 虽然提供 WeldJoint2D、RopeJoint2D 等节点图标，但这些是 PhysicsServer2D 后端实现。godot-box2d 未注册这些关节类，因此无法使用。详见项目 memory 中的 [godot-box2d 关节记录](godot_box2d_mouse_joint_missing.md)。

---

## PhysicsServer2D 后端模式说明

理解一个关键概念：**你在编辑器中放置的节点（如 RigidBody2D）不直接控制物理引擎**。它们只是 Godot 场景系统的一部分。当游戏运行时：

1. 场景节点（如 RigidBody2D）通过 `PhysicsServer2D` 向当前激活的物理后端发送命令
2. 物理后端（Rapier 或 Box2D）执行真实的物理计算
3. 计算结果通过 `PhysicsServer2D` 回传给场景节点，更新位置、速度等

这意味着：
- 你可以随时在两个后端之间切换，**不需要修改任何场景节点**
- 两个后端的行为可能略有差异（如碰撞检测的精度、关节参数的敏感度）

---

## 延伸阅读

- [Rapier 官方文档](https://rapier.rs/docs/)
- [godot-rapier-physics GitHub](https://github.com/godot-rapier-physics)
- [godot-box2d GitHub](https://github.com/appsinacup/godot-box2d)
- 本指南下一章：[01-rigid-body.md](01-rigid-body.md)
