# 3C v1 验证记录 — 2026-05-24

> 本文件由 Task 12 创建为模板，等待人工 F6 走一遍 test_level 后填入结果。
> 入口：主菜单 → "11 - 3C 原型"，或直接 F6 打开 `Scenes/Prototypes/3C/test_level.tscn`。

## §6 验证标准结果

| # | 标准 | 通过? | 备注 |
|---|---|---|---|
| 1 | §4.9 所有参数都能在 runtime 滑条调（F1 切换 Debug 面板） | ⏳ | 13 个滑条 + 6 个 readout 已实现；需人工确认每个滑条实时生效 |
| 2 | 在测试关卡能制造"边缘 Coyote 起跳"和"提前 Buffer 起跳"的成功 case | ⏳ | 在悬崖（x=3200-3400）测 Coyote；在下降平台序列（x=3400-3800）测 Buffer |
| 3 | 调整地面 μ 能明显改变滑行距离（冰 vs 泥 vs 默认 显著不同） | ⏳ | 冰区 x=600-1000、泥区 x=1000-1400、默认走廊 x=0-600 |
| 4 | 走过台阶序列能看到 Capsule 弹跳症状：接地态闪烁 + 水平减速 + 视觉颠簸 + debug 面板法线变化 | ⏳ | 台阶序列 x=1400-1800，5 级每级 60px |
| 5 | 开启 1 帧防抖（`ground_state_buffer_frames`=1）后，接地态闪烁掩盖，水平减速仍在 | ⏳ | 调 Debug 面板的 ground_state_buffer_frames 滑条 |
| 6 | 助跑跳能跨过比原地跳明显更宽的缺口（验证 ADR-0004） | ⏳ | 第二个 200px 缺口 x=2400-2600 配合助跑跑道 x=2000-2400 |
| 7 | dynamic box 踩稳 + box 会被踩动少量 | ⏳ | DynamicBox 在 x=4200 |
| 8 | 推一下 dynamic box → 角色受反作用力被微微减速 | ⏳ | 同上 |
| 9 | 摄像机平移不眩晕、不卡顿 | ⏳ | CameraFollow 默认 follow_time_constant=0.15s |
| 10 | 朋友试玩主观评价 | ⏳ | 后做 |

## 调整后的参数（如有偏离 spec 默认值）

待 Debug 面板 Save 按钮存出后，从 `%APPDATA%\Godot\app_userdata\2D Platformer - Starter Kit\3c_params.json` 复制到此处：

```json
（待填）
```

## 发现的问题 / 未来 ADR 候选

待 F6 走完后填入。可能的候选：
- Capsule 弹跳若太严重 → 触发 ADR-0007（切换 Box+脚趾）
- Apex 飘感不足 → 启动 ADR-0003 辅助力（gravity_fall_multiplier / apex_hang）
- 空中控制力 f_max_air = 40 N 是否合适
- coyote_time / jump_buffer_time 默认 0.10s 是否需要调

## 测试入口与操作约定

- 主菜单 → "11 - 3C 原型" 进入 test_level
- F1：切换 Debug 面板显示
- 移动：A/D 或 Left/Right
- 跳跃：Space（或在 Input Map 里绑定的 Jump 按键）
- Debug 面板：
  - Reset 按钮：参数恢复 spec 默认值
  - Save：写入 `user://3c_params.json`
  - Load：从同一文件读回
- 关卡布局（从左到右）：
  - 0-600 默认走廊
  - 600-1000 冰区
  - 1000-1400 泥区
  - 1400-1800 5 级台阶
  - 1800-2000 缺口（原地跳跨不过）
  - 2000-2400 助跑跑道
  - 2400-2600 缺口（助跑跳能跨）
  - 2600-2800 小凸起
  - 2800-3200 多高度平台
  - 3200-3400 紧密悬崖（Coyote）
  - 3400-3800 下降平台序列（Buffer）
  - 3800-4000 墙
  - 4000-4400 dynamic box
