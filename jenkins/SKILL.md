---
name: jenkins
description: Use when the user asks to trigger, inspect, or manage Jenkins jobs via REST API, especially on the test Jenkins instance at dev-jenkins03.tc168.cloud. Requires JENKINS_API_TOKEN environment variable.
---

# Jenkins

通过 REST API 操作测试 Jenkins：

```bash
JENKINS_BASE="https://dev-jenkins03.tc168.cloud"
```

所有操作默认要求环境变量：

```bash
source ~/.zshrc
[ -z "$JENKINS_API_TOKEN" ] && echo "Error: JENKINS_API_TOKEN environment variable not set" && return 1
```

## 鉴权

优先按以下顺序处理鉴权：

1. 如果已设置 `JENKINS_USER`，使用 Basic Auth：
```bash
AUTH=(--user "$JENKINS_USER:$JENKINS_API_TOKEN")
```
2. 如果只有 `JENKINS_API_TOKEN`，先尝试 Bearer：
```bash
AUTH=(-H "Authorization: Bearer $JENKINS_API_TOKEN")
```
3. 如果返回 `401/403` 且只有 token，没有用户名，不要盲猜用户名，先告知用户 Jenkins 可能要求 `JENKINS_USER + API Token`

## Crumb

写操作前先尝试获取 crumb；如果接口不存在或返回空，再直接发请求：

```bash
CRUMB_JSON=$(curl -fsS "${AUTH[@]}" "$JENKINS_BASE/crumbIssuer/api/json" 2>/dev/null || true)
if [ -n "$CRUMB_JSON" ]; then
  CRUMB_FIELD=$(printf '%s' "$CRUMB_JSON" | jq -r '.crumbRequestField')
  CRUMB_VALUE=$(printf '%s' "$CRUMB_JSON" | jq -r '.crumb')
  CRUMB=(-H "$CRUMB_FIELD: $CRUMB_VALUE")
else
  CRUMB=()
fi
```

## Job Path 规则

- 顶层 job：`/job/<job-name>`
- 文件夹中的 job：`/job/<folder>/job/<job-name>`
- 多层文件夹按此规则继续拼接

在执行触发、查询、日志拉取前，先确认 job 路径是否正确。

## 常用工作流

1. 读操作：优先 `GET .../api/json`，并用 `jq` 提取关键信息
2. 触发构建：无参用 `/build`，有参用 `/buildWithParameters`
3. 参数化构建前，必须先向用户确认参数名和值；不要自行猜测、补默认值或构造示例参数去实际触发
4. 触发成功后，默认继续跟踪执行：先看队列项，再跟到具体 build 编号，再持续查询直到 `building=false`
5. 任务失败时，默认继续查询 `/consoleText`，提取最后一段关键日志并确认失败原因；不要停留在“构建失败”的表面结论
6. 输出结果时，优先返回：job 名、queue id、build number、result、url；失败时附上明确失败原因或最接近根因的日志片段
7. 失败处理：优先反馈 HTTP 状态码、响应体、请求 URL，不要只说“失败”

## 常用命令模板

### 读取 Job 信息

```bash
JOB_PATH="/job/example"
curl -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/api/json" | jq '{name: .name, color: .color, inQueue: .inQueue, nextBuildNumber: .nextBuildNumber}'
```

### 触发无参 Job

```bash
JOB_PATH="/job/example"
curl -i -X POST "${AUTH[@]}" "${CRUMB[@]}" "$JENKINS_BASE$JOB_PATH/build"
```

### 触发带参数 Job

```bash
JOB_PATH="/job/example"
# 先向用户确认每个参数的名称和值，再替换下面的占位符
curl -i -X POST "${AUTH[@]}" "${CRUMB[@]}" \
  "$JENKINS_BASE$JOB_PATH/buildWithParameters" \
  --data "<param1>=<value1>" \
  --data "<param2>=<value2>"
```

### 查询最近一次构建

```bash
JOB_PATH="/job/example"
curl -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/lastBuild/api/json" | jq '{number: .number, result: .result, building: .building, url: .url}'
```

### 从队列持续跟踪到构建结束

```bash
JOB_PATH="/job/example"
QUEUE_ID=456

# 先跟踪队列，直到拿到 build number
while true; do
  QUEUE_JSON=$(curl -fsS "${AUTH[@]}" "$JENKINS_BASE/queue/item/$QUEUE_ID/api/json")
  BUILD_NUMBER=$(printf '%s' "$QUEUE_JSON" | jq -r '.executable.number // empty')
  if [ -n "$BUILD_NUMBER" ]; then
    break
  fi
  printf '%s' "$QUEUE_JSON" | jq '{id, blocked, buildable, stuck, cancelled, why, task: .task.name}'
  sleep 5
done

# 再跟踪 build，直到结束
while true; do
  BUILD_JSON=$(curl -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/$BUILD_NUMBER/api/json")
  BUILDING=$(printf '%s' "$BUILD_JSON" | jq -r '.building')
  RESULT=$(printf '%s' "$BUILD_JSON" | jq -r '.result')
  printf '%s' "$BUILD_JSON" | jq '{number, result, building, duration, estimatedDuration, url}'
  if [ "$BUILDING" = "false" ]; then
    break
  fi
  sleep 10
done

# 失败时自动拉控制台日志，确认失败原因
if [ "$RESULT" != "SUCCESS" ]; then
  curl -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/$BUILD_NUMBER/consoleText" | tail -n 80
fi
```

### 拉取构建日志

```bash
JOB_PATH="/job/example"
BUILD_NUMBER=123
curl -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/$BUILD_NUMBER/consoleText"
```

## 输出约定

- JSON 响应用 `jq` 格式化
- 汇总信息时优先返回：job 名、build number、result、url
- 触发操作若返回 `201 Created` 或 `302`，说明通常已成功进入队列
- 触发构建后，不要只返回“已触发”；默认继续跟踪到成功、失败或明确卡住
- 若构建失败，返回失败原因；至少提供控制台日志尾部的关键报错

## 安全约束

- 默认只操作测试 Jenkins：`https://dev-jenkins03.tc168.cloud`
- 不删除 job，不修改系统级配置
- 写操作前明确目标 job 路径和参数
- 若是参数化构建，参数必须来自用户明确提供；不得为了“方便”自行构造 `branch`、`env` 或其他参数
- 如果需要 `script console`、凭据、节点管理等高风险接口，先征得用户确认

## API Reference

完整端点、状态跟踪和示例见 [references/api_reference.md](references/api_reference.md)。
