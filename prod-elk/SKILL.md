---
name: prod-elk
description: 查询 tcg-uss-ae 的 10 套生产 ELK 集群（F1–F7 / S1 / S2 / H1）日志。Use when 需要查行为日志、应用日志、慢请求排名、异常栈、traceId 追踪、接口耗时分位数、跨环境指标对比，或用户提到 ELK、Kibana、Elasticsearch、elk-platform、Discover、logstash-core_uss_ae。
---

# prod-elk

查 tcg-uss-ae 生产日志。**不要走 Kibana Discover UI，也不要建 API Key**——用本 skill
自带的脚本。

例外只有两个：用户明确要求走浏览器界面（要自己看、要截图），或本脚本路径确实断了
（keychain 无凭据、权限规则未配、脚本非零退出且短期修不好）。这两种情况走
`elk-browser-discover` skill，它记录了 Discover 的操作流程和那条路上的坑。
其余情况一律用脚本——浏览器路径每套集群都要用户手动登录，扫 10 套就是 10 次。

## 用法

脚本在本 skill 目录下，文档里一律以相对路径称呼它：

```
scripts/elk-query <env> <path> [json-body | -]
```

`env` = `f1`…`f7` `s1` `s2` `h1`。不带参数运行看完整用法。

```bash
scripts/elk-query f1 '/_cat/indices/*uss_ae_behavior-2026.09.04*?h=index,docs.count,store.size&s=index:asc'
```

### 执行时展开成绝对路径

**相对路径是文档写法，不是执行写法。** 真正跑命令时把 `scripts/` 换成本
skill 所在目录的绝对路径 `<SKILL_DIR>`（由实际加载的 skill 目录展开，例如当前环境下的实际路径），拼成一条完整路径直接写进命令行：

```
SKILL_DIR = <实际加载的 skill 目录绝对路径，例如 /path/to/prod-elk/>
```

上面那条示例展开后即（执行时以实际 `<SKILL_DIR>` 绝对路径替换）：

```bash
<SKILL_DIR>/scripts/elk-query f1 '/_cat/indices/*uss_ae_behavior-2026.09.04*?h=index,docs.count,store.size&s=index:asc'
```

两个坑，都会让命令跑不起来：

- **不能真用相对路径执行。** agent 的 cwd 是项目目录，不是 skill 目录，
  `scripts/elk-query` 会 `No such file`。
- **不能塞进 shell 变量再引用。** 权限规则按命令字符串前缀匹配，
  `"$ELK" f1 ...` 或 `"$SKILL_DIR/scripts/elk-query" f1 ...` 都匹配不上，会被拦。
  必须每次把由实际加载路径展开后的完整绝对路径**字面**写在命令开头。

`~/.local/bin/elk-query` 是指向同一文件的 symlink，仅为人工在终端敲短命令方便；
**skill 不依赖它**，删掉不影响 skill 工作。

## 权限规则

宿主环境（如 `~/.claude/settings.json`）的 `permissions.allow` 需含（与上面实际加载的 `SKILL_DIR` 保持一致，
改动安装位置时两处要一起改）：

```json
"Bash(<SKILL_DIR>/scripts/elk-query:*)"
```

`Bash(*)` 这种宽泛通配**不足以**让 auto mode classifier 放行脚本内读 keychain 的操作，
必须是这条具体规则。（另有 `Bash(elk-query:*)` 对应 symlink 短命令，非必需。）

## 凭据

口令从 macOS keychain（service `elk-readonly`，用户 `dev`）现取，经进程替换
（`--config <(...)`，走 `/dev/fd`）喂给 curl：**既不进 argv，也不落盘**。缺失时脚本
会提示创建命令。

端点白名单只放行 `_cat` `_search` `_count` `_msearch` `_mapping` `_field_caps`
`_stats` `_resolve` `_cluster/health` `_cluster/state/metadata` `_nodes/stats`。
`_mapping` 只允许无 body 的 GET；带 body 会被拒（POST/PUT 会改索引 mapping）。
完整主机名只接受这 10 套已知集群，不要传任意 `*.local`。
白名单防的是误操作，不防有写权限的调用方。

## 退出码

脚本用 `--fail-with-body`，HTTP 错误会同时给出**非零退出码**和 **ES 的错误 JSON**。
别只看 stdout 有没有 JSON 就当成功：

| 码 | 含义 | 处置 |
| ---: | --- | --- |
| 0 | HTTP 2xx | 正常，但仍需做下面纪律 ④ 的完整性检查 |
| 22 | HTTP 非 2xx | 读 stdout 里的 `error.reason`（索引不存在、DSL 语法错等） |
| 28 | curl 超时 | 见纪律 ③；`kibana` 模式加大 `ELK_TIMEOUT` 无用 |
| 2 / 3 / 4 / 5 | 未知环境 / path 被白名单拒 / keychain 无凭据 / 未知传输模式 | 见 stderr |

## 查询纪律（最容易出错的地方）

**① 永远按 `@timestamp` 过滤，绝不用索引名当日期边界。**

索引按**大小**滚动，名字里的日期是索引**创建**日期，不是数据日期。一天的数据会
大量躺在前一天命名的索引里。2026-09-04 截至 07:15Z 实测 F2（00:00Z–07:15Z 计 7.25 小时）：

| 口径 | 结果 |
| --- | ---: |
| `_cat` 看 `...-2026.09.04-*` 索引 | 17,836,373 |
| 按 `@timestamp` 查 09-04 00:00Z–07:15Z（前 7.25 小时） | **282,433,878** |

**差 16 倍。** 所以索引通配**必须覆盖前一天**：

```
/*uss_ae_behavior-2026.09.03*,*uss_ae_behavior-2026.09.04*/_search
```

**② 没按 `@timestamp` 验证前，不要判定某环境日志中断。**

曾据 `_cat` 误判 S1 管道断了（最新 uss_ae 索引停在 09-03，而同集群其他日志仍在写），
实际数据正常流入、只是 rollover 慢。判活性用 `max(@timestamp)` 聚合，别看索引名。
判定规则：**第一步（必做）**全通配加 `now-2h` 相对窗做绝对滞后判断（null 直接判停摆；
<120s 正常近实时）；**第二步（条件触发）**仅当滞后 >300s 或为负时复测推进（推进量 > 间隔
为赶工追赶，≈ 间隔为**恒定滞后**需报警，0 < 推进 < 间隔为持续掉队，≤0 为停摆）。方法见
`references/query-patterns.md` ①。

**③ 分位数聚合在大索引上会超时。** 单索引 4 亿+ 文档做 `percentiles` 会打穿
Kibana 代理（约 30s）。分索引逐个查，或换轻量聚合（`avg` + `max` + range 分档）。

**④ HTTP 200 不等于结果完整——每次取数后检查 `timed_out` 与 `_shards`。**

③ 的超时是硬失败（连接断、退出码 28），看得见。真正阴险的是**软失败**：分片级超时
或部分分片异常时，ES 照样返回 **200 + 结构完整的 JSON + 偏小的数字**，只在
`timed_out: true` / `_shards.failed > 0` 上留痕。这类数字看起来完全正常，直接拿去做
跨环境对比就会得出错误结论。在本项目的量级（单环境日均 3–5 亿文档）上很容易触发。

固定校验（每条查询都串上）：

```bash
... | jq '{timed_out, shards: ._shards, total: .hits.total.value}'
```

`timed_out` 非 `false` 或 `_shards.failed` 非 `0` → 该结果作废，缩小时间窗或分索引重查，
**不要拿它下结论**。

**⑤ 查 ERROR 必须排除 INFO，别直接查 "ERROR"。**

`log_level` 未填充，全文匹配会混入大量 INFO 业务码。DSL 与 KQL 排除式写法、噪声分类与
基线见 `references/error-baseline.md`（两路径共用单源）。报数时两个口径都给。

## 环境与传输模式

`:9200` 是否可达分两组，脚本已内置映射；排查连不通时需要知道：

| 组 | 环境 | 传输 |
| --- | --- | --- |
| `:9200` 直连 | **F1 F2 F3 S2 H1** | `direct` |
| `:9200` 被防火墙 DROP，只开 `:443` | **F4 F5 F6 F7 S1** | `kibana`（console proxy） |

第二组的症状是 `curl: (28) Connection timed out`（不是 refused）；两组的 `:443` 都返回 200。
Kibana console proxy 实测接受 `Authorization: Basic`，不必先拿 session cookie，但受
约 30s 代理超时限制。防火墙规则变动时用 `ELK_MODE=direct|kibana` 覆盖，并更新
`scripts/elk-query` 里的映射表。

域名、IP、各环境主机数、`merchantCode` 后缀、规模基线见 `references/clusters.md`。

## 索引与常用查询

```
logstash-core_uss_ae_behavior-YYYY.MM.DD-NNNNNN   行为日志：uri / elapsed / query /
                                                  thread / request_ip / host.name /
                                                  action / state
logstash-core_uss_ae_ap-YYYY.MM.DD-NNNNNN         应用日志：message（异常栈、ORA 错误码）
```

管道活性检查、环境基线、慢接口排名、单接口下钻、异常栈聚合、真 ERROR 检索、traceId 追踪、跨环境
循环的 DSL 模板见 `references/query-patterns.md`。

## 其他已知事实

- **证书**：10 套证书均为 OpenSSL 默认占位自签，**无 CN 也无 SAN**，且 `CA:TRUE` 被当
  叶子证书用。Chrome 的证书错误**客户端无法消除**（Chrome 58+ 忽略 CN 强制查 SAN），
  故 Chrome 在这些证书错误站点不保存也不自动填充密码、每套都要手动登录——这正是不走浏览器的原因。
  `curl -k` 不受影响。根治需服务端重签带 SAN 的证书（平台侧）。
- **凭据**：`dev` 是 **superuser**。F1 上既有 19 个 API Key 无一可读 uss_ae
  （`search-api-key` 只覆盖 `logstash-trd_pss_engine_jobs_log-*`，属别的系统，别动）。
  API Key 与 `dataViewId` 一样**不可跨集群复用**，别为读日志建 key。
- **AI Assistant**（Kibana 内置）对取数没用：需配外部 LLM connector，等于把生产日志
  外发第三方，且产出不如直接写 DSL。
