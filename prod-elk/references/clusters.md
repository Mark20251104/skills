# 集群清单

10 套彼此独立的 ELK。**API Key 与 `dataViewId` 均不可跨集群复用。**

IP 与传输模式于 **2026-09-04 实测**；实例与 `merchantCode` 后缀源自
`tcg-uss-ae` 仓库的 `docs/slow-request-analysis-2026-08-16.md` §A.1（2026-08-19 复验）。

| 环境 | 域名 | IP | 传输 | 实例 | merchantCode 后缀 |
| --- | --- | --- | --- | --- | --- |
| F1 | `elk-platform.tcg.local` | 10.105.77.35 | `direct` | 4：`TCG-USS-AE01` ~ `AE04` | `f1` |
| F2 | `elk-platform.tcg-f2.local` | 10.105.77.24 | `direct` | 5：`TCG2-USS-AE01-A` ~ `E` | `f2` |
| F3 | `elk-platform.tcg-f3.local` | 10.156.77.42 | `direct` | 4：`TCG3-USS-AE01-C/D` + `PL-USS-AE01-A/B` ※ | `f3` |
| F4 | `elk-platform.tcg-f4.local` | 10.112.77.17 | `kibana` | 4：`TCG4-USS-AE01-A` ~ `D` | `f4` |
| F5 | `elk-platform.tcg-f5.local` | 10.115.77.16 | `kibana` | 4：`TCG5-USS-AE01-A` ~ `D` | `f5` |
| F6 | `elk-platform.tcg-f6.local` | 10.116.77.16 | `kibana` | 4：`TCG6-USS-AE01-A` ~ `D` | `f6` |
| F7 | `elk-platform.tcg-f7.local` | 10.117.77.16 | `kibana` | 4：`TCG7-USS-AE01-A` ~ `D` | `f7` |
| S1 | `elk-platform.s1.local` | 10.153.77.16 | `kibana` | 2：`S1-USS-AE01-A/B` | `s1` |
| S2 | `elk-platform.s2.local` | 10.154.77.18 | `direct` | 4：`S2-USS-AE01-A` ~ `D` | `s2` |
| H1 | `elk-platform.h1.local` | 10.155.77.18 | `direct` | 4：`H1-USS-AE01-A` ~ `D` | `h1` |

※ F3 主机命名混用 `TCG3-` 与 `PL-` 两套前缀，负载分布均匀，功能上为同一集群，
命名不一致原因未查。

注：F1 的地址无环境后缀（`tcg.local` 而非 `tcg-f1.local`）。旧报告曾称其为 "ENV1"，
后经 `merchantCode` 后缀 `f1` 确认即 F1。

## 传输模式

`kibana` 组的 `:9200` 被防火墙 **DROP**（`curl: (28) Connection timed out`，
不是 refused），只开 `:443`；两组的 `:443` 都返回 200。脚本已内置映射，
防火墙规则变动时用 `ELK_MODE=direct|kibana` 覆盖并更新 `scripts/elk-query` 的表。

## 规模基线

2026-09-04 07:15Z 实测，当天 00:00Z 起 7.25 小时的 behavior 文档数（按 `@timestamp`）：

| 环境 | 文档数 | 约每小时 |
| --- | ---: | ---: |
| F7 | 425,071,323 | 58.6M |
| F1 | 385,331,390 | 53.1M |
| F6 | 370,258,107 | 51.1M |
| F3 | 355,765,854 | 49.1M |
| F4 | 331,371,027 | 45.7M |
| F5 | 305,989,167 | 42.2M |
| S2 | 302,961,170 | 41.8M |
| F2 | 282,433,878 | 39.0M |
| H1 | 100,878,355 | 13.9M |
| S1 | 10,443,269 | 1.4M |

H1 约为主流环境 1/4、S1 小约 30 倍，是**环境规模差异而非故障**。判活性见
`query-patterns.md` 的管道活性检查。

数据量小的环境（S1、H1）在做代码版本判别时特征会失效——全表扫描本身就快，
只能用于功能正确性验证，不能据此判断版本。
