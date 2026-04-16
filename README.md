# Skills

Agent skills 合集，每个 skill 封装了与特定工具/服务交互的完整知识和操作规范。

## 目录

| Skill | 描述 | 环境变量 |
|-------|------|--------|
| [bruno](bruno/SKILL.md) | Bruno API 工具集：初始化项目、生成测试脚本、运行测试 | — |
| [jenkins](jenkins/SKILL.md) | 通过 REST API 触发、查询和管理 Jenkins Job | `JENKINS_API_TOKEN`、`JENKINS_USER` |
| [jira](jira/SKILL.md) | 通过 REST API 管理 Jira issue、评论、流转和 Sprint | `JIRA_PAT` |

## 结构约定

每个 skill 遵循统一的两层结构：

```
<skill-name>/
├── SKILL.md          # 主入口：行为规则、工作流、常用命令模板
└── references/       # 详细参考文档（端点、格式、示例）
```

- **SKILL.md**：Agent 调用时的主要指令文件，包含前置条件、鉴权流程、工作流规范和输出约定
- **references/**：专题参考文档，供 SKILL.md 按需引用，避免主文件过长

## 新增 Skill

1. 创建 `<skill-name>/SKILL.md`，添加 YAML frontmatter（`name`、`description`）
2. 在 `<skill-name>/references/` 下放置专题参考文档
3. 更新本文件的目录表
