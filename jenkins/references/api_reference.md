# Jenkins REST API Reference

测试环境基础地址：

```bash
JENKINS_BASE="https://dev-jenkins03.tc168.cloud"
```

## 前置变量

```bash
source ~/.zshrc
[ -z "$JENKINS_API_TOKEN" ] && echo "Error: JENKINS_API_TOKEN environment variable not set" && return 1
[ -z "$JENKINS_USER" ] && echo "Error: JENKINS_USER environment variable not set" && return 1
```

推荐鉴权顺序：

```bash
# 方案 1：Jenkins 标准 Basic Auth
AUTH=(--user "$JENKINS_USER:$JENKINS_API_TOKEN")

# 方案 2：网关支持 token header 时使用
AUTH=(-H "Authorization: Bearer $JENKINS_API_TOKEN")
```

可选 crumb：

```bash
CRUMB_JSON=$(curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE/crumbIssuer/api/json" 2>/dev/null || true)
if [ -n "$CRUMB_JSON" ]; then
  CRUMB_FIELD=$(printf '%s' "$CRUMB_JSON" | jq -r '.crumbRequestField')
  CRUMB_VALUE=$(printf '%s' "$CRUMB_JSON" | jq -r '.crumb')
  CRUMB=(-H "$CRUMB_FIELD: $CRUMB_VALUE")
else
  CRUMB=()
fi
```

## 常用端点

| 操作 | Method | Endpoint |
|------|--------|----------|
| Jenkins 根信息 | GET | `/api/json` |
| Job 信息 | GET | `/<job-path>/api/json` |
| 触发无参构建 | POST | `/<job-path>/build` |
| 触发参数化构建 | POST | `/<job-path>/buildWithParameters` |
| 最近一次构建 | GET | `/<job-path>/lastBuild/api/json` |
| 指定构建详情 | GET | `/<job-path>/<build-number>/api/json` |
| 构建日志 | GET | `/<job-path>/<build-number>/consoleText` |
| 队列项详情 | GET | `/queue/item/<queue-id>/api/json` |
| Crumb | GET | `/crumbIssuer/api/json` |

`<job-path>` 示例：

```text
/job/my-job
/job/folder-a/job/my-job
/job/folder-a/job/folder-b/job/my-job
```

## 常见操作示例

### 1. 查看 Jenkins 首页可见 job

```bash
curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE/api/json" | jq -r '.jobs[] | [.name, .url] | @tsv'
```

### 2. 查看单个 Job

```bash
JOB_PATH="/job/example"
curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/api/json" \
  | jq '{name: .name, description: .description, color: .color, buildable: .buildable, nextBuildNumber: .nextBuildNumber}'
```

### 3. 触发无参构建

```bash
JOB_PATH="/job/example"
curl -k -i -X POST "${AUTH[@]}" "${CRUMB[@]}" "$JENKINS_BASE$JOB_PATH/build"
```

返回头里常见：

- `201 Created`
- `Location: https://.../queue/item/<id>/`

### 4. 触发参数化构建

注意：

- 这里的参数名和值必须先由用户明确提供
- 不要自行猜测参数、补默认值，或把示例参数直接用于真实触发

```bash
JOB_PATH="/job/example"
# 先向用户确认每个参数的名称和值，再替换下面的占位符
curl -k -i -X POST "${AUTH[@]}" "${CRUMB[@]}" \
  "$JENKINS_BASE$JOB_PATH/buildWithParameters" \
  --data "<param1>=<value1>" \
  --data "<param2>=<value2>"
```

### 5. 跟踪队列到具体构建号

如果响应头里拿到了队列地址：

```bash
QUEUE_ID=456
curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE/queue/item/$QUEUE_ID/api/json" | jq .
```

常见关注字段：

```bash
curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE/queue/item/$QUEUE_ID/api/json" \
  | jq '{blocked: .blocked, buildable: .buildable, stuck: .stuck, cancelled: .cancelled, executable: .executable}'
```

当 `.executable.number` 出现时，表示已经分配到具体 build：

```bash
BUILD_NUMBER=$(curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE/queue/item/$QUEUE_ID/api/json" | jq -r '.executable.number')
```

### 6. 持续跟踪直到构建结束

不要只查一次状态。触发后应持续轮询，直到构建结束或明确卡住。

```bash
JOB_PATH="/job/example"
BUILD_NUMBER=123

while true; do
  BUILD_JSON=$(curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/$BUILD_NUMBER/api/json")
  BUILDING=$(printf '%s' "$BUILD_JSON" | jq -r '.building')
  RESULT=$(printf '%s' "$BUILD_JSON" | jq -r '.result')
  printf '%s' "$BUILD_JSON" | jq '{number: .number, result: .result, building: .building, duration: .duration, estimatedDuration: .estimatedDuration, timestamp: .timestamp, url: .url}'
  if [ "$BUILDING" = "false" ]; then
    break
  fi
  sleep 10
done
```

### 7. 查询构建结果

```bash
JOB_PATH="/job/example"
BUILD_NUMBER=123
curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/$BUILD_NUMBER/api/json" \
  | jq '{number: .number, result: .result, building: .building, duration: .duration, timestamp: .timestamp, url: .url}'
```

### 8. 构建失败后查看控制台日志

```bash
JOB_PATH="/job/example"
BUILD_NUMBER=123
curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/$BUILD_NUMBER/consoleText"
```

如果只是为了快速定位失败原因，优先看日志尾部：

```bash
curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/$BUILD_NUMBER/consoleText" | tail -n 80
```

推荐顺序：

1. 先确认 `result` 是否为 `FAILURE`、`ABORTED` 或 `UNSTABLE`
2. 再抓 `/consoleText` 尾部，提取最接近根因的报错
3. 对用户汇报时，不要只说“失败”，要说明失败点，例如“找不到分支”“单元测试失败”“制品上传失败”

## 诊断建议

### 401 Unauthorized

- token 无效
- Jenkins 需要 `JENKINS_USER + API Token`
- Bearer 模式不被当前 Jenkins / 网关接受

### 403 Forbidden

- 账号无权限
- 需要 crumb
- 该 job 限制了 Build 权限

### 404 Not Found

- job 路径写错
- 文件夹层级少写了 `/job/`
- build number 不存在

### 触发成功但未执行

先检查：

```bash
curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE/queue/item/$QUEUE_ID/api/json" | jq .
```

重点看：

- `.why`
- `.blocked`
- `.stuck`
- `.cancelled`
- `.task.name`

### 已执行但构建失败

先检查：

```bash
curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/$BUILD_NUMBER/api/json" \
  | jq '{number, result, building, duration, url}'
curl -k -fsS "${AUTH[@]}" "$JENKINS_BASE$JOB_PATH/$BUILD_NUMBER/consoleText" | tail -n 80
```

输出时优先包含：

- build number
- result
- build url
- 明确失败原因
- 支撑该结论的关键日志片段

## 推荐输出格式

### Job 摘要

```bash
| jq '{name: .name, color: .color, inQueue: .inQueue, nextBuildNumber: .nextBuildNumber}'
```

### 构建摘要

```bash
| jq '{number: .number, result: .result, building: .building, duration: .duration, url: .url}'
```

### Job 列表

```bash
| jq -r '.jobs[] | [.name, .url] | @tsv'
```
