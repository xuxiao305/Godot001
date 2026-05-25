# 流体（Fluid2D）

## 本章要解决什么问题

你想在游戏中制作以下效果：
- 一桶水倾倒后流淌
- 角色穿过岩浆受伤
- 水流推动物体
- 沙粒堆积成小山丘

这些都是**流体模拟**的典型需求。Rapier 是唯一通过 `Fluid2D` 节点支持 2D 粒子流体模拟的 Godot 物理后端。

```
类比：流体模拟就像用成千上万个小珠子（粒子）来表示水。
每个珠子都很小，但合在一起，它们的行为就和真实液体非常相似。
```

---

## 基本概念

### SPH（Smoothed Particle Hydrodynamics）

Rapier 的流体使用 SPH 方法（平滑粒子流体动力学）。简单来说：

1. 液体被表示为一群粒子（particles）
2. 每个粒子携带位置、速度等信息
3. 粒子之间通过平滑核函数（Smoothing Kernel）相互影响
4. 当粒子靠得太近时，产生排斥力（类似不可压缩性）；太远时无影响

```
类比：想象一群人在房间里。每个人都有一个"私人空间泡泡"。
当两个人靠得太近时，私人空间重叠，两人都会不舒服并退开。
这大致就是 SPH 粒子之间压力的工作方式。
```

### Fluid2D 节点的角色

`Fluid2D` 是一个 `Node2D` 节点，它管理一群流体粒子。每个 `Fluid2D` 节点代表一"团"流体（如一滩水、一条熔岩流）。

---

## Fluid2D 基础配置

### 创建粒子

`Fluid2D` 提供了两种便捷方法来生成初始粒子布局：

```gdscript
# 创建矩形布局的粒子（宽 10 格，高 5 格）
var points = $Fluid2D.create_rectangle_points(10, 5)
$Fluid2D.set_points(points)

# 创建圆形布局的粒子（半径 8 格）
var points = $Fluid2D.create_circle_points(8)
$Fluid2D.set_points(points)
```

粒子的间距由 `radius` 属性决定（默认读取项目设置 `fluid_particle_radius`）。

### 核心属性

| 属性 | 默认值 | 含义 |
|------|--------|------|
| `radius` | 从项目设置读取 | 单个粒子的碰撞半径。决定了粒子的间距 |
| `density` | 1.0 | 流体的密度。影响流体与刚体碰撞时的行为 |
| `lifetime` | 0.0 | 粒子存活时间（秒）。0 = 永久存活。超时的粒子自动删除 |
| `debug_draw` | false | 是否在编辑器和运行时可视化显示粒子位置 |

### 碰撞层/掩码

`Fluid2D` 支持独立的碰撞层（`collision_layer`）和碰撞掩码（`collision_mask`）：

- `collision_layer`：流体粒子"属于"哪些层
- `collision_mask`：流体粒子会和哪些层的物体交互

默认值都是 1（第一层）。通过设置碰撞掩码，你可以让某团流体只与特定物体交互。

```gdscript
# 让流体只与第 2 层的物体交互
$Fluid2D.set_collision_mask(2)
```

### 运行时操作粒子

```gdscript
# 批量设置位置和速度
$Fluid2D.set_points_and_velocities(positions, velocities)

# 动态添加新粒子
$Fluid2D.add_points_and_velocities(new_positions, new_velocities)

# 删除指定索引的粒子
$Fluid2D.delete_points([0, 5, 10])

# 获取当前所有粒子位置
var current_points = $Fluid2D.get_points()

# 获取当前所有粒子速度
var current_velocities = $Fluid2D.get_velocities()

# 获取当前所有粒子加速度
var current_accels = $Fluid2D.get_accelerations()
```

### 获取剩余存活时间

```gdscript
# 用于绘制 alpha 渐变，让粒子随时间淡出
var remaining = $Fluid2D.get_remaining_times()
for i in range(remaining.size()):
    var alpha = remaining[i] / $Fluid2D.lifetime
    draw_particle(points[i], alpha)
```

### 空间查询

你可以在流体内部做空间物理查询：

```gdscript
# 获取矩形区域内的粒子索引
var indices = $Fluid2D.get_particles_in_aabb(Rect2(0, 0, 100, 100))

# 获取圆形区域内的粒子索引
var indices = $Fluid2D.get_particles_in_circle(Vector2(50, 50), 30.0)
```

---

## 流体效果（Fluid Effects）

`Fluid2D` 支持叠加多种物理效果（effects）数组。每种效果都是一个 `Resource` 类型的子类。你可以在编辑器中为 `Fluid2D` 添加和组合任意数量、任意类型的效果。

**注意**：效果在编辑器模式下不会应用（`is_editor_hint()` 检查），只在运行时生效。这避免了场景加载期间的绑定崩溃。

### Elasticity（弹性）

控制碰撞发生时粒子的软硬程度。有两个实现完全相同的版本（2D 和 3D）。

| 属性 | 默认值 | 含义 |
|------|--------|------|
| `young_modulus` | 100.0 | 杨氏模量 -- 材料的刚度。值越大粒子越硬（更难压缩） |
| `poisson_ratio` | 0.3 | 泊松比 -- 材料被压缩时的横向膨胀程度 |
| `nonlinear_strain` | true | 是否使用非线性应变（Nonlinear Strain）。开启后大变形时更真实 |

```
类比：young_modulus = 橡皮的硬度。
高值 = 乒乓球（硬，几乎不压缩），
低值 = 海绵（软，轻松压缩）。
```

### Surface Tension（表面张力）

表面张力让粒子互相凝聚，形成圆润的水滴形状，防止粒子散开。

Rapier 提供三种表面张力算法：

| 算法 | Resource 类型 | 特点 |
|------|---------------|------|
| AKINCI | `FluidEffectSurfaceTensionAKINCI` | 经典实现，效果均衡 |
| HE | `FluidEffectSurfaceTensionHE` | He 等人的改进算法 |
| WCSPH | `FluidEffectSurfaceTensionWCSPH` | 基于弱可压缩 SPH 的方法 |

所有三种算法共享相同的参数：

| 属性 | 默认值 | 含义 |
|------|--------|------|
| `fluid_tension_coefficient` | 1.0 | 粒子之间的凝聚力。值越大，粒子越倾向于聚在一起 |
| `boundary_adhesion_coefficient` | 0.0 | 粒子与边界（墙壁）的附着力。值越大，粒子越容易粘在墙上 |

**如何选择**：从 AKINCI 开始。它是经典实现，效果均衡，适合大多数流体效果。如果 AKINCI 产生的水滴形状不满足需求，再尝试 HE 或 WCSPH。

```
类比：fluid_tension_coefficient 决定水滴是"圆圆的一团"
还是"散开的一滩"。boundary_adhesion 决定水滴是"滚过叶子"
还是"粘在玻璃上"。
```

### Viscosity（粘滞性）

粘滞性控制流体内部的"阻力"。不同的粘滞性值可以让流体表现得像水（低粘滞性）或蜂蜜（高粘滞性）。

Rapier 提供三种粘滞性算法：

| 算法 | Resource 类型 | 参数 |
|------|---------------|------|
| Artificial | `FluidEffectViscosityArtificial` | `fluid_viscosity_coefficient`（默认 200.0）、`boundary_adhesion_coefficient` |
| DFSPH | `FluidEffectViscosityDFSPH` | `fluid_viscosity_coefficient`（默认 1.0）|
| XSPH | `FluidEffectViscosityXSPH` | `fluid_viscosity_coefficient`、`boundary_adhesion_coefficient` |

**如何选择**：从 Artificial 开始。它实现简单、性能好，适合大多数游戏场景。DFSPH 精度更高但开销也更大，适合对流体真实性要求高的模拟。XSPH 是经典方法，介于两者之间。

```
类比：
- 低粘滞性 = 水 → 粒子流动快，互相穿过容易
- 中粘滞性 = 油 → 粒子流动但有些阻力
- 高粘滞性 = 蜂蜜 → 粒子黏在一起，流动极慢
```

### 效果叠加

你可以在 `effects` 数组中组合多种效果。例如，同时使用 Elasticity + Surface Tension + Viscosity 来模拟"粘稠的果冻液"：

```gdscript
var effects: Array = []
# 弹性
var elasticity = FluidEffect2DElasticity.new()
elasticity.young_modulus = 80.0
effects.append(elasticity)

# 表面张力
var surface = FluidEffect2DSurfaceTensionAKINCI.new()
surface.fluid_tension_coefficient = 2.0
effects.append(surface)

# 粘滞性
var viscosity = FluidEffect2DViscosityArtificial.new()
viscosity.fluid_viscosity_coefficient = 300.0
effects.append(viscosity)

$Fluid2D.set_effects(effects)
# 注意：在 _ready() 中只调用一次 set_effects()。
# 多次调用需要先释放旧的 effects 资源，避免内存泄漏。
```

### 效果选择速查

| 想要模拟的效果 | 推荐的效果组合 |
|---------------|---------------|
| 水（流动快、低粘性） | Viscosity (Artificial, 低系数) |
| 蜂蜜/糖浆（流动慢、高粘性） | Viscosity (Artificial, 高系数) |
| 水滴/水珠（圆润、凝聚） | Surface Tension (AKINCI) |
| 果冻/胶状物（弹性、有形变） | Elasticity + Surface Tension |
| 沙粒/粉末（堆积、不散开） | Elasticity (高 young_modulus) |
| 岩浆（粘稠、有表面张力） | Viscosity + Surface Tension |
| 粘稠果冻液（弹性+凝聚+粘性） | Elasticity + Surface Tension + Viscosity |

---

## 与刚体的交互

流体粒子会自动与场景中的 `RigidBody2D` 和 `StaticBody2D` 碰撞。碰撞行为由：
1. 流体的 `collision_mask`（流体能看到哪些物体）
2. 物体的 `collision_layer`（哪些层的物体能和流体交互）

共同决定。流体粒子碰撞刚体后会被推开，产生自然的"水溅到墙上"效果。

流体还能推动 Dynamic 物体。较大的密度值会让流体更有"力量"。

---

## 性能说明

### 粒子数量

每个粒子都需要被独立模拟，因此粒子数量直接影响性能：

- **< 500 粒子**：几乎所有硬件都能流畅运行
- **500-2000 粒子**：主流设备可以接受
- **> 2000 粒子**：需要关注性能，考虑简化效果或减少粒子数

### 优化建议

1. **用更少的粒子 + 更大的 radius**：减少粒子数，增大间距
2. **减少同时活跃的 Fluid2D 节点**：不要把水铺满整个关卡
3. **限制 lifetime**：让粒子定时消失，防止无限积累
4. **禁用不需要的效果**：每种效果都有性能开销
5. **使用 debug_draw** 仅在调试时开启，发布时关闭

---

## 延伸阅读

- [Rapier 官方文档：Fluids (Salva)](https://rapier.rs/docs/user_guides/2d/fluids)
- 参考：Salva（Rapier 的流体引擎）官方文档
- 本指南：[01-rigid-body.md](01-rigid-body.md) -- 流体与刚体的交互
- 本指南：[04-collision-shapes.md](04-collision-shapes.md) -- 碰撞形状也与流体粒子交互
- 本指南：[05-space-queries.md](05-space-queries.md) -- 在流体中进行空间查询
