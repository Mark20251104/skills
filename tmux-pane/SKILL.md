---
name: tmux-pane
description: Use when the user needs a persistent secondary shell alongside the current conversation — SSH 远程连接、日志监控（tail）、服务状态查询、并行命令执行、"在右侧/底部 pane 跑 X"、"split tmux"、"开个新 pane"、"在另一个 pane 运行 Y" 等场景。默认在主 pane 右侧新建侧边 pane。
---

# tmux-pane

在当前 tmux 会话中创建并驱动一个**默认位于右侧**的侧边 pane，用于 SSH 远程连接、日志监控、服务状态查询等需要持续运行的任务，主对话 pane 保持自由。

仅当用户明确要求"底部"或"下方"时才改用底部布局（`split-window -v`）。

## 何时使用此 skill

满足任一条件即触发：

- 用户要求"在右侧/底部新建 pane"、"split tmux"、"开个新 pane"
- 用户要求"在另一个 pane 运行 X"、"在侧边 pane SSH 到 X"
- 用户需要 tail 日志/监控进程/查看服务状态，且不应阻塞当前对话
- 需要并行运行多个命令（一个在主 pane，一个在侧边 pane）

## 前置检查

执行任何 tmux 命令前确认在 tmux 会话内：

```bash
[ -n "$TMUX" ] && echo "in tmux" || echo "NOT in tmux"
```

若不在 tmux 中，告知用户需要先 `tmux new -s <name>` 或附加到已有会话。

## 核心工作流（四步）

### Step 1：创建 pane

```bash
# 默认：右侧新建（垂直分割），占 40% 宽
tmux split-window -h -p 40

# 用户明确要求底部时（水平分割）
tmux split-window -v -p 30
```

**关于焦点**：`split-window` 后焦点会切到新 pane，但**所有后续 `send-keys` / `capture-pane` 都用 `-t` 目标语法寻址**，与当前焦点无关，因此**不需要也不应该手动 `select-pane` 切回主 pane**。

### Step 2：发送命令

**强烈推荐**：split 时直接用 `-P -F '#{pane_id}'` 把新 pane ID 写入 shell 变量，后续所有操作都用 `-t "$SIDE_PANE"` 寻址，不依赖 layout 和焦点：

```bash
SIDE_PANE=$(tmux split-window -h -p 40 -P -F '#{pane_id}')
tmux send-keys -t "$SIDE_PANE" "<命令>" Enter
```

> ⚠️ 不要写成 `tmux split-window ... | read SIDE_PANE`——管道右侧在 subshell 执行，变量赋值丢失。必须用 `$(...)`。

如果忘记保存 ID，仍可用方向/历史 token 兜底：

**目标 pane 寻址语法（tmux 实际支持的 token，分两类）：**

| 语法 | 类别 | 含义 |
|------|------|------|
| `{top}` / `{bottom}` / `{left}` / `{right}` | 位置类（绝对） | 窗口中最上/下/左/右**那一个** pane（与 active 无关） |
| `{up-of}` / `{down-of}` / `{left-of}` / `{right-of}` | 相对类 | 当前 active pane 的上/下/左/右**邻居** |
| `{last}` | 历史类 | 上一个活动 pane（注意：`split-window` 后焦点在新 pane，此时 `{last}` 指**主 pane**——若想发到新 pane 须先切焦点或改用 pane ID） |
| `{next}` / `{previous}` | 历史类 | 按编号的下一个 / 上一个 pane |
| `%<id>` | ID（最稳） | 全局 pane ID，用 `tmux list-panes -F '#{pane_id}'` 查询 |

**踩坑提醒：**
- `{up}` 和 `{down}` **不存在**，写了会报错或目标错误
- `{right}` 是"窗口最右侧那个 pane"，**不是**"当前 pane 的右邻居"——两 pane 简单 layout 下两者恰好等价，但多 pane 时含义不同
- "当前 pane 右邻居" 是 `{right-of}`

**简单命令直接合并发送：**

```bash
tmux send-keys -t "$SIDE_PANE" "ssh dev-ae" Enter
```

**复杂/含特殊字符的命令分两步发送（与 TUI 程序交互时尤为重要）：**

```bash
tmux send-keys -t "$SIDE_PANE" -l "$cmd"   # -l 字面发送，不解释为快捷键
sleep 0.3
tmux send-keys -t "$SIDE_PANE" Enter
```

### Step 3：捕获输出

```bash
# 抓取最近 N 行（含历史滚动缓冲）
tmux capture-pane -t "$SIDE_PANE" -p -S -50

# 仅抓当前可见屏幕
tmux capture-pane -t "$SIDE_PANE" -p

# 抓全部历史
tmux capture-pane -t "$SIDE_PANE" -p -S -
```

**关键参数：**
- `-p`：打印到 stdout（缺失则保存到 buffer，需再 `tmux show-buffer` 取）
- `-S -50`：从倒数第 50 行开始（负数表示历史方向偏移）

**发送命令后等待输出：** 远程交互/慢命令需等待回显。短命令 sleep 1-2 秒再捕获即可；长命令循环捕获直到看到提示符。

### Step 4：基于输出做下一步

根据捕获结果决定继续发送什么命令。例如 SSH 登录后检测到 `[user@host]#` 提示符，再发送服务查询命令。

## 典型工作流模板

### 模板 A：SSH 远程服务诊断（默认右侧）

```bash
# 1. 右侧建 pane，立刻锁定 ID
SIDE_PANE=$(tmux split-window -h -p 40 -P -F '#{pane_id}')

# 2. SSH 连接
tmux send-keys -t "$SIDE_PANE" "ssh <host>" Enter
sleep 2
tmux capture-pane -t "$SIDE_PANE" -p -S -20   # 验证已登录

# 3. 查进程状态
tmux send-keys -t "$SIDE_PANE" "ps aux | grep <service> | grep -v grep" Enter
sleep 1
tmux capture-pane -t "$SIDE_PANE" -p -S -30

# 4. tail 日志（实时监控，不阻塞主 pane）
tmux send-keys -t "$SIDE_PANE" "tail -f /path/to/service.log" Enter
```

完成后主 pane 继续工作，侧边 pane 持续滚动日志。

### 模板 B：本地长任务并行运行（用户明确要求底部时）

```bash
# 仅当用户明确说"底部/下方"才用 -v；默认仍是右侧 -h
SIDE_PANE=$(tmux split-window -v -p 25 -P -F '#{pane_id}')
tmux send-keys -t "$SIDE_PANE" "npm run dev" Enter
# 主 pane 继续执行其他任务，无需等待 dev server
```

### 模板 C：多 pane 监控仪表板（用 pane ID 精确寻址）

```bash
# 主 pane + 右上（日志） + 右下（指标）
LOG_PANE=$(tmux split-window -h -p 40 -P -F '#{pane_id}')
METRICS_PANE=$(tmux split-window -v -t "$LOG_PANE" -P -F '#{pane_id}')

tmux send-keys -t "$LOG_PANE" "tail -f /var/log/app.log" Enter
tmux send-keys -t "$METRICS_PANE" "htop" Enter
```

多 pane 场景下方向 token 易混淆——**只要 pane 数 ≥ 3 就强制用 `%<id>` 寻址**。查询全部 pane ID：

```bash
tmux list-panes -F '#{pane_id} #{pane_current_command} #{pane_width}x#{pane_height}'
```

## 常用辅助命令

```bash
tmux list-panes -F '#{pane_id} #{pane_current_command}'   # 列出所有 pane
tmux kill-pane -t "$SIDE_PANE"                             # 关闭指定 pane
tmux select-pane -t "$SIDE_PANE"                           # 切换焦点（一般不需要）
tmux resize-pane -t "$SIDE_PANE" -R 10                     # 右扩 10 列
tmux clear-history -t "$SIDE_PANE"                         # 清空 pane 历史缓冲
```

## 反模式与陷阱

- **不要用 `{up}` / `{down}`** —— tmux 没有这两个 token。上下方向请用位置类 `{top}` / `{bottom}` 或相对类 `{up-of}` / `{down-of}`。
- **不要把 `{right}` 当作"右邻居"** —— `{right}` 是"窗口最右侧那个 pane"，与 active 无关。"当前 pane 的右邻居"是 `{right-of}`。两 pane 简单 layout 下两者结果相同，多 pane 时会指错目标。
- **不要在 split 后立刻 `select-pane` 回主 pane** —— `send-keys -t` 用目标语法寻址，与当前焦点无关，多余的 `select-pane` 只会干扰用户视觉焦点。
- **不要用 `tmux send-keys "$cmd Enter"`** —— Enter 必须是独立参数，作为按键发送，否则会变成字面字符串 "Enter"。
- **不要长时间不捕获就假定命令成功** —— SSH 可能因 key 问题卡在确认步骤，必须 capture 验证。
- **远程 tail -f 后**主 pane 别再 `send-keys` 到该 pane（除非用 `C-c` 先中断）—— 否则按键会被 tail 进程吞掉。
- **跨多 pane（≥3）时方向语法不可靠** —— layout 变化后 `{right}` / `{right-of}` 含义都可能变，关键流程一律用 `%<pane_id>` 固定目标，且 split 时用 `-P -F '#{pane_id}'` 即时锁定 ID。

## 常见服务的日志/状态路径速查

详细路径库见 [references/service-paths.md](references/service-paths.md)。包含 WebLogic、Tomcat、Nginx、Spring Boot、Docker、systemd 等常见服务的日志位置与状态查询命令。
