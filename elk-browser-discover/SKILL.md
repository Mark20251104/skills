---
name: elk-browser-discover
description: 用 Chrome + Kibana Discover 界面查 tcg-uss-ae 的 10 套生产 ELK（F1–F7 / S1 / S2 / H1）日志。这是 prod-elk 脚本路径的兜底方案。Use when 用户明确要求走浏览器（如“在 Chrome 打开 / 用浏览器查看 / 新标签页看 ELK 或 Discover”），或 prod-elk 脚本不可用（keychain 缺失、权限拦截、脚本异常）。已在浏览器操作 Kibana 需要选数据视图、写 KQL、判读 ERROR 或使用 Dev Tools 时使用。默认优先使用 prod-elk 脚本路径。
---

# elk-browser-discover

Kibana Discover 界面查 uss-ae 生产日志。**这是兜底路径，不是默认路径。**

## 先确认该不该用本 skill

默认优先使用 `prod-elk` 脚本路径（免登录、可批量、结果可 `jq` 校验）。本 skill 仅在两种场景下使用：

1. **用户明确要求走浏览器**：需要人工查阅界面、截屏留档或实时盯盘图表。
2. **脚本路径不可用**：keychain 无凭据、权限拦截或脚本非零退出且短时间无法恢复。

其余情况请切回 `prod-elk`。因 10 套集群均采用自签证书，可能需要用户逐套手动登录；扫描两套以上前先告知人工登录成本并取得用户确认，批量取数优先走脚本。

## 凭据安全红线

**凭据由用户全权管理。严禁代输账号密码，严禁代点密码管理器的自动填充建议。**

正确动作：将标签页停在登录页，提示用户手动完成登录，确认完成后再继续执行。

跨站建议防范：Chrome 可能在不同环境的登录页跨站弹出其他集群凭据（如在 `tcg-f4.local` 弹出 `elk-platform.tcg.local` 账号）。看到此情况需明确提醒用户核实来源域名，避免累积登录失败触发账号保护。

## 集群地址

集群域名命名在不同系列间存在差异，请直接按以下权威地址访问：

```
F1  https://elk-platform.tcg.local        ← 注意：无环境后缀
F2  https://elk-platform.tcg-f2.local
F3  https://elk-platform.tcg-f3.local
F4  https://elk-platform.tcg-f4.local
F5  https://elk-platform.tcg-f5.local
F6  https://elk-platform.tcg-f6.local
F7  https://elk-platform.tcg-f7.local
S1  https://elk-platform.s1.local          ← 注意：无 tcg- 前缀
S2  https://elk-platform.s2.local
H1  https://elk-platform.h1.local
```

IP、传输模式与规模基线详见 `prod-elk` skill 目录下的 `references/clusters.md`（S1 仅为主流环境约 1/30，15 分钟内十余万条日志属正常业务规模）。

## Discover 操作流程

### 前置检查

执行浏览器交互前按序确认以下状态：
1. **Chrome 扩展连接**：调用 `tabs_context_mcp` 确认 Chrome 已连接。若提示 `Claude in Chrome is not connected`，重试 2 次；仍未连上则提示用户检查 Chrome 侧边栏连接状态。
2. **证书拦截页放行**：初次访问自签证书站点若弹出 Chrome 安全警告（`NET::ERR_CERT_AUTHORITY_INVALID`），**点击“高级”并点击“继续前往 <host>（不安全）”属于常规网络放行，不属于凭据认证操作，允许 Agent 直接执行**。
3. **登录态确认**：
   - 停留在 `/login`：停止自动交互，提示用户手动登录，待用户确认后继续。
   - 顶部已渲染 Kibana 菜单栏或位于 `/app/discover`：已具备登录态，直接开始操作。

### 步骤与完成判据（Completion Criteria）

直接导航至 `https://<host>/app/discover#/`。Kibana 冷启动较慢（首屏常需 15~25 秒），导航后串联两次等待（每次 10 秒），避免白屏误判。

1. **步骤 1：确认进入 Discover 界面**
   - 动作：导航至目标 URL，等待 DOM 渲染完成。
   - **完成判据**：页面 URL 包含 `/app/discover`，顶栏显示 Kibana 导航与数据视图选择器，页面无 `Loading Elastic` 白屏遮罩。

2. **步骤 2：筛选并切换数据视图**
   - 动作：点击左上角数据视图选择器，在筛选框中输入 `uss`（必须用搜索过滤，虚拟列表仅渲染前 ~11 项，见坑 ①），选择目标视图（`USS AE AP` 或 `USS AE Behavior`）。
   - **完成判据**：选择器当前选中文本更新为目标视图名称，且直方图完成重绘并无加载指示。

3. **步骤 3：调整时间范围**
   - 动作：点击右上角时间选择器，设置目标时间窗（默认 `Last 15 minutes`，或按需设定指定时间段）。
   - **完成判据**：时间选择器按钮文本更新为目标区间，直方图横坐标按目标区间重绘。

4. **步骤 4：提交 KQL 查询并获取数据**
   - 动作：在 KQL 搜索框输入查询表达式（真 ERROR 查 `message: "ERROR" and not message: "INFO"`），按回车或点击 Update。
   - **完成判据**：hits 计数刷新为确定数字，加载进度条消失，下方日志列表渲染出对应记录。

## 三个必踩的坑

### ① 数据视图下拉是虚拟列表，读到的不是全部

数据视图下拉列表使用虚拟 DOM，按字母序仅渲染前 ~11 项（截断在 M 附近），`USS *` 在 U 开头均未进 DOM。

**规则：必须在筛选框输入 `uss` 进行搜索**，等待过滤渲染后再选择目标视图，不可直接遍历或截屏读取原始未筛选列表。

### ② `message: "ERROR"` 会捞进 INFO 行，必须排除

在 Discover 的 KQL 框里查真 ERROR 用排除式：

```
message: "ERROR" and not message: "INFO"
```

为什么必须排除、字段未填充机制、已知业务码噪声模式、真 ERROR 分类基线与排查校验详见
`prod-elk` skill 目录下的 `references/error-baseline.md`（唯一权威来源，别在本 skill 复制）。

### ③ 判活性：首步绝对滞后，异常再补推进确认

三套时间同时存在且互不相等：日志正文里的时间（UTC+8）、`@timestamp`（UTC）、
Kibana 界面显示（按 Kibana 自己的时区设置）。**拿 `max(@timestamp)` 去减 Kibana 界面
读出的“现在”没有意义** —— 界面时间是 Kibana 时区，不是 UTC。这个减法曾导致误判
S2 和 H1「摄入延迟约 1 小时」，实际两套完全实时。

**但绝对滞后判断本身有效，只要拿对时钟：** `@timestamp` 的 `value_as_string` 是 UTC
（ISO 8601 带 Z），与 shell `date -u` 的输出相减有意义。只有“界面显示时间”和“日志
正文时间”不能当“现在”。

两步判定逻辑：

1. **第一步（必做）：绝对滞后判断**。Dev Tools 查 `max(@timestamp)`（必须带 `now-2h` 相对窗，
   主管道为 behavior；排查应用异常同理查 ap）：
   ```
   GET *uss_ae_behavior-*/_search
   {"size":1,"query":{"range":{"@timestamp":{"gte":"now-2h"}}},"sort":[{"@timestamp":"desc"}],"_source":["@timestamp"]}
   ```
   - 若返回结果为 `null` 或 hits 为 0：**直接判定停摆或严重滞后（>2h）**，不进第二步。
   - `LAG < 120s`：**正常近实时**，第一步直接通过。
   - `120s ~ 300s`：稍有缓冲延迟，可接受。
   - `LAG > 300s` 或 `LAG < 0`（时钟偏斜）：**补第二步推进确认**。
   - `LAG > 900s`：**判定异常滞后**。
2. **第二步（条件触发）：推进确认**。仅当第一步疑似异常时，间隔 30~60 秒对同一索引复测：
   - **推进量 > 间隔**：正在追赶（积压消耗中）。
   - **推进量 ≈ 间隔**：**恒定滞后**（积压未减，需报警）。
   - **0 < 推进量 < 间隔**：**持续掉队**（滞后扩大中）。
   - **推进量 ≤ 0**：停摆。

细则与脚本计算命令见 `prod-elk` skill 目录下的 `references/query-patterns.md` ①。

## Dev Tools 补充

Discover 拿不到的东西（索引清单、精确 count、聚合）走 `https://<host>/app/dev_tools#/console`。

两个操作坑：

- **Console 会恢复上次的内容。** 输入前先点进编辑器 → `cmd+a` → `Backspace`，
  且输入后**截图确认文本进去了再执行** —— 页面刚加载完时输入经常落空，
  直接 `cmd+Return` 会跑掉一条旧查询，而你以为跑的是新的。
- 执行是 `cmd+Return`（macOS）。

**只读红线：Console 只发 `GET`，且编辑器内仅保留当前一条单请求。** 浏览器路径没有
`prod-elk` 脚本那套端点白名单兜底，`dev` 是 superuser。而且 **Kibana Console 的 `cmd+Return`
执行的是光标所在的那一条请求块**而非首行；若编辑器内留存多条请求，仅首行是 `GET`
起不到防护作用。硬规则：
1. 输入前必须 `cmd+a` → `Backspace` **清空整个编辑器**，确保窗口内只有一条待发请求。
2. 请求必须且只能是 `GET`，目标限于 `_search`、`_count`、`_cat`、`_field_caps`、`_stats`
   及**无 body 的 `_mapping`**（禁止带 body 的 mapping 操作）。
3. 严禁任何 `POST`、`PUT`、`DELETE`。**执行前截图确认整屏仅这一条 `GET` 请求**，确认无误再 `cmd+Return`。

**别用猜的索引名代表整套集群的状态。** 数据视图指向的索引集合未必等于你拼出的通配符；
要判断某视图的数据，就在 Discover 里查那个视图，或先确认视图实际指向的索引
（判活性时用主管道索引族全通配 `*uss_ae_behavior-*` 加 `now-2h` 相对窗是明确例外，
由 ES `can_match` 阶段高效跳过无关分片）。

## 浏览器操作要点

- 用 `browser_batch` 把 navigate / wait / click / type / screenshot 串成一批，省往返
- 每套集群开一个新标签页，便于对照，也避免登录态互相干扰
- 扩展断连处理见前置检查 ①（重试 2 次，未恢复则提示用户检查扩展状态，不原地循环重试）
- 标签组里的标签页可能被用户或系统移走，`tabId` 会失效；报错时用 `tabs_context_mcp` 重新取列表

## 报告口径

扫多套集群时，固定给五列（集群、15min 日志量、全文命中、真 ERROR、主要错误类型）。
表头格式、日志量对 0 值的有效性约束与跨集群对比规范详见 `prod-elk` skill 目录下的
`references/error-baseline.md`。
