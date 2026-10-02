# CX Quota

CX Quota 是 macOS 菜单栏额度查看器，附带 `cx` 多配置 Codex 启动器。它适合在一台 Mac 上管理多个已获授权的 Codex 配置：每个配置独立登录、独立运行、独立查看额度。两者都使用官方 `codex app-server` 与 `codex login`；不包含、读取或复制任何认证文件。

**关键词：** Codex 多账号、Codex 多配置、macOS 菜单栏、Codex 额度、5H 限额、周限额、Codex CLI、`CODEX_HOME` 隔离、SwiftUI、开发者效率、账号配置管理。

## 功能

- `cx` 为每个账号提供独立的 `CODEX_HOME` 和私有目录。
- 菜单栏应用显示每个账号的 5H 与周限额、自然重置时间和可用重置卡。
- 打开面板时优先显示本地缓存；只有新账号、自然重置已过去的零额度，或重置卡明细缺失的账号才自动查询。
- 底部“刷新”手动更新全部未暂停账号。应用没有后台轮询。
- 重置卡必须经确认才会调用官方消耗接口；退出账号也必须确认。

## cx：macOS Codex 多配置管理

`cx` 是一个本地 CLI 启动器。它把每个配置放在 `~/.codex-profiles/<配置名>`，启动时仅为该次官方 Codex CLI 进程设置对应的 `CODEX_HOME`。因此个人、工作或不同项目的 Codex 配置、会话、插件缓存和本地设置可以彼此隔离。

你可以在不同终端同时启动多个配置；每个进程只使用自己的目录和自己的官方登录状态：

```sh
# 终端 A
cx personal

# 终端 B
cx work -- --model gpt-5.2-codex
```

这不是额度合并、账号共享或自动化绕过工具。`cx` 不转移额度、不共享认证文件、不把多个账号的限额相加，也不模拟网页登录。每个配置都应对应你本人有权使用的 OpenAI 账号或组织账号，并继续受该账号的套餐、限额、服务可用性及 OpenAI 条款约束。

## 官方 CLI 与使用边界

- 登录调用官方 `codex login`，额度读取调用官方 `codex app-server`。
- 每个配置目录仅限当前用户访问；`cx` 拒绝符号链接、非当前用户所有或非私有权限的目录。
- 应用只在打开面板、手动刷新或确认使用重置卡时请求官方服务，不做后台轮询。
- 不要共享账号凭据或将账号提供给他人使用。OpenAI 说明个人账号应由创建该账号的个人使用；多人协作应使用各自账号或适用的组织产品。[OpenAI 账户使用说明](https://help.openai.com/en/articles/10471989-role-based-access-control-rbac-in-chatgpt-business-enterprise-and-edu)

完整的 `cx` 命令、共享插件选项和回滚说明见 [cx 使用说明](cx/README.md)。

## 要求

- macOS 15 或更新版本。
- 官方 Codex CLI 已安装，并且 `codex` 可在 `PATH` 中找到。
- Xcode 16.4 或更新版本，含 Swift 6.1，用于从源码构建菜单栏应用。
- Bash；只有可选的 LazyCodex 共享插件同步功能需要 Python 3.11+。

## 快速开始

```sh
git clone https://github.com/Fakexiaoer/cx-quota.git
cd cx-quota

# 安装多账号启动器，并创建、登录第一个账号。
./cx/install.sh
cx init personal
cx login personal

# 构建并安装菜单栏应用。
./scripts/build-app.sh
./scripts/install-app.sh --apply
open "$HOME/Applications/CX Quota.app"
```

`cx login personal` 会启动官方浏览器登录流程。登录成功后，点击菜单栏 CX 图标即可查看该账号额度。通过 `cx init` 创建的后续账号也会自动被应用发现。

## cx：多账号 Codex

```sh
cx init <账号名>                 # 创建私有账号目录
cx login <账号名>                # 官方登录
cx <账号名> [--] [codex 参数]    # 在该账号中启动 Codex
cx list                          # 列出账号
cx path <账号名>                 # 输出账号目录
```

账号目录保存在 `~/.codex-profiles/<账号名>`，并以 `700` 权限创建。

## 菜单栏应用

应用对每个账号独立调用官方 `codex app-server`，并为该进程设置相应的 `CODEX_HOME`。它不通过 `cx <账号>` 启动 CLI，因此读取额度不会触发插件同步。

点击账号卡片可暂停该账号的刷新，暂停状态会保存在本机。点击“重置次数”可进入重置卡视图；点击卡片后先检查账号、重置卡到期日、5H 和周限额，再由用户确认消耗。服务端可能只返回可用次数而不返回单张卡的到期日；此时应用会重试一次，仍缺失时会明确说明并交由官方服务选择下一张卡。

本地额度缓存只保存显示字段与更新时间，位置为 `~/Library/Caches/CXQuota/quota-cache.json`，权限仅限当前用户。

## 开发、测试和打包

```sh
swift test
swift run

bash -n cx/bin/cx cx/install.sh scripts/build-app.sh scripts/install-app.sh
python3 -B -m unittest discover -s cx/tests -p 'test_*.py' -v
```

构建脚本不会覆盖现有产物；更新时使用：

```sh
./scripts/build-app.sh --replace
./scripts/install-app.sh --apply --replace
```

应用包使用本机 ad-hoc 签名。需要移除应用时，将 `~/Applications/CX Quota.app` 移到废纸篓；要清除额度缓存，同时删除 `~/Library/Caches/CXQuota/quota-cache.json`。

## 审计

额度查询、缓存刷新、重置卡、账号管理和已知限制记录在 [逻辑审计](docs/logic-audit.md)。

## 许可证

本项目采用 [PolyForm Noncommercial 1.0.0](LICENSE) 许可证。允许非商业用途的使用、修改和分发；商业使用需要获得版权方的另行书面许可。

## 友链

- [LINUX DO](https://linux.do) — 一个面向技术与开源爱好者的社区。
