# Bruno Case — 生成测试脚本

分析业务代码，为 API 端点生成 `.bru` 测试文件。

## 流程

1. 从用户输入提取 HTTP 方法、路径、基础 URL
2. 定位对应的 Controller / Router / Handler 源码，提取：
   - **请求参数**：path、query、body（从方法签名、DTO/Schema）
   - **响应结构**：返回类型、VO/Response 类
   - **认证方式**：Bearer Token、API Key、Cookie 等
   - **校验规则**：`@Valid` / `@NotNull` / Zod schema 等必填字段
3. **询问分组名 `<group>`**（如需求号 / 模块名）；用户未提供则回退当前 git 分支名
4. 确定目标目录：`bruno-collection/<group>/<endpoint>/`
5. **依赖前置数据判断**：若目标 API 为 GET / PUT / PATCH / DELETE 等需操作既有资源的端点，先在源码中定位对应注册 / 创建 API（如 `POST /users`、`POST /auth/register`），生成前置 `00-setup-*.bru` 用例
6. 若 `bruno-collection/` 不存在，提示先运行 `init`
7. 生成 `.bru` 文件，已存在则跳过（除非用户要求覆盖）

## .bru 文件格式

> **语言约定**：`meta.name`、`test()` 描述、`docs` 块、行内注释一律使用中文（与代码库注释语言保持一致）。变量名、HTTP 方法、字段键名保持英文。

```bru
meta {
  name: 创建用户 - 正常场景
  type: http
  seq: 1
}

<method> {
  url: {{baseUrl}}<path>?<query>
  body: <none|json|form-urlencoded|multipart-form>
  auth: <none|bearer|basic|apikey>
}

params:query {
  page: 1
  size: 20
}

params:path {
  id: 1
}

headers {
  Content-Type: application/json
}

auth:bearer {
  token: {{token}}
}

body:json {
  {
    "key": "value"
  }
}

tests {
  test("状态码应为 200", function() {
    expect(res.status).to.equal(200);
  });

  test("响应应包含 data 字段", function() {
    const body = res.getBody();
    expect(body).to.have.property("data");
  });
}

docs {
  创建用户接口的正常场景：提交合法的用户名与邮箱，期望返回 200 与新建用户 ID。
}
```

## 参数处理规则

| 来源 | Bruno 块 | 示例 |
|------|---------|------|
| `@PathVariable` / `:id` | `params:path` + URL 内 `:id` 或 `{{id}}` | `/users/:id` |
| `@RequestParam` / `req.query` | `params:query` | `?page=1` |
| `@RequestBody` / `req.body` | `body:json` | JSON DTO |
| `@RequestHeader` | `headers` | `X-Trace-Id` |
| 认证 Token | `auth:bearer` + `{{token}}` | Bearer JWT |

## 断言规则

### 状态码断言（强制）

**每个 `.bru` 文件的 `tests` 块首条断言必须是状态码断言**，且必须与场景匹配：

```bru
tests {
  test("状态码应为 XXX", function() {
    expect(res.status).to.equal(XXX);
  });
  // ... 其余业务断言
}
```

### 正常场景默认状态码

| HTTP 方法 | 默认状态码 | 附加断言 |
|-----------|-----------|---------|
| GET       | 200 | 响应体非空、关键字段存在 |
| POST（创建） | 200 或 201 | 响应含 `id` 或关键字段（按源码返回决定 200/201） |
| PUT/PATCH | 200（或 204） | 响应含更新后字段（204 时断言 body 为空） |
| DELETE    | 200（或 204） | 204 时断言 body 为空 |

> 优先从源码实际返回值（Controller / ResponseEntity / handler return）判定 200 vs 201/204，不要盲目全填 200。

### 异常场景状态码映射

根据场景命名（见"文件命名"表）自动选择期望状态码：

| 场景类别 | 命名示例 | 期望状态码 | 附加断言 |
|---------|---------|-----------|---------|
| 正常 | `success` / `happy-path` | 200 / 201 | 关键字段存在 |
| 参数校验失败 | `missing-<field>` / `invalid-<field>` / `boundary-<case>` | 400 | 响应含错误信息字段（`message` / `errors`） |
| 未认证 | `unauthorized` | 401 | —— |
| 无权限 | `forbidden` | 403 | —— |
| 资源不存在 | `not-found` | 404 | —— |
| 方法不允许 | `method-not-allowed` | 405 | —— |
| 资源冲突 | `duplicate` / `conflict` | 409 | 响应含冲突原因 |
| 请求体过大 | `payload-too-large` | 413 | —— |
| 限流 | `rate-limited` | 429 | —— |
| 服务端异常（模拟） | `server-error` | 5xx | 仅在明确要求时生成 |

### 业务断言补充

基于源码分析额外生成：
- 响应字段类型断言（`expect(body.data.id).to.be.a("number")`）
- 必填字段非空断言（`expect(body.data.name).to.not.be.empty`）
- 数组长度断言（`expect(body.data.list).to.have.lengthOf.above(0)`）
- 枚举值断言（若 DTO 定义了固定集合）

### 异常用例示例

```bru
meta {
  name: 创建用户 - 邮箱格式非法
  type: http
  seq: 3
}

post {
  url: {{baseUrl}}/api/users
  body: json
  auth: none
}

body:json {
  {
    "name": "test",
    "email": "not-an-email"
  }
}

tests {
  test("状态码应为 400", function() {
    expect(res.status).to.equal(400);
  });

  test("响应应包含错误信息", function() {
    const body = res.getBody();
    expect(body).to.have.property("message");
  });
}
```

## 命名与组织

### 目录结构

固定两级：`bruno-collection/<group>/<endpoint>/`。

- `<group>`：**优先询问用户**指定（如需求号 `JIRA-123`、模块名 `user-mgmt`、版本号 `v2-api`）；用户未提供时回退使用当前 git 分支名 `git rev-parse --abbrev-ref HEAD`，并将 `/` 替换为 `-`
- `<endpoint>`：端点语义名，`<method>-<kebab-path>`，例：`POST /api/users` → `create-user`、`GET /api/users/{id}` → `get-user-by-id`

**询问示例**：
> 请提供本批用例的分组名（如需求号 / 模块名）。直接回车将使用当前分支名 `<branch>` 作为分组。

```
bruno-collection/
└── feature-user-mgmt/              # group（用户指定，回退用 branchName）
    ├── create-user/                # endpoint
    │   ├── 01-success.bru
    │   ├── 02-missing-required.bru
    │   ├── 03-invalid-email.bru
    │   ├── 04-duplicate-email.bru
    │   └── 05-unauthorized.bru
    ├── get-user-by-id/
    │   ├── 01-success.bru
    │   └── 02-not-found.bru
    └── delete-user/
        ├── 01-success.bru
        └── 02-forbidden.bru
```

### 文件命名

`<seq>-<scenario>.bru`，`scenario` 用语义化 kebab：

| 类别 | 命名示例 |
|------|---------|
| 正常 | `success` / `happy-path` |
| 参数校验 | `missing-<field>` / `invalid-<field>` |
| 业务错误 | `not-found` / `duplicate` / `conflict` |
| 鉴权 | `unauthorized` / `forbidden` |
| 边界值 | `boundary-<case>` |

### `seq` 规则

- 同端点目录内 `seq` 控制执行顺序
- **状态依赖**用例必须严格递增（如 create → get → update → delete）
- 无状态用例可乱序，建议 `success` 优先（`01-`）
- 路径变量 `{id}` / `:id` → `{{id}}`

### 单接口 vs 多场景

| 场景数 | 组织方式 |
|--------|---------|
| 单一正常用例 | 仍建一层 `endpoint/` 目录，文件命名为 `01-success.bru`，便于后续扩展 |
| 多场景 | 同目录下按上表分类，统一 `seq` 前缀 |

### 跨场景共享数据

后续场景需复用前序响应（如 `userId`、`token`）时，使用 Bruno 的 `vars:post-response` 写入环境变量，后续 `.bru` 以 `{{userId}}` 引用，禁止硬编码。

```bru
vars:post-response {
  userId: res.body.data.id
}
```

## 前置数据准备（Setup）

**适用场景**：目标 API 为 GET / PUT / PATCH / DELETE 等依赖既有资源的端点。

**原则**：测试自给自足，不依赖数据库已有数据；通过同集合内的注册 / 创建 API 即时生成所需资源。

### 流程

1. 在源码中定位资源的注册 / 创建端点（如 `POST /users`、`POST /auth/register`）
2. 在目标 endpoint 目录下生成 `00-setup-<resource>.bru`，`seq=0` 确保最先执行
3. setup 用例通过 `vars:post-response` 捕获关键字段（`id`、`token`、唯一键等）写入环境变量
4. 后续场景以 `{{xxxId}}` / `{{token}}` 引用
5. 如需清理，再追加 `99-teardown-<resource>.bru` 调用对应删除 API

### 示例

```
bruno-collection/
└── feature-user-mgmt/
    └── get-customer-by-id/
        ├── 00-setup-register-customer.bru   # 注册新用户，捕获 customerId
        ├── 01-success.bru               # 使用 {{customerId}} 查询
        ├── 02-not-found.bru             # 故意传错 ID
        └── 99-teardown-delete-customer.bru  # 可选：清理用户
```

**00-setup-register-customer.bru** 关键片段：

```bru
meta {
  name: 前置 - 注册客户
  type: http
  seq: 0
}

post {
  url: {{baseUrl}}/api/register
  body: json
  auth: none
}

body:json {
  {
    "name": "test-customer-{{$randomInt}}",
    "email": "test-{{$timestamp}}@example.com"
  }
}

vars:post-response {
  customerId: res.body.data.id
}

tests {
  test("前置数据准备成功", function() {
    expect(res.status).to.equal(200);
    expect(res.body.data).to.have.property("id");
  });
}

docs {
  为后续依赖客户资源的查询/更新/删除用例注册新客户，并将 customerId 写入环境变量。
}
```

### 约束

- setup 用例失败应阻断后续执行（CI 配合 `bru run --bail`）
- 唯一字段（email、customername）使用 `{{$timestamp}}` / `{{$randomInt}}` 避免冲突
- 共享多端点的 setup 不重复生成；同 `<group>` 内可复用同一环境变量
- 若注册 API 本身已有 `01-success.bru` 用例并捕获了变量，可直接在依赖端点目录用 `vars:pre-request` 复用，不必重复 setup

## 约束

（全局约定见 `SKILL.md`：固定根目录、`{{var}}` 语法、禁硬编码凭证）

- 不覆盖已有 `.bru` 文件，除非用户明确要求
- 优先使用用户提供的真实响应体生成断言
- 无法定位源码时，退回基于 URL 与 HTTP 方法的通用断言
- **中文描述**：`meta.name`、`test()` 描述、`docs` 块、行内注释统一使用中文；保留英文的仅限：变量名、HTTP 方法、JSON 字段键名、URL 路径
