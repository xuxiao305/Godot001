# 04 -- 形状桥接 (Shape Bridge)

本章讲解 Godot 的碰撞形状如何映射到 Rapier 的 `SharedShape`（共享形状）。核心桥接代码位于 `src/rapier_wrapper/shape.rs`。

## 形状存储架构

形状在 `PhysicsEngine` 中以全局单例管理，不与特定物理世界绑定：

```rust
pub struct PhysicsEngine {
    pub physics_worlds: HashMap<WorldHandle, PhysicsWorld>,
    pub shapes: HashMap<ShapeHandle, SharedShape>,  // 全局共享
}
```

`ShapeHandle` 本质上是 `RapierId`（与 Space/Body/Joint 使用相同的 ID 系统）。当 Godot 创建一个形状时，它被插入到全局 `shapes` Arena 中。碰撞体（Collider）通过 `ShapeHandle` 引用这些共享形状。

## 形状类型映射总览 (2D)

| Godot 形状类型 | 桥梁函数 | Rapier SharedShape |
|---|---|---|
| `ConvexPolygonShape2D` | `shape_create_convex_polyline()` | `convex_polyline()` 或 `convex_hull()` (fallback) |
| `RectangleShape2D` | `shape_create_box()` | `cuboid(half_x, half_y)` |
| `CircleShape2D` | `shape_create_circle()` | `ball(radius)` |
| `CapsuleShape2D` | `shape_create_capsule()` | `capsule_y(half_height, radius)` |
| `ConcavePolygonShape2D` | `shape_create_concave_polyline()` | `polyline(points, indices)` |
| `WorldBoundaryShape2D` | `shape_create_halfspace()` | `compound([halfspace])` |
| `SeparationRayShape2D` | (同 convex_polyline) | `convex_polyline()` (两个点构成的线段) -- 见下方详解 |

## 形状生命周期

```
create (创建)
  |-- Godot: PhysicsServer2D::shape_create(type)
  |-- RapierShapeBase 对象创建
  |-- PhysicsEngine::shape_create_*() 构建 SharedShape
  |-- 插入 PhysicsEngine.shapes
  |
  v
bind to collision object (绑定)
  |-- RapierCollisionObjectBase::add_shape()
  |-- 通过 shape_handle 查找 SharedShape
  |-- 创建 Collider 并插入 ColliderSet
  |-- RapierShapeBase.add_owner() 记录引用计数
  |
  v
destroy (销毁)
  |-- PhysicsEngine::shape_destroy()
  |-- 从 PhysicsEngine.shapes 中移除
```

## 1. 矩形 (Box) -> cuboid

```rust
pub fn shape_create_box(&mut self, size: Vector, handle: ShapeHandle) {
    let shape = SharedShape::cuboid(0.5 * size.x, 0.5 * size.y);
    self.insert_shape(shape, handle);
}
```

**参数转换**：Godot 的 `size` 是矩形的完整宽高，Rapier 的 `cuboid` 使用半尺寸 (half-extents)，因此需要 `0.5 * size`。

## 2. 圆形 (Circle) -> ball

```rust
pub fn shape_create_circle(&mut self, radius: Real, handle: ShapeHandle) {
    let shape = SharedShape::ball(radius);
    self.insert_shape(shape, handle);
}
```

**直接映射**：Godot 的 `radius` 直接等于 Rapier 的 `ball.radius`，无需转换。

## 3. 胶囊 (Capsule) -> capsule_y

```rust
pub fn shape_create_capsule(&mut self, half_height: Real, radius: Real, handle: ShapeHandle) {
    let shape = SharedShape::capsule_y(half_height, radius);
    self.insert_shape(shape, handle);
}
```

**使用 `capsule_y`**：Rapier 2D 中 `capsule_y` 的轴线沿 Y 轴。Godot 的 CapsuleShape2D 默认也是沿 Y 轴对齐的。

## 4. 凸多边形 (ConvexPolygon) -- 含 fallback 策略

这是最复杂的形状创建，因为 Godot 的凸多边形可能不是"严格凸"或"严格逆时针"：

```rust
pub fn shape_create_convex_polyline(&mut self, points: &Vec<Vector>, handle: ShapeHandle) -> bool
```

### 处理流程

```
预处理: 检测 points 的方向和凸性
  |
  +-- 逆时针且凸 -> 直接使用原始 points
  |
  +-- 顺时针且凸 -> reverse() 后使用
  |
  +-- 非凸或退化 -> sort_points_counter_clockwise() 排序
  |
  v
创建: convex_polyline_unmodified(处理后的 points)
  |
  +-- 成功 -> insert_shape() -> return true
  |
  +-- 失败 -> fallback: convex_hull()
  |
  v
convex_hull() 失败 -> return false
```

说明：第一步是**预处理阶段** -- 仅对顶点做方向检测和修正（翻转或重排序），不创建形状。所有路径收敛到第二步，用修正后的 points 统一调用 `convex_polyline_unmodified()`。如果 Rapier 拒绝（如退化面），再用 `convex_hull()` 兜底。

### 方向检测

```rust
fn convex_polyline_orientation(points: &[Vector]) -> Option<ConvexPolylineOrientation> {
    // 1. 检测面积符号 (有向面积)
    let area = signed_area(points);
    // 2. 逐边检测凸性 (cross product 符号一致性)
    // 3. 检测退化边 (边长过小)
}
```

使用有向面积 (signed area) 判断方向：
- `signed_area > epsilon` -> 逆时针 (CounterClockwise)
- `signed_area < -epsilon` -> 顺时针 (Clockwise)

### 非凸多边形排序

当多边形不满足凸性要求时，`sort_points_counter_clockwise()` 将点云按角度排序生成凸包：

```rust
fn sort_points_counter_clockwise(points: &[Vector]) -> Vec<Vector> {
    // 1. 计算几何中心
    // 2. 按相对于中心的极角排序
    // 3. 同角度按距离排序
}
```

### convex_hull fallback

如果 `convex_polyline_unmodified()` 仍然失败（例如 Rapier 内部检测到退化面），则使用 `SharedShape::convex_hull(&points_vec)` 作为最后的兜底方案。这会调用 Rapier 的凸包算法重新计算顶点。

## 5. 凹多边形 (ConcavePolygon) -> polyline

```rust
pub fn shape_create_concave_polyline(
    &mut self,
    points: &Vec<Vector>,
    indices: Option<Vec<[u32; 2]>>,
    handle: ShapeHandle,
) {
    let points_vec = point_array_to_vec(points);
    let shape = SharedShape::polyline(points_vec, indices);
    self.insert_shape(shape, handle);
}
```

`polyline` 接受可选索引数组 `Option<Vec<[u32; 2]>>`。当 `indices` 为 `None` 时，Rapier 将自动按顺序连接点。提供 indices 可以显式定义边。

## 6. 世界边界 (WorldBoundary) -> compound + halfspace

```rust
pub fn shape_create_halfspace(&mut self, normal: Vector, distance: Real, handle: ShapeHandle) {
    let shape = SharedShape::halfspace(normal.normalize_or_zero());
    let shape_position = Pose::from_parts(normal * distance, Rotation::default());
    let shapes_vec = vec![(shape_position, shape)];
    let shape_compound = SharedShape::compound(shapes_vec);
    self.insert_shape(shape_compound, handle);
}
```

**为什么用 compound？** Rapier 的 `halfspace` 是一个从原点出发的半平面（法线方向为外侧）。Godot 的 WorldBoundary 需要一个可以定位的半平面（有距离偏移）。因此将其包装在 compound 中，用 `Pose` 设置位置偏移。

## 7. 射线 (SeparationRayShape2D) -> convex_polyline

`SeparationRayShape2D` 没有专用的 Rapier 形状类型。它被桥接为一个两点的 `convex_polyline` 线段：

- Godot 的射线定义为从原点沿 +X 方向、长度为 `length` 的线段
- 桥接层将其映射为两个点：`[(0, 0), (length, 0)]`
- 这两个点通过 `shape_create_convex_polyline()` 走标准凸多边形流程
- 因此 RayShape 也享有凸多边形的方向检测和 convex_hull fallback

这意味着 RayShape 在 Rapier 中实际上是一个极窄的凸多边形（线段），而非无限长射线。对于需要真正的射线检测，应使用 Rapier 的 `RayCast` 查询 API（见 [05-space-queries](../01-user-manual/05-space-queries.md)）。

## ShapeInfo -- 形状与变换的组合

当形状被绑定到碰撞体时，创建 `ShapeInfo` 结构体：

```rust
pub struct ShapeInfo {
    pub handle: ShapeHandle,
    pub transform: Pose,   // 碰撞体本地空间中的形状变换
    pub skew: Real,        // 倾斜 (仅 2D)
    pub scale: Vector,     // 缩放
}
```

```rust
pub fn shape_info_from_body_shape(shape_handle: ShapeHandle, transform: Transform) -> ShapeInfo {
    ShapeInfo {
        handle: shape_handle,
        transform: Pose::from_parts(
            vector_to_rapier(transform.origin),
            Rotation::from_angle(transform.rotation()),
        ),
        skew: transform.skew(),
        scale: vector_to_rapier(transform.scale()),
    }
}
```

`ShapeInfo` 在创建 `Collider` 时被使用，将形状定位到碰撞体的本地坐标系。

## 形状的引用计数

`RapierShapeBase` 维护一个 `owners` HashMap，跟踪哪些碰撞体在使用此形状：

```rust
pub struct RapierShapeState {
    aabb: Rect,                    // 本地 AABB 缓存
    owners: HashMap<RapierId, i32>, // 使用此形状的碰撞体 ID -> 引用计数
    id: RapierId,
}
```

- `add_owner(owner)`：引用计数 +1
- `remove_owner(owner)`：引用计数 -1，减到 0 时移除条目
- `destroy_shape()`：清空所有 owners 并通知 PhysicsEngine 删除 SharedShape

当形状数据变更时，`call_shape_changed()` 遍历所有 owners 并通知它们重建 collider。

## 坐标转换

形状创建时，point array 在桥梁层需要转换为 Rapier 的向量格式：

```rust
pub fn point_array_to_vec(pixel_data: &Vec<Vector>) -> Vec<Vector> {
    let mut vec = Vec::<Vector>::with_capacity(pixel_data.len());
    for point in pixel_data {
        vec.push(*point);
    }
    vec
}
```

这是从 Godot 的引用 Vector 数组到 Rapier 期望的 owned Vector 数组的转换。

## 形状查询函数汇总

| 桥梁函数 | 返回类型 | 说明 |
|---|---|---|
| `shape_get_box_size()` | `Vector` (half_extents) | 获取 cuboid 的半尺寸 |
| `shape_circle_get_radius()` | `Real` | 获取 ball 的半径 |
| `shape_get_capsule()` | `(Real, Real)` half_height, radius | 获取胶囊参数 |
| `shape_get_convex_polyline_points()` | `Vec<Vector>` | 获取凸多边形顶点 |
| `shape_get_concave_polyline()` | `(&[Vector], &[[u32; 2]])` | 获取凹多边形顶点和边 |
| `shape_get_halfspace()` | `(Vector, Real)` normal, distance | 获取半空间法线和距离 |
| `shape_get_aabb()` | `rapier::prelude::Aabb` | 获取本地 AABB |

## 形状的 AABB 缓存

`RapierShapeBase::reset_aabb()` 从 Rapier 的 `compute_local_aabb()` 获取 AABB 并缓存到 `RapierShapeState.aabb` 中：

```rust
pub(super) fn reset_aabb(&mut self, physics_engine: &mut PhysicsEngine) {
    let rapier_aabb = physics_engine.shape_get_aabb(self.get_id());
    let vertices = rapier_aabb.vertices();
    self.state.aabb = Rect::new(
        vector_to_godot(vertices[0]),
        vector_to_godot(rapier_aabb.extents()),
    );
}
```

这个缓存用于碰撞体的 AABB 计算 (`RapierCollisionObjectBase::get_aabb()`)，避免每次查询都调用 Rapier API。

## 相关文档

- [00-architecture.md](00-architecture.md) -- 整体架构概览
- [01-body-bridge.md](01-body-bridge.md) -- 刚体桥接层（碰撞体与形状的绑定）
- [03-fluid-bridge.md](03-fluid-bridge.md) -- 流体桥接层
