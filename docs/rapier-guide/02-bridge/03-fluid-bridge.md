# 03 -- 流体桥接 (Fluid Bridge)

本章讲解 Godot 的流体系统如何映射到 Salva（Rapier 的流体伴侣库）的粒子流体模拟。核心桥接代码位于 `src/rapier_wrapper/fluid.rs`。

## Salva 简介

Salva 是 Rapier 生态中的 SPH (Smoothed Particle Hydrodynamics) 流体模拟库。它与 Rapier 通过 `FluidsPipeline` 集成：

- **Rapier**：处理刚体动力学、碰撞检测
- **Salva**：处理流体粒子动力学、与 Rapier 碰撞体的耦合

在 `PhysicsWorld` 中，`FluidsPipeline` 与 `PhysicsObjects` 并列存在：

```rust
pub struct PhysicsWorld {
    pub physics_objects: PhysicsObjects,  // Rapier 刚体/碰撞/关节
    pub physics_pipeline: PhysicsPipeline,
    pub fluids_pipeline: FluidsPipeline,  // Salva 流体
}
```

## FluidsPipeline 初始化

在 `PhysicsWorld::new()` 中，`FluidsPipeline` 使用 WorldSettings 中的参数初始化：

```rust
fluids_pipeline: FluidsPipeline::new_with_boundary_coef(
    settings.particle_radius,     // 每个粒子的半径
    settings.smoothing_factor,    // SPH 核函数平滑因子
    settings.boundary_coef,       // 边界耦合系数
)
```

**SPH 内核半径** 通过 `particle_radius * smoothing_factor * 2.0` 计算得出，这决定了每个粒子影响范围的大小。

## 流体生命周期

```
fluid_create()
  |
  v
fluid_change_points() / fluid_add_points_and_velocities()
  |-- 粒子数组转换: Godot Vector[] -> salva::math::Vector[]
  |-- Salva LiquidWorld 中添加上下文粒子
  |
  v
fluid_add_effect_*()
  |-- 弹性 / 表面张力 / 粘度效果
  |
  v
每帧 step()
  |-- FluidsPipeline.step() 执行流体模拟
  |-- 与 Rapier collider_set 耦合 (碰撞)
  |-- 与 rigid_body_set 耦合 (浮力)
  |
  v
fluid_get_points() / fluid_get_velocities()
  |
  v
fluid_destroy()
```

## fluid_create 参数映射

| Godot 参数 | 桥梁层参数 | Salva 目标 | 说明 |
|---|---|---|---|
| `density` (float) | `density: Real` | `Fluid.density0` | 流体密度，影响浮力和压力计算 |
| `collision_layer` + `collision_mask` | `interaction_groups` | `Fluid.interaction_groups` | 粒子与碰撞体的交互组 |
| (从 FluidsPipeline 获取) | `particle_radius` | `Fluid::new(particle_radius)` | 每个粒子的物理半径 |

### fluid_create 代码

```rust
pub fn fluid_create(
    &mut self,
    world_handle: WorldHandle,
    density: Real,
    interaction_groups: InteractionGroups,
) -> HandleDouble {
    let particle_radius = physics_world.fluids_pipeline.liquid_world.particle_radius();
    let fluid = Fluid::new(Vec::new(), particle_radius, density, interaction_groups);
    fluid_handle_to_handle(
        physics_world.fluids_pipeline.liquid_world.add_fluid(fluid),
    )
}
```

注意 `particle_radius` 不是独立参数 -- 它从 `FluidsPipeline` 初始化时确定，对整个物理世界统一适用。

## 粒子数组转换

Godot 使用 `PackedVector2Array` 存储粒子位置，需要转换为 Salva 的 `salva::math::Vector<Real>`：

```rust
fn point_array_to_salva_vec(pixel_data: &[Vector]) -> Vec<salva::math::Vector<Real>> {
    pixel_data
        .iter()
        .map(|point| salva::math::Vector::new(point.x, point.y))
        .collect()
}
```

同样，`velocity_array_to_salva_vec()` 用于速度数组，`salva_vector_to_godot()` 用于反向转换。

## 粒子更新的两种模式

### 全量替换 (fluid_change_points / fluid_change_points_and_velocities)

用于重新设置所有粒子（如 Spawner 每帧发射新粒子）。实现方式：

```rust
// 1. 标记所有现有粒子在下个时间步删除
for i in 0..fluid.num_particles() {
    fluid.delete_particle_at_next_timestep(i);
}
// 2. 添加新粒子
fluid.add_particles(&points, Some(&velocity_points));
```

使用 `delete_particle_at_next_timestep` 而非直接移除，是为了保持内部网格 (grid) 的一致性 -- Salva 的网格结构在 step 之间需要稳定的索引。

### 增量添加 (fluid_add_points_and_velocities)

用于追加新粒子（如持续喷射）。直接调用 `fluid.add_particles()`。

### 增量删除 (fluid_delete_points)

按索引删除指定粒子：

```rust
for index in indices {
    if index >= 0 && (index as usize) < fluid.num_particles() {
        fluid.delete_particle_at_next_timestep(index as usize);
    }
}
```

## FluidEffect 类型映射

Godot 通过 `FluidEffect2D` 系列资源定义非压力力 (non-pressure forces)。桥接层为每种效果类型提供独立的添加函数。

### 弹性 (Elasticity)

| Godot 资源 | 函数 | Salva Solver | 参数 |
|---|---|---|---|
| `FluidEffect2DElasticity` | `fluid_add_effect_elasticity()` | `Becker2009Elasticity` | `young_modulus`, `poisson_ratio`, `nonlinear_strain` |

### 表面张力 (Surface Tension) -- 三种算法

| Godot 资源 | 函数 | Salva Solver | 参数 | 算法特点 |
|---|---|---|---|---|
| `FluidEffect2DSurfaceTensionAKINCI` | `fluid_add_effect_surface_tension_akinci()` | `Akinci2013SurfaceTension` | `fluid_tension_coefficient`, `boundary_adhesion_coefficient` | Akinci2013 -- 经典内聚力模型，实现简单，适合大多数场景 |
| `FluidEffect2DSurfaceTensionHE` | `fluid_add_effect_surface_tension_he()` | `He2014SurfaceTension` | `fluid_tension_coefficient`, `boundary_adhesion_coefficient` | He2014 -- 基于色散/内聚力的高阶模型，表面质量更好但计算量更大 |
| `FluidEffect2DSurfaceTensionWCSPH` | `fluid_add_effect_surface_tension_wcsph()` | `WCSPHSurfaceTension` | `fluid_tension_coefficient`, `boundary_adhesion_coefficient` | WCSPH -- 基于色散方程的简单模型，速度最快但精度较低 |

### 粘度 (Viscosity) -- 三种算法

| Godot 资源 | 函数 | Salva Solver | 参数 | 算法特点 |
|---|---|---|---|---|
| `FluidEffect2DViscosityArtificial` | `fluid_add_effect_viscosity_artificial()` | `ArtificialViscosity` | `fluid_viscosity_coefficient`, `boundary_viscosity_coefficient` | 人工粘度 -- 经典 SPH 方法，简单高效，适合快速原型 |
| `FluidEffect2DViscosityDFSPH` | `fluid_add_effect_viscosity_dfsph()` | `DFSPHViscosity` | `fluid_viscosity_coefficient` | DFSPH -- 隐式不可压缩方法内置的粘度处理，更物理但更昂贵 |
| `FluidEffect2DViscosityXSPH` | `fluid_add_effect_viscosity_xsph()` | `XSPHViscosity` | `fluid_viscosity_coefficient`, `boundary_viscosity_coefficient` | XSPH -- 速度平滑方法，计算量低，适合低粘度流体的速度稳定 |

### set_effect 的分发逻辑

Godot 数据层的 `RapierFluid::set_effect()` 通过 `try_cast` 判断资源类型：

```rust
fn set_effect(&self, effect: &Gd<Resource>, physics_engine: &mut PhysicsEngine) {
    if let Ok(effect) = effect.clone().try_cast::<FluidEffectElasticity>() {
        // ... Becker2009Elasticity
    } else if let Ok(effect) = effect.clone().try_cast::<FluidEffectSurfaceTensionAKINCI>() {
        // ... Akinci2013SurfaceTension
    } else if let Ok(effect) = effect.clone().try_cast::<FluidEffectSurfaceTensionHE>() {
        // ... He2014SurfaceTension
    }
    // ... 以此类推
}
```

效果存储在 `fluid.nonpressure_forces` (一个 `Vec<Box<dyn NonPressureForce>>`) 中。`fluid_clear_effects()` 清空此列表。

## HandleDouble -- 流体句柄

流体使用 `HandleDouble` 而非 `RapierId` 作为句柄，因为 Salva 使用基于 `ContiguousArenaIndex` 的句柄系统。

```rust
pub struct HandleDouble {
    pub id: usize,
    pub generation: u64,
}

pub fn fluid_handle_to_handle(fluid_handle: FluidHandle) -> HandleDouble {
    let contiguous_index: ContiguousArenaIndex = fluid_handle.into();
    let raw_parts = contiguous_index.into_raw_parts();
    HandleDouble { id: raw_parts.0, generation: raw_parts.1 }
}

pub fn handle_to_fluid_handle(handle: HandleDouble) -> FluidHandle {
    FluidHandle::from(ContiguousArenaIndex::from_raw_parts(handle.id, handle.generation))
}
```

`is_valid()` 检查 `id != usize::MAX && generation != u64::MAX`。

## 流体模拟的 step 集成

在 `PhysicsWorld::step()` 中，当存在流体粒子时执行：

```rust
if self.fluids_pipeline.liquid_world.fluids().len() > 0 {
    self.fluids_pipeline.step(
        &liquid_gravity,                    // 液体独立重力
        integration_parameters.dt,          // 物理步长
        &self.physics_objects.collider_set, // 碰撞体集合（边界耦合）
        &mut self.physics_objects.rigid_body_set, // 刚体集合（浮力耦合）
    );
}
```

`FluidsPipeline::step()` 同时处理：
1. 粒子之间的 SPH 力（压力、非压力力）
2. 粒子与 Rapier 碰撞体的碰撞
3. 粒子对 Rapier 刚体的浮力

## 流体查询 (Query)

### 获取所有粒子位置/速度/加速度

```rust
pub fn fluid_get_points(&self, world_handle, fluid_handle) -> Vec<Vector>
pub fn fluid_get_velocities(&self, world_handle, fluid_handle) -> Vec<Vector>
pub fn fluid_get_accelerations(&self, world_handle, fluid_handle) -> Vec<Vector>
```

### AABB 查询

```rust
pub fn fluid_get_particles_in_aabb(&self, world_handle, fluid_handle, aabb) -> Vec<i32>
```

通过 `aabb_to_salva_aabb()` 转换 Godot 的 `Rect` 到 Salva 的 AABB，然后调用 `liquid_world.particles_intersecting_aabb()`。

### 球形查询

```rust
pub fn fluid_get_particles_in_ball(&self, world_handle, fluid_handle, center, radius) -> Vec<i32>
```

先通过 AABB 做粗筛 (`particles_intersecting_aabb`)，再通过 `(particle_pos - center).norm_squared() <= radius_sq` 做精确判断。

## 与刚体材质的耦合

在 `body_update_material()` 中，除了更新 Rapier collider 的材质外，还同步更新流体耦合边界：

```rust
if let Some(coupling_boundary) = physics_world.fluids_pipeline
    .liquid_world.boundaries_mut()
    .get_mut(coupling_boundary_entry.boundary)
{
    coupling_boundary.interaction_groups = InteractionGroups {
        memberships: mat.collision_layer.into(),
        filter: mat.collision_mask.into(),
    };
}
```

这确保了流体粒子可以正确检测与碰撞体的碰撞/浮力交互。

## Godot 数据层的坐标变换

`RapierFluid` 管理粒子时涉及重要的坐标空间转换：

1. **发射阶段** (`fluid_impl.rs` 中的 `set_points`)：粒子的局部坐标通过 `get_global_transform()` 转换到世界空间，然后传给物理引擎。
2. **读取阶段** (`fluid_impl.rs` 中的 `get_points`)：世界空间的粒子位置通过 `get_global_transform().affine_inverse()` 转换回局部空间。

```rust
// 发射时: local -> world
let gl_transform = fluid.to_gd().get_global_transform();
rapier_points[i] = gl_transform * points[i];

// 读取时: world -> local
let gl_transform = fluid.to_gd().get_global_transform().affine_inverse();
new_points[i] = gl_transform * new_points[i];
```

## FluidEffectElasticity 参数细节

通过 `Becker2009Elasticity` 实现弹性：

| Godot 属性 | Salva 参数 | 说明 |
|---|---|---|
| `young_modulus` | `young_modulus` | 杨氏模量，控制刚度 |
| `poisson_ratio` | `poisson_ratio` | 泊松比，控制体积保持 |
| `nonlinear_strain` | `nonlinear_strain` | 是否使用非线性应力模型 |

## 相关文档

- [00-architecture.md](00-architecture.md) -- 整体架构概览
- [01-body-bridge.md](01-body-bridge.md) -- 刚体桥接层（材质与流体的耦合）
- [04-shape-bridge.md](04-shape-bridge.md) -- 形状桥接层（碰撞体形状与流体边界的关系）
