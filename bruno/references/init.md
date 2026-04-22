# Bruno Init

在项目根目录创建 `bruno-collection/` 并初始化环境配置。

## 流程

1. 检测项目根目录（含 `pom.xml` / `package.json` / `build.gradle` / `go.mod`，否则使用当前目录）
2. 调用 `scripts/init.sh <project-root>`（不传参数则使用当前目录）
3. 脚本检测 `bruno-collection/` 已存在时会自动终止，避免覆盖

## 生成结构

```
bruno-collection/
├── bruno.json              # 集合元数据，name 取项目目录名
├── .gitignore              # 忽略本地敏感凭证文件
└── environments/
    ├── local.bru           # baseUrl: http://localhost:8080
    ├── dev.bru             # baseUrl: http://10.80.0.25:7001
    └── sit.bru             # baseUrl: http://10.80.1.22:7001
```

所有环境文件均预留 `token:` 空值，由使用者按环境填写。

## 新增环境

如需新增环境（如 `prod.bru`、`uat.bru`），按现有 `*.bru` 模板复制并修改 `baseUrl`：

```
vars {
  baseUrl: <目标地址>
  token:
}
```

## 约束

- 禁止提交真实 `token`、密码、密钥到版本库
- 跨开发者共享凭证应通过 CI Secret 或 `.local.bru`（已被 `.gitignore`）
