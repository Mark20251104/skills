# 查询模板

模板已按 SKILL.md 的查询纪律改造过：**全部按 `@timestamp` 过滤，索引通配覆盖前一天。**
（`tcg-uss-ae` 仓库的 `docs/slow-request-analysis-2026-08-16.md` §A.3 原版模板只按索引名通配，会系统性
漏掉大部分数据——那份报告的数字是在知道该局限的前提下取的，勿直接照抄其模板。）

本文件中的查询模板，脚本路径均以 `<SKILL_DIR>/scripts/elk-query` 表示。
执行时需根据当前实际加载的 skill 目录展开为字面绝对路径（例如 `/path/to/prod-elk/scripts/elk-query`）。

**不要改写成 shell 变量引用**——权限规则按命令字符串前缀匹配，
`"$ELK" f1 ...` 会被拦，必须把展开后的完整绝对路径字面写在命令开头。

先设日期变量，后续模板复用（日期变量可以用，脚本路径不行）：

```bash
DAY=2026.09.04; PREV=2026.09.03; FROM=2026-09-04T00:00:00Z; TO=2026-09-05T00:00:00Z
BEH="/*uss_ae_behavior-$PREV*,*uss_ae_behavior-$DAY*/_search?request_cache=true"
AP="/*uss_ae_ap-$PREV*,*uss_ae_ap-$DAY*/_search?request_cache=true"
TS="{\"range\":{\"@timestamp\":{\"gte\":\"$FROM\",\"lt\":\"$TO\"}}}"
# 结果完整性校验（SKILL.md 纪律 ④）：非 ok 的结果一律作废，别拿去下结论
CHK='if .timed_out != false or ._shards.failed != 0 then {BAD:{timed_out,shards:._shards}} else . end'
```

每条查询的输出都先过 `$CHK` 再取数：

```bash
<SKILL_DIR>/scripts/elk-query f1 "$BEH" "$DSL" | jq "$CHK" | jq '.aggregations'
```

出现 `BAD` 说明分片超时或部分失败——ES 仍返回 200，但数字偏小。缩小时间窗或分索引重查。

## 字段

行为日志 `..._behavior-*`：`uri` `elapsed`(ms) `query` `thread` `request_ip`
`host.name` `action` `state`。按 API 请求过滤用 `{"term":{"action.keyword":"API-REQUEST"}}`。

应用日志 `..._ap-*`：`message`（异常栈、ORA 错误码）。

聚合用 keyword 子字段（`uri.keyword`），全文匹配用 `match_phrase`。

## ① 管道活性检查

判断某环境日志是否还在流入且摄入未滞后——**不要看索引名**。

活性检查**独立定义查询**，不复用固定日期的 `$TS` 和仅拼两天的 `$BEH`（否则跨天不改变量
或小集群如 S1 rollover 慢时，会被截断导致误报停摆）。索引走全通配，时间窗用相对范围
`now-2h`（ES 的 `can_match` 阶段会直接跳过无关索引，代价很低）：

```bash
# behavior 是主管道（行为日志，量最大、最实时）；排查应用异常时同理查 ap 管道 (/*uss_ae_ap-*/_search)
L_BEH='/*uss_ae_behavior-*/_search'
L_DSL='{"size":0,"track_total_hits":true,"query":{"range":{"@timestamp":{"gte":"now-2h"}}},"aggs":{"latest":{"max":{"field":"@timestamp"}}}}'
```

两步判定逻辑：
1. **第一步（必做）：绝对滞后判断**。查 `max(@timestamp)` 的 `value_as_string`（UTC，带 Z），
   与本机 UTC 时钟 `date -u` 相减得到绝对滞后秒数 `LAG`。
   - 若 `hits.total == 0` 或 `latest.value == null`：过去 2 小时内完全无数据流入，
     **直接判定停摆或严重滞后（>2h）**，无需也不应做第二步。
   - `LAG < 120s`：**正常近实时**（S2/H1 正常基线通常在数秒至数十秒，已证明数据在持续到达，无需第二步）。
   - `120s ~ 300s`：稍有缓冲延迟，仍在可接受范围。
   - `LAG > 300s`（5 分钟以上）：**疑似滞后**，必须补第二步确认管道推进状态。
   - `LAG > 900s`（15 分钟以上）：**判定异常滞后 / 管道阻塞**。
   - `LAG < 0`：本机时钟慢于 ES 集群（时钟偏斜 clock skew），非故障也非健康凭据，以第二步为准。
2. **第二步（条件触发）：推进确认**。当第一步 `LAG > 300s` 或 `LAG < 0` 时，间隔 30~60 秒
   重跑同一查询，对比两次 `value_as_string` 的推进量与间隔时长：
   - **推进量 > 间隔**：正在追赶（积压正在被消耗）。
   - **推进量 ≈ 间隔**：**恒定滞后**（积压量未缩小，管道稳定落后，需报警处理）。
   - **0 < 推进量 < 间隔**：持续掉队（入库速率小于产生速率，滞后扩大中）。
   - **推进量 == 0**：停摆（无新数据写入）。

```bash
# 单环境绝对滞后完整查询与计算（先过 $CHK 拦截分片软失败，再提取 latest 与算滞后）
OUT=$(<SKILL_DIR>/scripts/elk-query f1 "$L_BEH" "$L_DSL" | jq "$CHK")
if [[ -z "$OUT" ]]; then
  echo "FAIL: elk-query returned nothing, check exit code and stderr"; exit 1
elif jq -e '.BAD' <<<"$OUT" >/dev/null 2>&1; then
  echo "BAD: shard timeout/failure, result void, re-query: $(jq -c .BAD <<<"$OUT")"
else
  LATEST=$(jq -r '.aggregations.latest.value_as_string // "null"' <<<"$OUT")
  if [[ "$LATEST" == "null" ]]; then
    echo "CRITICAL: no logs in the past 2 hours (stalled or lag >2h)"
  elif [[ "$LATEST" == *Z ]]; then
    T="${LATEST%Z}"
    LAG=$(( $(date -u +%s) - $(date -j -u -f '%Y-%m-%dT%H:%M:%S' "${T%.*}" +%s) ))
    echo "lag_seconds=$LAG"
  else
    echo "WARN: unexpected timezone format ($LATEST)"
  fi
fi
```

跨 10 套巡检（每套做绝对滞后；仅疑似异常套再补测第二步推进）：

```bash
for e in f1 f2 f3 f4 f5 f6 f7 s1 s2 h1; do
  printf "%-3s " "$e"
  if out=$(ELK_TIMEOUT=50 <SKILL_DIR>/scripts/elk-query "$e" "$L_BEH" "$L_DSL" 2>/dev/null); then
    jq -r "$CHK" <<<"$out" \
      | jq -r 'if .BAD then "BAD \(.BAD.shards)" else "\(.hits.total.value)|\(.aggregations.latest.value_as_string)" end'
  else
    echo "FAIL rc=$?"   # 22=HTTP 错误 28=超时，见 SKILL.md 退出码表
  fi
done
```

**巡检必须逐环境判退出码**，否则某套挂掉时循环只会静默跳过、留下一份看似完整的
9 行结果——这类"少一行"的输出最容易被当成全量读。

## ② 环境基线（总量、分位数、慢请求分档）

```bash
<SKILL_DIR>/scripts/elk-query f1 "$BEH" - <<EOF
{ "size": 0, "track_total_hits": true,
  "query": { "bool": { "filter": [ $TS, { "term": { "action.keyword": "API-REQUEST" } } ] } },
  "aggs": {
    "pct":  { "percentiles": { "field": "elapsed", "percents": [50,95,99,99.9,99.99] } },
    "mx":   { "max": { "field": "elapsed" } },
    "avg":  { "avg": { "field": "elapsed" } },
    "slow": { "range": { "field": "elapsed",
              "ranges": [ {"from":1000,"to":3000}, {"from":3000,"to":10000},
                          {"from":10000,"to":30000}, {"from":30000} ] } } } }
EOF
```

⚠️ `percentiles` 在 4 亿+ 文档的单索引上会打穿 Kibana 代理（约 30s）。对 `kibana`
模式的环境（F4–F7、S1）改为逐个索引查，或去掉 `percentiles` 只留 `avg`/`max`/`slow` 分档。

## ③ 慢接口排名

口径：仅统计 >1s 的请求，按累计耗时排序（找总耗时大头，而非单次最慢）。

```bash
<SKILL_DIR>/scripts/elk-query f1 "$BEH" - <<EOF
{ "size": 0, "track_total_hits": true,
  "query": { "bool": { "filter": [ $TS,
      { "term": { "action.keyword": "API-REQUEST" } },
      { "range": { "elapsed": { "gte": 1000 } } } ] } },
  "aggs": { "u": { "terms": { "field": "uri.keyword", "size": 12, "order": { "s": "desc" } },
    "aggs": { "s": { "sum": { "field": "elapsed" } },
              "c": { "value_count": { "field": "elapsed" } },
              "a": { "avg": { "field": "elapsed" } },
              "mx":{ "max": { "field": "elapsed" } },
              "t": { "date_histogram": { "field": "@timestamp", "fixed_interval": "1h",
                                         "min_doc_count": 1, "order": { "_count": "desc" } } } } } } }
EOF
```

## ④ 单接口下钻 / 改造效果验收

对目标 `uri` 按 `query` 内容分组查，`match_phrase` 匹配查询串片段：

```bash
<SKILL_DIR>/scripts/elk-query f1 "$BEH" - <<EOF
{ "size": 0, "track_total_hits": true,
  "query": { "bool": { "filter": [ $TS,
      { "term": { "uri.keyword": "/tcg-uss-ae/customer/profile/condition/sensitive" } },
      { "match_phrase": { "query": "isWildcard=true" } } ] } },
  "aggs": { "p":    { "percentiles": { "field": "elapsed", "percents": [50,95,99] } },
            "mx":   { "max": { "field": "elapsed" } },
            "slow": { "range": { "field": "elapsed", "ranges": [ { "from": 10000 } ] } } } }
EOF
```

改造验收基准（该接口 P0-1 的历史判别标准）：

| 形态 | 含义 |
| --- | --- |
| 通配灾难（>10s 占比 12–94%）+ EMAIL 健康 | 旧版代码 |
| 通配健康（max < 10s）+ EMAIL 灾难（>10s 占比 66%） | 新版代码，P0-1 未落地 |
| 通配健康 + EMAIL 健康（p99 回落至 200ms 量级） | P0-1 落地成功 |

S1、H1 数据量太小，该判别特征失效（全表扫描本身就快），只能验功能正确性。

## ⑤ 异常栈聚合（应用日志）

```bash
<SKILL_DIR>/scripts/elk-query f1 "$AP" - <<EOF
{ "size": 0, "track_total_hits": true,
  "query": { "bool": { "filter": [ $TS ],
             "must": [ { "match_phrase": { "message": "ORA-" } } ] } },
  "aggs": { "hourly": { "date_histogram": { "field": "@timestamp", "calendar_interval": "hour",
                                            "min_doc_count": 1 } } } }
EOF
```

取样本原文（`size` 别开大，单条 message 可能很长）：

```bash
<SKILL_DIR>/scripts/elk-query f1 "$AP" - <<EOF
{ "size": 5, "_source": ["@timestamp","message"],
  "sort": [ { "@timestamp": "desc" } ],
  "query": { "bool": { "filter": [ $TS ],
             "must": [ { "match_phrase": { "message": "ORA-01722" } } ] } } }
EOF
```

## ⑥ 真 ERROR 检索（排除 INFO 噪声）

排除式 DSL 模板（机制、噪声清单与判读基线见 `error-baseline.md`，报数时两个口径都给）：

```bash
<SKILL_DIR>/scripts/elk-query f1 "$AP" - <<EOF
{ "size": 0, "track_total_hits": true,
  "query": { "bool": { "filter": [ $TS ],
             "must": [ { "match_phrase": { "message": "ERROR" } } ],
             "must_not": [ { "match_phrase": { "message": "INFO" } } ] } },
  "aggs": { "hourly": { "date_histogram": { "field": "@timestamp", "calendar_interval": "hour",
                                            "min_doc_count": 1 } } } }
EOF
```

## ⑦ traceId 追踪

`traceId` 在日志 pattern 里（`[%X{traceId}/%X{spanId}]`），行为日志与应用日志共用。
先在 behavior 定位请求，再拿 traceId 去 ap 捞栈：

```bash
<SKILL_DIR>/scripts/elk-query f1 "$AP" - <<EOF
{ "size": 20, "_source": ["@timestamp","message"], "sort": [ { "@timestamp": "asc" } ],
  "query": { "match_phrase": { "message": "<traceId>" } } }
EOF
```

## ⑧ 跨环境对比

任何模板套进循环即可。注意给 `kibana` 模式的环境留足超时，且大聚合可能仍会打穿代理：

```bash
for e in f1 f2 f3 f4 f5 f6 f7 s1 s2 h1; do
  echo "=== $e ==="
  if out=$(ELK_TIMEOUT=50 <SKILL_DIR>/scripts/elk-query "$e" "$BEH" "$DSL" 2>&1); then
    jq -r "$CHK" <<<"$out" | jq '.aggregations // .BAD'
  else
    echo "FAIL rc=$? $out"
  fi
done
```

同一份对比表里**不能混入 `BAD` 或缺失的环境**——分片软失败的数字偏小，会被误读成
"该环境负载低"。缺哪套就补哪套，补不上就在结论里标明缺口。

超过 120s 的循环会被移到后台并写入输出文件，读那个文件取结果即可。
