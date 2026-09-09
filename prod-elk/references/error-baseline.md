# uss-ae 应用日志错误分类基线

**这是 2026-09-08 一次巡检快照，不是长期基线。** 各集群取人工巡检时的 15 分钟窗口
（落在 2026-09-08 07:00Z–08:30Z 之间，非全集群绝对并发采样，横向对比仅作参考）。
错误构成会随版本和流量变，用它做**模式识别**（这条错误眼熟吗、是不是老问题），别用它
做阈值告警。

本文是 uss-ae 应用日志（`logstash-core_uss_ae_ap-*`，即 Discover 视图 `USS AE AP`）
错误语义的唯一权威来源。**两条取数路径共用**：prod-elk 的脚本 DSL 与
elk-browser-discover 的 Kibana KQL 读的是同一份 `message` 全文，下述口径两边通用，
别在任一 skill 复制。

## message 全文检索语义（先读这条）

`log_level` 字段**在所有集群都没有被填充**，按级别过滤（KQL `log_level: ERROR`、
DSL term 查询）恒返回 0 条，只能全文匹配 `message`。`message` 用标准分析器，
`[ERROR]` 与正文、INFO 业务码里的 `error` 分词后都是 `error`，无法区分级别 ——
**全文命中 ERROR 必然捞进 INFO 级业务码行**。

取真 ERROR 必须排除 INFO（真 ERROR 行不含 `[INFO ]` 标记，排除法实测干净有效）：

- KQL（elk-browser-discover 路径）：`message: "ERROR" and not message: "INFO"`
- DSL（elk-query 路径）：`match_phrase: {message: "ERROR"}` 且
  `must_not match_phrase: {message: "INFO"}`

下文的 INFO 噪声清单用于**一眼认出噪声**，不是白名单——别逐个排除，按级别排除。

**误排除风险与核验**：`not message: "INFO"` 为词元级排除。若真 ERROR 的 message 内含
`/customer/info` 等切词出 `info` 词元的 URI 或路径，会被连带排除。排查疑难问题时，
可抽样核验 `message: "ERROR" and message: "INFO"`（DSL: `must: [ERROR, INFO]`）子集，
确认无误杀真 ERROR。

## 报告口径（跨集群扫描固定列）

跨多套集群取数输出时，固定包含以下五列：

| 集群 | 15min 日志量 | 全文命中 | 真 ERROR | 主要错误类型 |

- **必须两口径并列**：单报全文命中会让跨集群对比严重失真（如 S2 全文命中 75 条全为 INFO，真 ERROR 实为 0）。
- **日志量决定 0 ERROR 的统计意义**：S1 仅 18 万条，0 ERROR 属无统计意义（期望值不足 1 条）；F7 在 1200 万条下的 0 才代表健康。

## 快照

采样时段：2026-09-08 07:00Z–08:30Z 间各集群人工巡检的 15 分钟窗口。
“全文命中” = `message` 匹配 `"ERROR"`；“真 ERROR” = 排除 INFO 后的数量。

| 集群 | 15min 日志量 | 全文命中 | 真 ERROR | 构成 |
| F1 | 8,662,250 | 8 | 8 | ORA-01013 ×5、异步上下文丢失 ×3 |
| F2 | 6,467,030 | 96 | ~96 ※ | **ORA-01795 ×90+**、ORA-12899、异步上下文丢失 |
| F3 | 8,070,810 | 1 | 1 | ORA-01013 ×1 |
| F4 | 8,968,014 | 5 | 3 | 异步上下文丢失 ×3（另 2 条 INFO 噪声） |
| F5 | 5,628,381 | 2 | 2 | 异步上下文丢失 ×2 |
| F6 | 6,902,500 | 2 | 2 | 异步上下文丢失 ×2 |
| F7 | 12,385,550 | 3 | 3 | 异步上下文丢失 ×2、Connection reset ×1 |
| S1 | 186,862 | 0 | 0 | — |
| S2 | 6,624,715 | 75 | **0** | 75 条全为 INFO 噪声 |
| H1 | 2,318,813 | 1 | 1 | 异步上下文丢失 ×1 |

※ F2 的 96 条中 90+ 条为一分钟内集中爆发的同一批 ORA-01795（traceId 前缀全同），
当时经抽样翻阅判定真 ERROR 约为 96；日常排查直接用排除式 KQL/DSL 取精确值。

S1 的 0 和 S2 的 0 含义不同：S1 是流量太小（约为主流环境 1/30）导致本就期望不到 1 条，
S2 是 662 万条里真的一条没有。

## 真 ERROR 类型

### 异步上下文丢失（跨集群系统性缺陷）

10 套里 7 套复现，是唯一的全环境问题。F4/F5/F6/H1 的 ERROR 100% 由它构成。

```
[ERROR] [customer-status-executor-N]
[SimpleAsyncUncaughtExceptionHandler.handleUncaughtException] (SimpleAsyncUncaughtExceptionHandler.java:39)
- Unexpected exception occurred invoking async method:
  com.tcg.uss.ae.service.async.CustomerStatusJob.processCustomerStatus(
    com.tcg.uss.ae.to.consumer.CustomerStatusConsumer)
  com.tcg.uss.ae.common.exception.UssBaseException: [invalid param] token and user agent must not be null
```

`@Async` 线程里拿不到请求上下文的 token / userAgent。跨环境、跨流量规模一致复现 ⇒
代码缺陷，与部署环境无关，别按环境问题去排查。

### ORA-01795（IN 列表超 1000）— F2 独有

10 套里只有 F2 出现，一分钟内爆发 90+ 条，traceId 前缀全部相同（同一批调用）。

```
[GlobalControllerExceptionHandler.handleException] (GlobalControllerExceptionHandler.java:38)
### Error querying database.
Cause: java.sql.SQLSyntaxErrorException: ORA-01795: maximum number of expressions in a list is 1000
```

集合直接拼进 `IN (...)` 未做 1000 一批的分片。只在 F2 触发 ⇒ 特定数据规模/调用方，
不是普遍路径。**它是唯一会随入参集合大小放大而爆发的问题**，量级上最唬人，
看到要优先定位。

### 低优先级背景噪声

| 错误 | 出现 | 说明 |
| --- | --- | --- |
| `ORA-01013: user requested cancel` | F1 ×5、F3 ×1 | JDBC queryTimeout 到期后主动 cancel，慢查询背景信号；日常低频无需单列事故，计数突增时需关联慢接口排名分析 |
| `ORA-12899: value too large for column ..."NICKNAME2" (actual: 81, maximum: 64)` | F2 | 昵称超长未截断，量极小 |
| `java.io.IOException: Connection reset by peer` | F7 ×1 | 对端断连，网络层抖动 |

## INFO 噪声（会被 ERROR 全文匹配误捞）

业务异常通常走 `GlobalControllerExceptionHandler.java:90`（截至 2026-09-08 快照），级别是 `[INFO ]`：

```
[INFO ] ... (GlobalControllerExceptionHandler.java:90) - [data_not_found] customer not found for customerId: ...
[INFO ] ... (GlobalControllerExceptionHandler.java:90) - [customer_nickname_error] customer nickname format error
[INFO ] ... (GlobalControllerExceptionHandler.java:90) - [customer_email_format_error] Customer Email format error
```

这三个只是当天抽到的，`[*_error]` 这类命名的业务码应该还有别的。**别把这个清单当白名单
去逐个排除** —— 按级别排除才是可靠做法，清单只用来帮你一眼认出“哦这条是噪声”。

> **关于 Java 类与行号的辅助性说明**：文档中提及的类名与代码行号（如 `GlobalControllerExceptionHandler.java:90`、
> `java:38`、`SimpleAsyncUncaughtExceptionHandler.java:39`）为截至 2026-09-08 版本快照的辅助参考，
> 随应用发布更新可能发生行号漂移。排查时应始终以日志正文中的 `[INFO ]` 与 `[ERROR]` 级别标记为**第一判据**，
> 类名与行号仅作为辅助识别依据。

## 判读顺序

1. 先看日志量级 —— 决定 0 ERROR 有没有意义
2. 再看真 ERROR 数（排除 INFO 后）
3. 再看构成：异步上下文丢失是老问题，ORA-01795 要警惕，ORA-01013 / Connection reset 属背景噪声（突增需关联慢接口分析）
4. 出现不在上表里的类型 ⇒ 值得单独下钻，按 traceId 追完整链路
