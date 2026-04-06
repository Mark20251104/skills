
# Bruno Run — 运行测试脚本

使用 Bruno CLI 执行 `.bru` 测试脚本并报告结果。

## 前置条件

- 已安装 Bruno CLI：`npm install -g @usebruno/cli`
- 已存在 `bruno-collection/` 目录及 `.bru` 测试文件

## 流程

1. 检查 Bruno CLI 是否已安装（`bru --version`），未安装则提示用户安装
2. 确认 `bruno-collection/` 目录存在，否则提示先运行 `init`
3. 确认目录内有 `.bru` 文件，否则提示先运行 `case` 生成测试
4. 执行测试并输出结果

## 命令参考

**运行整个集合：**
```bash
bru run --env local bruno-collection/
```

**运行指定目录：**
```bash
bru run --env local bruno-collection/users/
```

**运行单个文件：**
```bash
bru run --env local bruno-collection/users/get-users.bru
```

**指定环境：**
```bash
bru run --env dev bruno-collection/
```

**输出 JSON 报告：**
```bash
bru run --env local --output results.json bruno-collection/
```

## 结果解读

执行完成后：
- 汇总通过/失败/跳过的测试数量
- 对失败的测试，显示：请求名称、期望值 vs 实际值、HTTP 状态码
- 若有网络错误（连接拒绝、超时），提示检查目标服务是否运行

## 约束

- 运行前确认目标服务已启动（baseUrl 可访问）
- 默认使用 `local` 环境，用户可指定其他环境
- 不自动修改 `.bru` 文件内容
