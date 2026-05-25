# Rapier 2D 物理开发指南

> 面向 Godot 用户的 Rapier 2D 物理引擎完整指南。

---

## 文档结构

本指南由 **三份文档** 组成，分别面向不同读者：

| 文档 | 路径 | 面向读者 |
|------|------|----------|
| **用户手册** | `01-user-manual/` | 所有人。从零开始学习 Rapier 物理概念和用法 |
| **桥接层参考** | `02-bridge/` | 进阶用户和插件开发者。了解 Godot 参数如何映射到 Rapier 数据结构 |
| **算法笔记** | `03-algorithm/` | 插件开发者。Rapier 内部算法实现细节（CCD、求解器、休眠等） |

---

## 用户手册章节导航

| 章节 | 标题 | 适合谁 |
|------|------|--------|
| [00-overview](01-user-manual/00-overview.md) | 概述：Rapier 是什么？ | 所有人必读。了解 Rapier 的基本概念和启用方法 |
| [01-rigid-body](01-user-manual/01-rigid-body.md) | 刚体（RigidBody2D） | 所有人必读。静态/运动学/动态刚体的核心概念 |
| [02-joints](01-user-manual/02-joints.md) | 关节（Joints） | 需要连接物体的开发者。PinJoint、弹簧、滑槽 |
| [03-fluids](01-user-manual/03-fluids.md) | 流体（Fluid2D） | 需要水、熔岩、气流的开发者。粒子流体模拟 |
| [04-collision-shapes](01-user-manual/04-collision-shapes.md) | 碰撞形状（CollisionShape2D） | 所有人必读。选择正确的碰撞形状 |
| [05-space-queries](01-user-manual/05-space-queries.md) | 空间查询（RayCast 等） | 需要射线检测、范围查询的开发者 |

---

## 如何开始

### 如果你是新手

从头顺序阅读：
1. [概述](01-user-manual/00-overview.md) -- 了解 Rapier 是什么，如何启用
2. [刚体](01-user-manual/01-rigid-body.md) -- 理解物体为什么会动
3. [碰撞形状](01-user-manual/04-collision-shapes.md) -- 给物体加上碰撞边界

### 如果你需要特定功能

直接跳到对应章节：
- 做平台跳跃？重点看 [刚体](01-user-manual/01-rigid-body.md) 和 [空间查询](01-user-manual/05-space-queries.md)
- 做物理机关？重点看 [关节](01-user-manual/02-joints.md)
- 做水/液体效果？重点看 [流体](01-user-manual/03-fluids.md)

### 如果你从 godot-box2d 迁移

godot-box2d 和 godot-rapier 都是 PhysicsServer2D 的后端实现，Godot 场景中的 RigidBody2D、CollisionShape2D 等节点用法完全一致。主要区别：
- Rapier 支持 **流体模拟**（Fluid2D 节点）
- Rapier 的关节系统更现代化，支持位置马达（motor_position_enabled）
- 内置关节类型不同：Rapier 直接支持 PinJoint、DampedSpringJoint、GrooveJoint

详细对比见 [概述](01-user-manual/00-overview.md)。

---

## 约定

- **语言**：描述和解释用中文；API 名称、属性名、枚举值用英文
- **术语标注**：关键术语首次出现时附带英文注解，如"刚体（RigidBody）"
- **代码示例**：仅展示关键参数映射，不包含完整实现
- **跨版本兼容**：本指南基于 godot-rapier-physics 2D 版本编写
