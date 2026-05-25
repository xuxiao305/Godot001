# 空间查询（Space Queries）

## 本章要解决什么问题

你的角色开了一枪，你需要知道子弹打中了谁。
你要做一个鼠标点击选择，需要知道光标下是什么物体。
你想知道"前方 10 米内是否有障碍物"。

这些需求有一个共同点：**你有一个几何查询（一个点、一条线、一个形状），想知道它与物理世界中的哪些物体相交**。这就是空间查询（Space Queries）。

```
类比：空间查询就是"对着世界问一个问题"。
"这个点碰到了谁？"="点查询"
"这条线穿过了谁？"="射线查询"
"这个框和谁重叠了？"="形状查询"
```

---

## 查询入口：PhysicsDirectSpaceState2D

Godot 中所有空间查询都通过 `PhysicsDirectSpaceState2D` 进行。获取方式：

```gdscript
var space_state = get_world_2d().direct_space_state
```

在 Rapier 中，`RapierDirectSpaceState2D` 使用 RID 标记当前的空间实例，并通过底层 `RapierDirectSpaceStateImpl` 执行实际的物理查询。

---

## intersect_point：点与谁重叠了？

`intersect_point` 查询一个点是否落在物理物体的碰撞形状内部。最常见的用途是**鼠标点击检测**。

### 方法签名

```gdscript
var results = space_state.intersect_point(
    position: Vector2,          # 查询的点（世界坐标）
    max_results: int = 32,      # 最多返回多少结果
    exclude: Array = [],        # 要排除的 Rid 列表
    collision_mask: int = 0xFFFFFFFF,  # 只看哪些层的物体
    collide_with_bodies: bool = true,  # 是否检测身体
    collide_with_areas: bool = false   # 是否检测区域
)
```

### 应用示例

```gdscript
# 检测鼠标点击位置的物体
func _input(event):
    if event is InputEventMouseButton and event.pressed:
        var space_state = get_world_2d().direct_space_state
        var results = space_state.intersect_point(event.position)
        for result in results:
            print("点击到了: ", result.collider.name)
```

```
类比：用手指戳屏幕上的物体。戳到的点如果落在
某个形状的内部，就认为"碰到了"。
```

### 内部实现

Rapier 将查询转换为世界坐标，通过 `intersect_point_rawptr` 方法调用底层 `intersect_point`，支持 `canvas_instance_id` 过滤和碰撞掩码过滤。

---

## intersect_ray：射线穿过了谁？

`intersect_ray` 从一点向另一点发射一条射线，返回**第一个（最近的）**被射线穿过的物体。

```
类比：激光笔照射出去。光线碰到第一个障碍物就会停下。
```

### 方法签名

```gdscript
var result = space_state.intersect_ray(
    from: Vector2,              # 射线起点
    to: Vector2,                # 射线终点
    exclude: Array = [],        # 要排除的 Rid 列表
    collision_mask: int = 0xFFFFFFFF,
    collide_with_bodies: bool = true,
    collide_with_areas: bool = false,
    hit_from_inside: bool = false  # 是否检测从形状内部出发的射线
)
```

返回一个 Dictionary（如果命中）或空 Dictionary：

```gdscript
{
    "position": Vector2(...),      # 碰撞点（世界坐标）
    "normal": Vector2(...),        # 表面法线（指向射线来源方向）
    "collider": Node,              # 命中的碰撞体
    "collider_id": int,            # 碰撞体 ID
    "rid": Rid,                    # 碰撞体 RID
    "shape": int                   # 命中的子形状索引
}
```

### 应用示例

```gdscript
# 射击检测
func shoot_bullet(from: Vector2, direction: Vector2, range: float):
    var space_state = get_world_2d().direct_space_state
    var to = from + direction * range
    var result = space_state.intersect_ray(from, to, [self])
    if not result.is_empty():
        var hit_enemy = result.collider
        hit_enemy.take_damage(10)
        spawn_bullet_hole(result.position, result.normal)

# 视线检测（Line of Sight）
func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
    var space_state = get_world_2d().direct_space_state
    var result = space_state.intersect_ray(from, to)
    return result.is_empty()  # 射线没碰到东西 = 有视线
```

### hit_from_inside 参数

当射线从一个碰撞体内部出发时，默认情况下引擎不会检测到碰撞（因为射线已经在形状内部了）。设置 `hit_from_inside = true` 可以从内部也检测。

```
类比：你在一个房间里面用手电筒照向外面的墙壁。
hit_from_inside = false 时，光可以穿透房间墙壁；
hit_from_inside = true 时，近侧的墙壁也会被检测到。
```

---

## intersect_shape：哪些形状与这个形状重叠了？

`intersect_shape` 用另一个物理形状作为"探针"，查询世界中哪些物体与它重叠。与 `intersect_point`（点探针）和 `intersect_ray`（线探针）不同，它使用一个完整的 2D 形状。

```
类比：用一个呼啦圈在地上扫过。
呼啦圈碰到的一切都算"重叠"。
```

### 方法签名

```gdscript
var results = space_state.intersect_shape(
    shape: Shape2D,             # 用作探针的形状（需要 RID）
    transform: Transform2D,     # 探针的位置和旋转
    motion: Vector2 = Vector2.ZERO,  # 可选的运动向量
    margin: float = 0.0,        # 探针边缘的扩展距离
    max_results: int = 32,
    collision_mask: int = 0xFFFFFFFF,
    collide_with_bodies: bool = true,
    collide_with_areas: bool = false
)
```

### 应用示例

```gdscript
# 爆炸范围查询：检测爆炸半径内的所有敌人
func detect_in_explosion_radius(center: Vector2, radius: float):
    var space_state = get_world_2d().direct_space_state
    var circle_shape = CircleShape2D.new()
    circle_shape.radius = radius
    var query = PhysicsShapeQueryParameters2D.new()
    query.shape = circle_shape
    query.transform = Transform2D(0, center)
    query.collision_mask = 1 << 2  # 只看敌人层
    var results = space_state.intersect_shape(query)
    for result in results:
        result.collider.take_damage(50)
```

### 内部实现

Rapier 的 `intersect_shape_rawptr` 接收形状 RID、变换、运动向量等参数。底层实现使用 `ShapeRID` 查找对应的 Rapier 形状引用，进行碰撞检测。

---

## cast_motion：这个形状沿某方向能移动多远？

`cast_motion` 比 `intersect_shape` 更进一步：它不是告诉你"和谁重叠了"，而是告诉你"沿给定方向安全移动多远不会碰到东西"。

```
类比：停车时慢慢靠近墙壁。你不停地问"还能往前走多少？"，
直到距离为零（碰到了）。
```

### 方法签名

```gdscript
var result = space_state.cast_motion(
    query: PhysicsShapeQueryParameters2D,  # 包含形状、变换、碰撞掩码等的查询参数对象
    motion: Vector2                         # 想要移动的方向和距离
) -> Array[float]
```

返回一个数组 `[closest_safe, closest_unsafe]`：
- `closest_safe`（float）：安全移动的比例（0.0 ~ 1.0）。1.0 = 整个 motion 都安全。
- `closest_unsafe`（float）：首次碰撞的比例。

### 应用示例

```gdscript
# 角色移动时检测是否会碰撞
func move_with_collision(body: CharacterBody2D, motion: Vector2):
    var space_state = get_world_2d().direct_space_state
    var query = PhysicsShapeQueryParameters2D.new()
    query.shape = body.get_node("CollisionShape2D").shape
    query.transform = body.global_transform
    var result = space_state.cast_motion(query, motion)
    var safe_fraction = result[0]
    var collision_fraction = result[1]
    if safe_fraction < 1.0:
        # 只能走 safe_fraction * motion 的距离才安全
        motion *= safe_fraction
    body.global_position += motion
```

---

## collide_shape：详细碰撞信息查询

`collide_shape` 类似于 `intersect_shape` 但返回**更丰富**的碰撞信息。不仅知道和谁重叠了，还知道碰撞点、法线、穿透深度等。

由于返回数据量大，它使用原始指针（raw pointer）来写入结果，对应 Rapier 中的 `collide_shape_rawptr` 方法。

---

## rest_info：静止信息查询

`rest_info` 查询如果将形状放置在给定位置，它是否会与某个物体碰撞，并返回"最近的接触点"信息。

```
类比：你想要把一个方块放在地上。rest_info 告诉你方块底部
会碰到什么、碰在哪、法线方向是什么。
```

对应的 Rapier 方法：`rest_info_rawptr`

---

## collision_layer 和 collision_mask

### 两层过滤机制

Rapier 使用标准的 Godot 碰撞层（Collision Layer）和碰撞掩码（Collision Mask）机制：

```
对于物体 A 和物体 B 要发生碰撞：
  (A.collision_layer & B.collision_mask) != 0
  AND
  (B.collision_layer & A.collision_mask) != 0
```

### collision_layer：我是什么

物体属于哪些层。例如：
- 第 1 层：环境/地形
- 第 2 层：玩家
- 第 3 层：敌人
- 第 4 层：弹丸

### collision_mask：我看见谁

物体关心哪些层。例如：
- 弹丸设置 mask 为第 2 层和第 3 层（打玩家和敌人，不打环境）
- 环境设置 mask 为所有层（和一切碰撞）

### 空间查询中的掩码

在空间查询中，`collision_mask` 参数让你只查询特定层的物体，而不必手动遍历所有结果做筛选。

```gdscript
# 只看第 2 层（玩家）和第 3 层（敌人）
var mask = (1 << 1) | (1 << 2)  # bit 1 和 bit 2
var result = space_state.intersect_ray(from, to, [], mask)
```

### 底层实现

Rapier 中 `collision_layer` 和 `collision_mask` 存储在 `Material` 结构中（与摩擦、弹性等一起），在创建碰撞体时应用。collision_mask 用于过滤碰撞对，collision_layer 决定物体属于哪些组。

---

## 空间查询的性能提示

1. **只查询你需要的层**：通过 `collision_mask` 过滤，避免不必要的碰撞测试
2. **射线比形状快**：能用射线检测解决的问题（如视线检测），不要用形状重叠
3. **点检测最快**：如果是简单的点击检测，用 `intersect_point`
4. **避免每帧做大量查询**：将查询分散到多帧，或缓存结果
5. **排除无关物体**：使用 `exclude` 参数排除查询者自身

---

## 延伸阅读

- [Rapier 官方文档：Scene Queries](https://rapier.rs/docs/user_guides/2d/scene_queries)
- Godot 官方文档：PhysicsDirectSpaceState2D
- 本指南：[01-rigid-body.md](01-rigid-body.md) -- 查询的对象是刚体
- 本指南：[04-collision-shapes.md](04-collision-shapes.md) -- 查询使用的形状
