# Spike 0 决议 — Constraint 物理路径策略

**任务来源：** `docs/superpowers/plans/2026-05-25-destruction-prototype-plan.md` Task 0

**Spike 文件：**
- 脚本：`Scripts/Prototypes/Destruction/spike/spike_pin_reaction.gd`
- 场景：`Scenes/Prototypes/Destruction/spike/spike_pin_reaction.tscn`
- Smoke 日志：headless 跑出的日志已 inline 节录到本文件，原始 log 文件未入库

**结论：** 选 (c) — v1 不实现物理路径

**用户决策日期：** 2026-05-25（F6 后确认）

**Spike 推荐：** (c) — v1 不实现物理路径，T4 拱门塌方手动 F6 容忍；理由见下。如果坚持物理路径，
应走改良版 (b')：用差分加速度 `|mA·aA·n − mB·aB·n|`，而不是原方案的和式。

---

## 证据 — (a) 私有 API 读 reaction force

**全部为 false / null。** Box2D 后端不暴露任何 reaction force API。

### grep 证据
```
$ grep -ri reaction D:/GoDot/Projects/2DPlatformerSample/addons/godot-box2d/
(无匹配)
```
addon 整个目录只有 SVG 图标 + DLL，零源文件 — 不可能从外面 patch。

### Godot 上游 PinJoint2D 头文件
`d:/GoDot/Source/godot-master/scene/2d/physics/joints/pin_joint_2d.h`：只有 softness / angular_limit /
motor 相关 getter，没有任何反作用力 / 约束冲量接口。父类 `Joint2D` 也只暴露 `get_rid()`。

### 运行时探测（spike print 关键片段）
```
[spike] pin.has_method("get_reaction_force") = false
[spike] pin.has_method("get_constraint_force") = false
[spike] pin.has_method("get_applied_impulse") = false
[spike] pin.has_method("get_reaction_impulse") = false
[spike] pin.has_method("get_force") = false
[spike] pin.has_method("get_impulse") = false
[spike] pin.get("reaction_force") = <null>
[spike] pin.get("constraint_force") = <null>
[spike] pin.get("applied_impulse") = <null>
[spike] pin.get("reaction_impulse") = <null>
[spike] pin.get("force") = <null>
[spike] pin.get("impulse") = <null>
[spike] PhysicsServer2D.has_method("joint_get_reaction_force") = false
[spike] PhysicsServer2D.has_method("joint_get_applied_impulse") = false
[spike] PhysicsServer2D.has_method("joint_get_constraint_force") = false
```

**结论 (a)：** 完全不可行。要走 (a) 需要 fork godot-box2d 加 GDExtension binding，超出 prototype 范围。

---

## 证据 — (b) 相对加速度代理 sigma_proxy

实现：`sigma_proxy = |mA·(aA·n)| + |mB·(aB·n)|`，n = A→B 单位向量。

### 三阶段数值（spike 0–8s）

**STATIC (0–1s)** — 无外力：
```
phase=STATIC sigma_proxy=0.000  (mA*aA.n=0.000, mB*aB.n=0.000)
```
✅ 符合预期 — 没有加速度就没有"应力"读数。

**IMPULSE (1–5s)** — 每 0.1s 给 B 一个 +5 N·s 水平 impulse：
```
phase=IMPULSE impulse_total=10.0  sigma_proxy=0.494  (-0.247, -0.247)
phase=IMPULSE impulse_total=15.0  sigma_proxy=0.983  (-0.491, -0.491)
...
phase=IMPULSE impulse_total=170.0 sigma_proxy ≈ 数值随阻尼缓慢增长，量级 1~10
```
⚠️ 注意：两端 acceleration 几乎完全相等（A 和 B 被 pin 锁住，作为刚体对一起运动）。
**这意味着相对加速度沿轴向 ≈ 0**，而 (b) 求的是**和**而不是**差**——所以读到的只是
"整对刚体被外力加速"的惯性，并不是"pin 在传力"的指标。

**PIN_DELETED (5.5–8s)** — pin 删掉之后：
```
[spike] >>> deleting pin at t=5.52 <<<
phase=PIN_DELETED  sigma_proxy=13.163  (-6.582, -6.582)  <- 比 IMPULSE 阶段还高
phase=PIN_DELETED  sigma_proxy=10.426  (-5.213, -5.213)  <- 一直稳在 ~10
```
❌ **致命问题**：pin 已经不存在了，sigma_proxy 反而比 pin 存在时还高。原因是
两个 body 都还在因为 linear_damp 而减速，差分出 ~-5 的加速度，proxy 把这识别为"应力"。

### 量级分析与结论 (b)

**原方案 (b) 不能区分"约束传力"和"自由减速/外力加速"**，这是对应力代理的根本性误判。
拱门塌方场景中，所有 brick 都在重力作用下持续有加速度（即使 pin 完好），proxy 会读到
大量假阳性 → 不停误触发 break → 拱门刚生成就崩。

### (b') 改良方案 — 差分加速度

`sigma_proxy' = |mA·(aA·n) − mB·(aB·n)|`

物理直觉：如果 pin 真在传力，A 和 B 沿轴向应该有**反向**等大加速度（牛顿第三定律），
差分会 ≈ 2·|F_pin|；如果只是外力推整对，两端 acceleration 同号同大小，差分 ≈ 0。

从 spike 数据看 (b')：
- IMPULSE 阶段：(aA·n − aB·n) ≈ 0 → sigma_proxy' ≈ 0 ❌ **也不对** —
  说明在被刚 pin 住的两体上，约束本身就让 aA = aB，差分天然为零，
  根本读不出"pin 多努力"。
- 要让 (b') 有意义，**pin 必须有 softness > 0**，让两端能产生小幅相对运动 → 才能差出 a。
  这是 Box2D `b2_softPinJoint` 的方向，但 godot-box2d 默认 PinJoint2D 是硬约束。

→ (b') 也不靠谱，除非全局把 pin 改成 soft，会改变手感。

---

## 证据 — (c) v1 不做物理路径

参考 spec §3.1 T4：拱门塌方依赖 ConstraintBreaker 在 pin 反作用力超阈值时断开 pin。
如果 (a) (b) (b') 都不可行：
- **受影响成功标准**：T4 拱门塌方退化为"手动 F6 验收"——人眼看拱门在重力下是否稳定，
  在外力（projectile）冲击下是否能局部塌方。
- **不受影响**：T1/T2/T3（projectile 击碎单 brick、破片碎散、连锁掉落）走的是 contact_monitor +
  HP 路径，与 ConstraintBreaker 无关，照常实现。
- v1.5 follow-up：fork godot-box2d 加 `b2Joint::GetReactionForce()` 的 binding，走 (a) 路。

---

## 提议的修订（待 user 决策后落地）

**若选 (c)（spike 推荐）：**
- Task 6 (ConstraintBreaker) 删除，或降级为 "stub class，记录 TODO，永不触发"
- spec §3.1 T4 注脚改为"手动 F6 验收时容忍 — 物理 break 路径推迟到 v1.5"
- 新开 follow-up plan `docs/superpowers/plans/2026-XX-XX-destruction-v1.5-constraint-break.md`
  描述 fork box2d 暴露 reaction 的工作

**若选 (b) 原方案：**
- 警告：拱门会在生成瞬间塌方（重力下的加速度就会触发 break）
- 必须先做一个"重力静止"过滤（grounded + low velocity 不计入应力），增加 spec 复杂度
- 不推荐

**若选 (b') 改良 + pin softness：**
- 需要先 spike PinJoint2D.softness 参数对手感的影响（拱门会不会一直摇晃）
- 多一个调参维度
- 中等推荐

**若选 (a)：**
- 立刻进入 v1.5 范围，prototype 周期超支
- 不推荐 prototype 阶段做

---

## Verification 证据

| 层 | 命令 | 结果 |
|---|---|---|
| parse | `--check-only --script spike_pin_reaction.gd` | ✅ 仅打印 Godot banner，无错误 |
| import | `--headless --quit` | ✅ 无相关 SCRIPT ERROR（仅打印无关的 demo_menu ready） |
| smoke run | headless 跑 .tscn 8s 自退 | ✅ 无 stderr，正常 print，自然 quit |

Smoke 日志已 inline 节录在本文件 (b)/(b') 段落，原始 log 未入库（一次性 evidence）。

---

## 用户决策：选 (c) — v1 不实现物理路径

**落地动作：**
- Task 6 ConstraintBreaker 降级为 stub：保留 class + register/scan 签名，scan() 内为空操作（便于后续 v1.5 替换）
- Task 11 验收时 T4（拱门塌方）改为"手动 F6 容忍"——人眼看拱门在重力下静态稳定 + projectile 击碎柱底时局部塌方
- Task 13 验收清单 T4 注脚标"spike0 (c) 路线下：挂着掉一截也算 pass"
- 新开 follow-up plan 描述 fork box2d 暴露 reaction force（在 v1 milestone 完成后写）

User F6 时建议观察（已确认）：
1. 编辑器里看到两个小方块悬浮（重力被 _ready 关掉）并被 pin 连接
2. 1s 后 B 开始被 impulse 推，A 因 pin 跟着动（pair 一起向 +x 漂）
3. 5.5s 后 pin 消失，两 body 继续按 momentum + damping 各自飘
4. Output 面板 sigma_proxy 数值与上面记录一致，确认 (b) 噪声不可接受
