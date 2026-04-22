---
name: bruno
description: Bruno（开源 API 测试工具）工作流：初始化 bruno-collection、基于 Controller/Router 源码生成 .bru 测试脚本（含多场景与前置数据准备）、通过 bru CLI 运行测试并输出报告。Use when user mentions Bruno、bru、.bru、bruno-collection、接口测试、API 测试脚本、API 自动化测试、bru run 等关键词。
version: "1.3"
updated: "2026-04-22"
---

# Bruno Skill

Bruno API 测试工作流：**初始化集合 → 生成测试脚本 → 运行测试**。

## 路由

按用户意图按需加载对应模块（不要预读全部）：

| 用户意图 | 加载文件 / 资源 |
|---------|----------------|
| 初始化项目 / 创建 `bruno-collection/` | `references/init.md`（调用 `scripts/init.sh`） |
| 为 API 端点生成 `.bru` 测试脚本 | `references/case.md` |
| 运行 `.bru` 测试并查看报告 | `references/run.md` |

## 全局约定

- 集合根目录固定为 `bruno-collection/`
- 环境变量统一使用 `{{variableName}}` 语法
- 禁止在脚本中硬编码真实 token、密码、密钥
