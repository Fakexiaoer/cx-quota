# cx：Codex 多配置启动器

`cx` 为每个 Codex 配置使用独立的 `CODEX_HOME`，配置位于 `~/.codex-profiles/<账号名>`。它不读取、复制或合并认证文件；登录仍由官方 `codex login` 在浏览器中完成。

**关键词：** OpenAI Codex、Codex CLI、多账号、多配置、`CODEX_HOME`、macOS、终端开发、账号隔离、并行 Codex 会话、插件隔离、Codex 额度管理。

## 为什么使用 cx

- **本地隔离：** 默认情况下，每个配置都有独立的认证状态、设置、会话和插件缓存；共享插件缓存必须由用户显式启用。
- **并行会话：** 可以在多个终端同时运行不同配置，不会混用 `CODEX_HOME`。
- **安全边界：** 配置目录必须由当前用户拥有且权限私有；启动器不会读取、导出或复制认证文件。
- **官方路径：** 启动、登录和额度读取仍由官方 Codex CLI 与 app-server 完成。

```sh
# 两个终端可同时运行，各自使用独立配置。
cx personal
cx work -- --model gpt-5.2-codex
```

`cx` 不合并额度、不共享会话、不转移认证，也不用于绕过套餐或服务限制。每个配置必须对应你有权使用的账号；不要共享个人账号凭据或把账号提供给其他人使用。OpenAI 对个人账号的说明见 [账户使用说明](https://help.openai.com/en/articles/10471989-role-based-access-control-rbac-in-chatgpt-business-enterprise-and-edu)。

## 安装

在仓库根目录执行：

```sh
./cx/install.sh
```

该脚本会创建 `~/.local/bin/cx`，作为指向当前检出目录中启动器的符号链接。请保留该检出目录；日后 `git pull` 后，命令会自动使用更新后的代码。若已有同名命令，先检查其来源；确认替换时使用 `./cx/install.sh --force`，旧文件会被改名备份。

要求：macOS、Bash、官方 `codex` 命令已在 `PATH` 中。`~/.local/bin` 也需要在 `PATH` 中。

## 基本使用

```sh
cx init personal
cx login personal
cx personal
cx list
cx path personal
```

账号名允许字母、数字、点、下划线和连字符，最长 64 个字符。目录会以 `700` 权限创建；启动器拒绝符号链接、非当前用户所有或非私有的账号目录。

向官方 CLI 传递参数时：

```sh
cx personal -- --model gpt-5.2-codex
cx login personal -- --help
```

## 可选：共享 LazyCodex 插件

默认情况下，账号完全隔离。若你已在默认 `~/.codex` 安装并启用 LazyCodex，可使用 Python 3.11+ 的同步工具，把插件注册项和插件缓存安全地共享到指定账号：

```sh
cx plugins sync personal          # 预览，不写入
cx plugins sync personal --apply  # 写入并保留备份
cx plugins sync --all --apply     # 为全部账号启用启动前同步
```

完整的改动范围、回滚方式与限制见 [共享插件说明](docs/cx-shared-plugins.md)。

## 验证

```sh
bash -n cx/bin/cx cx/install.sh
python3 -B -m unittest discover -s cx/tests -p 'test_*.py' -v
```
