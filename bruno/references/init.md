
# Bruno Init

在项目根目录创建 `bruno-collection/` 并初始化环境。

## 流程

1. 检测项目根目录（含 `pom.xml`/`package.json`/`build.gradle`/`go.mod` 的目录，否则用当前目录）
2. 若 `bruno-collection/` 已存在，提示用户并终止
3. 创建以下结构并写入文件：

```
bruno-collection/
├── bruno.json
├── environments/
│   ├── local.bru
│   └── dev.bru
└── .gitignore
```

## 文件模板

**bruno.json**（`name` 取项目目录名）：
```json
{
  "version": "1",
  "name": "<项目目录名>",
  "type": "collection",
  "ignore": []
}
```

**environments/local.bru**：
```
vars {
  baseUrl: http://localhost:8080
  token: 
}
```

**environments/dev.bru**：
```
vars {
  baseUrl: https://api.example.com
  token: 
}
```

**.gitignore**：
```
environments/dev.bru
```

## 约束

- 环境变量使用 `{{variableName}}` 语法
- `dev.bru` 默认被 `.gitignore` 忽略，防止敏感信息泄露
