# CX Quota

CX Quota 是 macOS 菜单栏额度查看器，附带 `cx` 多账号 Codex 启动器。两者都使用官方 `codex app-server` 与 `codex login`；不包含、读取或复制任何认证文件。

## 功能

- `cx` 为每个账号提供独立的 `CODEX_HOME` 和私有目录。
- 菜单栏应用显示每个账号的 5H 与周限额、自然重置时间和可用重置卡。
- 打开面板时优先显示本地缓存；只有新账号、自然重置已过去的零额度，或重置卡明细缺失的账号才自动查询。
- 底部“刷新”手动更新全部未暂停账号。应用没有后台轮询。
- 重置卡必须经确认才会调用官方消耗接口；退出账号也必须确认。

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

账号目录保存在 `~/.codex-profiles/<账号名>`，并以 `700` 权限创建。详细安装、共享插件同步和回滚说明见 [cx 使用说明](cx/README.md)。

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
