# Skills

Agent skills 合集，每个 skill 封装了与特定工具/服务交互的完整知识和操作规范。

## 目录

| Skill | 描述 | 环境变量 |
|-------|------|--------|
| [bruno](bruno/SKILL.md) | Bruno API 工具集：初始化项目、生成测试脚本、运行测试 | — |
| [elk-browser-discover](elk-browser-discover/SKILL.md) | 用 Chrome + Kibana Discover 界面人工查 tcg-uss-ae 的 10 套生产 ELK 日志（prod-elk 脚本路径的兜底方案） | — |
| [jenkins](jenkins/SKILL.md) | 通过 REST API 触发、查询和管理 Jenkins Job | `JENKINS_API_TOKEN`、`JENKINS_USER` |
| [jira](jira/SKILL.md) | 通过 REST API 管理 Jira issue、评论、流转和 Sprint | `JIRA_PAT` |
| [prod-elk](prod-elk/SKILL.md) | 只读查询 tcg-uss-ae 的 10 套生产 ELK 集群日志（行为日志、异常栈、慢请求排名、traceId 追踪） | macOS keychain `elk-readonly` |
| [tmux-pane](tmux-pane/SKILL.md) | 在当前 tmux 会话中创建并驱动侧边 pane（默认右侧），用于 SSH、日志监控、并行命令 | — |

## 结构约定

每个 skill 遵循统一的两层结构：

```
<skill-name>/
├── SKILL.md          # 主入口：行为规则、工作流、常用命令模板
├── references/       # 详细参考文档（端点、格式、示例）
└── scripts/          # 可选：可执行封装（bruno、prod-elk 有）
```

- **SKILL.md**：Agent 调用时的主要指令文件，包含前置条件、鉴权流程、工作流规范和输出约定
- **references/**：专题参考文档，供 SKILL.md 按需引用，避免主文件过长
- **scripts/**：把鉴权、端点白名单、环境映射等易错细节封装成一条命令，
  让 SKILL.md 只需描述"查什么"而不必重复"怎么连"

## 新增 Skill

1. 创建 `<skill-name>/SKILL.md`，添加 YAML frontmatter（`name`、`description`）
2. 在 `<skill-name>/references/` 下放置专题参考文档
3. 更新本文件的目录表

### scripts/ 的约定

- **凭据绝不进 argv，也不落盘**：argv 会出现在 `ps` 输出和 shell history 里。
  从 keychain / 环境变量现取，经 stdin 或进程替换（`--config <(...)`）传给下游。
  用 `mktemp` 写临时凭据文件的写法要特别小心——**结尾若用 `exec`，`trap ... EXIT`
  不会触发，明文凭据会永久残留**。
- **失败必须有非零退出码**：HTTP 4xx/5xx 默认不会让 curl 失败，agent 会把错误
  响应体当数据用。加 `--fail-with-body`（保留错误体的同时返回 22）。
- **只读封装用端点白名单**：防的是误操作，不防有写权限的调用方。
- **调用方写绝对路径**：Claude Code 的权限规则按命令字符串前缀匹配，
  `"$VAR" args` 形式匹配不上会被拦。SKILL.md 的模板里不要把脚本路径写成变量。
