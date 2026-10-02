# CX Quota 逻辑审查

审查日期：2026-10-01

## 目标与边界

CX Quota 是本机菜单栏额度查看器。它通过官方 `codex app-server` 获取各个 `~/.codex-profiles` 配置的额度和重置卡信息，不读取或复制认证文件。应用只在用户打开菜单栏面板、点击“刷新”或确认消耗重置卡后查询网络。

## 运行流程

1. `StatusBarController` 打开弹出框后调用 `QuotaStore.refreshOnOpen()`。
2. `QuotaStore` 先显示 `~/Library/Caches/CXQuota/quota-cache.json` 中的快照。
3. 只有下列账号会在打开面板时自动查询：
   - 没有缓存快照；
   - 缓存额度为零，且该额度的自然重置时间晚于上次成功更新、同时已经过去；
   - 服务端曾返回可用重置次数，但没有返回单张重置卡明细。
   这种缺明细响应在单次读取中还会立即重查一次；第二次仍缺明细才写入缓存。
4. 底部“刷新”会查询全部未暂停账号；暂停账号保留缓存数据。
5. `account/rateLimits/read` 返回 5H、周限额和 `rateLimitResetCredits`。
6. 重置视图优先显示周限额已耗尽、且某张重置卡在周限额自然重置前到期的账号。
7. 点击一张账号重置卡区域后，应用进入确认状态。确认框显示账号、选中重置卡到期时间、5H 限额和周限额。
8. 确认才调用官方 `account/rateLimitResetCredit/consume`。成功或服务端报告幂等成功后，应用刷新额度。

## 重置卡选择规则

当服务端返回 `credits` 明细时，应用按 `expiresAt` 升序保存和显示，并把最早到期的一张传给官方消耗接口。

当服务端仅返回 `availableCount` 且 `credits` 为 `null` 时，应用无法判断最早到期时间。确认框会提示该限制，并省略 `creditId`，让官方服务选择下一张可用重置卡。官方协议允许 `credits` 为 `null`，且说明 `availableCount` 才是权威数量。

## 实测响应

2026-10-01 对多个本机配置执行了只读 `account/rateLimits/read`。响应包含可用重置次数及带到期时间的重置卡明细。账号标识和额度数据不记录在仓库中。

此前“到期日未提供”来自旧缓存：旧快照保留了 `availableResetCreditCount`，但没有 `resetCredits`。自动刷新规则已修正为只刷新这种缺明细的账号，因此不会触发全部账号刷新。

## 账号管理

- 添加账号：调用 `cx init <profile>`，再通过 `cx login <profile>` 走官方浏览器登录。
- 退出账号：确认后调用官方 `codex logout`，随后删除对应的 `~/.codex-profiles/<profile>` 目录。
- 删除操作没有在审查或自动化测试中执行。

## 审查结论

| 区域 | 结论 | 证据 |
| --- | --- | --- |
| 额度解析 | 通过 | `QuotaParserTests.testParsesMultipleBucketsAndPreservesResetTime` |
| 缓存按需刷新 | 通过 | `QuotaParserTests.testRefreshesOnlyAfterAnExhaustedWindowHasReset` |
| 缺失重置明细刷新 | 通过 | 同一缓存刷新测试覆盖 `availableResetCreditCount > 0 && resetCredits == nil` |
| 重置结果处理 | 通过 | `QuotaParserTests.testAcceptsOnlySuccessfulResetOutcomes` |
| 官方额度读取 | 通过 | 指定本地 profile 的只读集成测试 |
| 应用包 | 通过 | 已安装包包含 `CXQuota.icns`、采用本机 ad-hoc 签名，进程可启动 |

## 已知限制与后续风险

1. 官方服务可返回重置次数但不返回单张重置卡到期日；这种情况下无法在客户端保证选择最早到期的卡。
2. 重置消费与账号删除都会改变外部或本地状态，审查没有执行这两类真实操作。
3. `ProfileDiscovery` 和 `CXProfileManager.profileDirectory(for:)` 现在检查目录类型、符号链接、当前用户所有权和私有权限；对应回归测试覆盖非私有目录。
4. 代码已按职责拆分：`QuotaModels.swift` 保存领域类型，`QuotaParser.swift` 解析响应，`QuotaSupport.swift` 提供格式化与错误；UI 分为主面板、额度卡和重置卡文件。

## 验证命令

```sh
swift test
CX_QUOTA_LIVE_PROFILE=<本地账号名> swift test --filter QuotaParserTests/testFetchesLiveProfileWhenExplicitlySelected
./scripts/build-app.sh --replace
./scripts/install-app.sh --apply --replace
```

官方协议参考：[Codex App Server - Rate limits](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt)。
