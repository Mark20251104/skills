# Bruno Run — 运行测试脚本

使用 Bruno CLI 执行 `.bru` 测试脚本并报告结果。

## 前置条件

- 已安装 Bruno CLI：`npm install -g @usebruno/cli`
- 存在 `bruno-collection/` 目录与 `.bru` 测试文件
- 目标服务可访问（`baseUrl` 可达）

## 流程

1. `bru --version` 检查 CLI；未安装则提示用户安装
2. 确认 `bruno-collection/` 存在；否则提示先运行 `init`
3. 确认目录内有 `.bru` 文件；否则提示先运行 `case`
4. 执行测试并解读结果

## 命令参考

| 场景 | 命令 |
|------|------|
| 运行整个集合 | `bru run --env local bruno-collection/` |
| 运行指定子目录 | `bru run --env local bruno-collection/users/` |
| 运行单个文件 | `bru run --env local bruno-collection/users/get-users.bru` |
| 切换环境 | `bru run --env dev bruno-collection/` |
| 输出 JSON 报告 | `bru run --env local --reporter-json results.json bruno-collection/` |
| 输出 JUnit 报告（CI） | `bru run --env local --reporter-junit junit.xml bruno-collection/` |
| 输出 HTML 报告 | `bru run --env local --reporter-html report.html bruno-collection/` |
| 失败即停止 | `bru run --env local --bail bruno-collection/` |
| 跳过 TLS 校验（自签证书） | `bru run --env local --insecure bruno-collection/` |
| 临时覆盖变量 | `bru run --env local --env-var token=xxx bruno-collection/` |

## 结果解读

执行完成后汇总：通过 / 失败 / 跳过 数量。

失败用例需展示：
- 请求名称与文件路径
- 期望值 vs 实际值
- HTTP 状态码与响应片段

## 故障排查

| 现象 | 排查方向 |
|------|---------|
| `ECONNREFUSED` / 超时 | 目标服务未启动或 `baseUrl` 配置错误 |
| `401 / 403` | `token` 未填写或已过期；检查 `--env` 是否选错 |
| `bru: command not found` | 重新执行 `npm install -g @usebruno/cli` |
| TLS 证书错误 | 自签环境追加 `--insecure` |
| 变量未替换为值 | 检查环境文件变量名与 `{{var}}` 引用是否一致 |

## 约束

- 默认 `local` 环境，用户可显式指定其他环境
- 不自动修改 `.bru` 文件内容
- CI 中推荐 `--reporter-junit` + `--bail` 组合
- 禁止在命令行明文传入生产环境真实凭证（使用 CI Secret 注入）
