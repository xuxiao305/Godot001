# 碰撞形状（CollisionShape2D）

## 本章要解决什么问题

每个物理物体都需要一个"碰撞外形"-- 告诉引擎"我的边界在哪里"。你不能让引擎用一个无限小的点来检测碰撞，那既不现实也不实用。你需要给它一个形状。

```
类比：每个人的身份证照片（形状）告诉安检人员"这个人长什么样"。
碰撞形状就是物体在物理世界中的"身份证照片"。
```

---

## 形状类型的完整列表

Rapier 2D 支持以下碰撞形状（通过 Godot 的 `CollisionShape2D` 节点使用）：

| 形状 | Godot Shape2D 类 | 2D 描述 |
|------|-----------------|---------|
| Circle（圆形） | CircleShape2D | 一个圆 |
| Rectangle（矩形） | RectangleShape2D | 一个矩形 / 盒子 |
| Capsule（胶囊形） | CapsuleShape2D | 矩形 + 两端半圆 |
| Segment（线段） | SegmentShape2D | 一条线段（薄边） |
| ConvexPolygon（凸多边形） | ConvexPolygonShape2D | 任意凸多边形 |
| ConcavePolygon（凹多边形） | ConcavePolygonShape2D | 任意凹多边形（分解为凸） |
| WorldBoundary（世界边界） | WorldBoundaryShape2D | 一个无限延伸的直线（半空间） |
| SeparationRay（分离射线） | SeparationRayShape2D | 一根用于检测的射线 |

---

## 每种形状的详细说明

### CircleShape2D（圆形）

最简单的形状。只需要一个半径（radius）。

```
类比：一个完美的球。无论如何旋转，碰撞边界完全相同。
```

- **性能**：最快。圆形碰撞检测只需要比较两个圆心距离和一个半径和。
- **缺点**：占用空间效率低。一个方形箱子用圆形包裹会在四角留空。
- **适用场景**：球类、弹丸、角色头部碰撞、简化碰撞

### RectangleShape2D（矩形）

定义一个宽度和高度的矩形。

```
类比：一个纸箱。有明显的边和角。
```

- **性能**：非常快。矩形碰撞也在原生 Rapier 中有高优化实现。
- **缺点**：不能旋转后仍是完美的矩形（但 Rapier 自动处理旋转后的凸包）。
- **适用场景**：箱子、平台、墙壁、地板、大多数规则形状的物体

### CapsuleShape2D（胶囊形）

由一个矩形段和两端各一个半圆组成。需要设置 `radius`（半圆半径）和 `height`（矩形段高度）。

```
类比：一颗药丸的形状。两端圆润，中间是直的。
```

- **性能**：比圆形稍慢，但仍比多边形快得多。
- **优点**：圆润边缘不会在斜坡上卡住（方形会），角色碰撞的首选形状。
- **适用场景**：角色碰撞体（强烈推荐）、斜坡地形

### SegmentShape2D（线段）

定义一条有起点和终点的线段。

```
类比：一根牙签。极薄的直线。
```

- **性能**：快。仅检测线段与其他形状的交点。
- **适用场景**：细杆、冰面边缘、收窄的地形边界

### ConvexPolygonShape2D（凸多边形）

凸多边形（Convex Polygon）指所有内角都小于 180 度的多边形。

```
凸多边形的简单判断：
从多边形内部看，任何一条边都不会遮住其他部分。
换句话说，在多边形内任意两点之间画线，线条永远在多边形内部。
```

- **性能**：中等。随着顶点数增加略微变慢。
- **优点**：比矩形更灵活的形状表达能力。
- **缺点**：顶点较多时创建成本略高。
- **适用场景**：斜坡、三角形障碍、自定义角色轮廓

```gdscript
# 创建一个三角形碰撞形状
var shape = ConvexPolygonShape2D.new()
shape.points = PackedVector2Array([
    Vector2(0, 0),
    Vector2(50, 0),
    Vector2(25, -50)
])
$CollisionShape2D.shape = shape
```

### ConcavePolygonShape2D（凹多边形）

凹多边形（Concave Polygon）至少有一个内角大于 180 度。

```
举例：L 形、星形、E 形都是凹多边形。
```

Rapier 内部会将凹多边形**自动分解为多个凸多边形**，因为物理引擎只理解凸形状。这个过程对用户透明，但性能上等同于多个凸多边形的组合。

- **性能**：相当于多个凸多边形的组合性能，随凹度增加。
- **适用场景**：复杂的地形轮廓、不规则的洞穴墙壁

### WorldBoundaryShape2D（世界边界）

定义一个无限延伸的直线。`distance` 参数决定直线与原点的距离，`normal` 决定直线的方向（哪一侧是"内部"）。

```
类比：地平线。你只能定义它的方向和位置，
但它向两侧无限延伸。
```

- **性能**：极快（解析解，无需迭代）。
- **注意**：只适用于 StaticBody2D。Dynamic 物体不能绑定世界边界形状。
- **适用场景**：关卡边界、无限地面、天花板

```gdscript
# 创建一个在 y=500 处、法线向上的世界边界（地面）
var shape = WorldBoundaryShape2D.new()
shape.normal = Vector2(0, -1)  # 向上
shape.distance = 500.0
```

### SeparationRayShape2D（分离射线）

一根从物体原点发射的射线，用于**检测距离**而非碰撞。设置 `length` 定义射线的长度。

```
类比：汽车的倒车雷达。不停探测"距离后面墙壁有多远"。
```

- **性能**：快。仅做射线投射。
- **注意**：这不是碰撞形状，而是检测工具。不参与碰撞响应。
- **适用场景**：地面检测（角色是否站在地上）、滑墙检测

---

## 形状选择建议

### 性能排序（从快到慢）

1. WorldBoundaryShape2D -- 解析解
2. CircleShape2D -- 一次平方距离比较
3. SegmentShape2D -- 线段相交检测
4. RectangleShape2D -- SAT（分离轴定理）检测，但 4 条边很高效
5. CapsuleShape2D -- 与矩形类似
6. ConvexPolygonShape2D -- SAT，边数越多越慢
7. ConcavePolygonShape2D -- 分解为多个凸多边形

### 实际选择指南

| 场景 | 推荐形状 |
|------|----------|
| 角色碰撞体 | CapsuleShape2D（防卡角） |
| 弹丸/子弹 | CircleShape2D（旋转无关） |
| 箱子/道具 | RectangleShape2D |
| 复杂地形 | ConcavePolygonShape2D（自动分解） |
| 关卡边界 | WorldBoundaryShape2D |
| 地面检测射线 | SeparationRayShape2D |

### 凸 vs 凹

一般原则：
- **运动物体**用凸形状（ConvexPolygonShape2D、CircleShape2D、RectangleShape2D 等）
- **静态地形**可以用凹多边形（ConcavePolygonShape2D）

动态物体使用凹多边形可能在物理上产生未定义行为，因为 Rapier 的核心碰撞检测（Collision Detection）算法设计针对凸形状。

---

## 延伸阅读

- [Rapier 官方文档：Colliders](https://rapier.rs/docs/user_guides/2d/colliders)
- Godot 官方文档：CollisionShape2D / CollisionPolygon2D
- 本指南：[01-rigid-body.md](01-rigid-body.md) -- 形状绑定到刚体
- 本指南：[05-space-queries.md](05-space-queries.md) -- 用形状做空间查询
