
# Bruno Case — 生成测试脚本

分析业务代码，为 API 端点生成 `.bru` 测试文件。

## 流程

1. 从用户输入提取 HTTP 方法、路径、基础 URL
2. 定位对应的 Controller/Router/Handler 源码，提取：
   - 请求参数（path、query、body）及类型（从方法签名、DTO/Schema 类）
   - 响应结构（从返回类型、VO/Response 类）
   - 认证方式（Bearer Token、API Key 等）
   - 校验规则（`@Valid`、`@NotNull`、Zod schema 等必填字段）
3. 生成 `.bru` 文件到 `bruno-collection/{branchName}`（若不存在，提示先运行 `init`）

## .bru 文件格式

```bru
meta {
  name: <请求名称>
  type: http
  seq: <序号>
}

<method> {
  url: {{baseUrl}}<path>
  body: <none|json|form-urlencoded>
  auth: <none|bearer>
}

headers {
  Content-Type: application/json
}

body:json {
  {
    "key": "value"
  }
}

tests {
  test("status 200", function() {
    expect(res.status).to.equal(200);
  });

  test("response has data", function() {
    const body = res.getBody();
    expect(body).to.have.property("data");
  });
}
```

## 断言规则

所有正常用例统一断言状态码 200（除非是异常用例或用户明确指定其他状态码）。

| HTTP 方法 | 默认断言 |
|-----------|---------|
| GET       | 状态码 200、响应体非空、关键字段存在 |
| POST      | 状态码 200、响应含 id 或关键字段 |
| PUT/PATCH | 状态码 200、响应含更新后字段 |
| DELETE    | 状态码 200 |

基于代码分析额外生成：响应字段类型断言、必填字段非空断言、数组长度断言。

## 命名与组织

- 文件名：`<method>-<kebab-path>.bru`，如 `/api/users/{id}` → `get-user-by-id.bru`
- `seq` 按生成顺序递增
- 路径变量 `{id}` → `{{id}}`
- 多接口按资源分组为子目录：

```
bruno-collection/
└── users/
    ├── get-users.bru
    ├── get-user-by-id.bru
    ├── create-user.bru
    └── delete-user.bru
```

## 约束

- 不覆盖已有 `.bru` 文件，除非用户明确要求
- 环境变量使用 `{{variableName}}` 语法
- 若用户提供响应体示例，优先用实际字段生成断言
- 若无法定位源码，退回基于 URL 和 HTTP 方法的通用断言
