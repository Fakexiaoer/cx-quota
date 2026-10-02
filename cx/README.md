# cx 多账号启动器

`cx` 为每个 Codex 账号使用独立的 `CODEX_HOME`，配置位于 `~/.codex-profiles/<账号名>`。它不读取、复制或合并认证文件；登录仍由官方 `codex login` 在浏览器中完成。

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
