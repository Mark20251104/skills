---
name: jira
description: Interact with Jira via curl REST API for issue management, search, transitions, comments, sprints, and more. Use when the user asks to create/read/update/search Jira issues, check sprint status, add comments, transition issue status, assign issues, or perform any Jira operation. Requires JIRA_PAT environment variable.
---

# Jira

Interact with Jira Server/Data Center via curl and REST API v2. All operations require `$JIRA_PAT` environment variable.

## Prerequisites

Source shell environment and validate token before any curl operation:
```bash
source ~/.zshrc
[ -z "$JIRA_PAT" ] && echo "Error: JIRA_PAT environment variable not set" && return 1
```

## Configuration

```bash
JIRA="https://jira.tc-gaming.co/jira/rest/api/2"
AGILE="https://jira.tc-gaming.co/jira/rest/agile/1.0"
AUTH=(-H "Authorization: Bearer $JIRA_PAT")
JSON=(-H "Content-Type: application/json")
```

## Quick Reference

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Get issue | GET | `/issue/{key}` |
| Create issue | POST | `/issue` |
| Update issue | PUT | `/issue/{key}` |
| Search (JQL) | GET | `/search?jql=...` |
| Add comment | POST | `/issue/{key}/comment` |
| Transition | POST | `/issue/{key}/transitions` |
| Assign | PUT | `/issue/{key}/assignee` |
| Attachments | POST | `/issue/{key}/attachments` |

## Workflow

1. **Read operations** (get issue, search, list projects): Execute curl GET directly, pipe to `jq` for formatting
2. **Write operations** (create, update, comment): Build JSON payload, execute curl POST/PUT
3. **Transition**: Always GET transitions first to discover available transition IDs, then POST
4. **Bulk operations**: Use JQL search to find issues, then iterate

## Output Formatting

Always pipe results through `jq` for readability. Common patterns:

```bash
# Compact issue summary
| jq '{key: .key, summary: .fields.summary, status: .fields.status.name, assignee: .fields.assignee.displayName}'

# Search results table
| jq -r '.issues[] | [.key, .fields.status.name, .fields.summary] | @tsv'
```

## Issue Workflow Transitions

TCG Jira 的 issue 状态流转路径及对应 transition ID：

```
Open → [Assign To (11)] → In Progress → [Resolved (41)] → In Review → [Accepted (51)] → Closed
                                  ↘ [Req Incomplete (31)]          ↘ [Reject (61)]
Open → [Cancelled (21)] → Cancelled
```

### 快速关闭（Open → Closed）

从 Open 到 Closed 需要依次执行 3 个 transition：
```bash
# 1. Open → In Progress
curl -s -X POST "${AUTH[@]}" "${JSON[@]}" -d '{"transition":{"id":"11"}}' "$JIRA/issue/${KEY}/transitions"
# 2. In Progress → In Review
curl -s -X POST "${AUTH[@]}" "${JSON[@]}" -d '{"transition":{"id":"41"}}' "$JIRA/issue/${KEY}/transitions"
# 3. In Review → Closed
curl -s -X POST "${AUTH[@]}" "${JSON[@]}" -d '{"transition":{"id":"51"}}' "$JIRA/issue/${KEY}/transitions"
```

### 关闭时必须设置的字段

通过 API 逐步流转关闭 issue 时，`resolution` 字段不会自动设置（与 Jira UI 操作不同），导致 Closed 状态的 issue 没有绿色勾号。

**已知限制：** `resolution` 字段在 Closed 状态下无法通过 PUT `/issue/{key}` 直接设置（报错 "Field 'resolution' cannot be set. It is not on the appropriate screen"），且 Closed 状态无可用 transition 可退回。

**建议：** 在执行 "Resolved"（41）transition 时尝试附带 resolution：
```bash
curl -s -X POST "${AUTH[@]}" "${JSON[@]}" \
  -d '{"transition":{"id":"41"},"fields":{"resolution":{"name":"Resolved"}}}' \
  "$JIRA/issue/${KEY}/transitions"
```

### 关闭后常用自定义字段

| 字段名 | Field ID | 类型 | 示例值 |
|--------|----------|------|--------|
| ResolvedBy | customfield_11605 | User | `{"name":"mark.w"}` |
| ResolvedDate | customfield_11606 | DateTime | `"2026-04-06T09:50:00.000+0800"` |
| Workdays | customfield_11701 | Number | `1` |

**⚠️ Workdays 确认规则：** 在关闭 issue（设置 Workdays 字段）前，**必须**先向用户确认填写值，不得自动推断或默认为 1：

```
⚠️ 即将关闭 {KEY}，请确认 Workdays（工作天数）：
建议值：[基于上下文的推断，若无法推断则留空]
请输入实际工作天数（直接回复数字）：
```

收到用户确认后，再执行字段更新：
```bash
curl -s -X PUT "${AUTH[@]}" "${JSON[@]}" \
  -d '{"fields":{"customfield_11605":{"name":"mark.w"},"customfield_11701":<用户确认的值>}}' \
  "$JIRA/issue/${KEY}"
```

批量更新示例：
```bash
for key in TCG-XXX TCG-YYY; do
  curl -s -X PUT "${AUTH[@]}" "${JSON[@]}" \
    -d '{"fields":{"customfield_11605":{"name":"mark.w"},"customfield_11701":<用户确认的值>}}' \
    "$JIRA/issue/${key}"
done
```

## API Reference

For complete endpoint documentation, curl examples, JQL patterns, and error codes, see [references/api_reference.md](references/api_reference.md).
