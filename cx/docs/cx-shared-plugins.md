# cx 共享 LazyCodex

`cx` 继续用独立 `CODEX_HOME` 隔离各账号。LazyCodex 程序统一来自 `~/.codex` 的现有安装，不再对每个账号运行安装器。

## 使用

```sh
cx plugins sync --all          # 预览全部账号的同步
cx plugins sync --all --apply  # 同步，并为后续启动和新建账号启用持续同步
cx plugins sync personal --apply  # 单独同步一个账号
cx personal                    # 已启用持续同步时，先同步再启动 Codex
```

要求 Python 3.11+。首次先在默认 `~/.codex` 安装并启用 LazyCodex。统一更新也在该目录执行，之后启动账号时同步最新注册项。

## 修改范围

- 合并每个账号 `config.toml` 中的 `marketplaces.sisyphuslabs`、`plugins."omo@sisyphuslabs"`、该插件的 Hook 信任项和 Ultrawork Agent 定义。
- 启用插件所需的 `features.plugins`、`plugin_hooks`、`multi_agent`、`unified_exec`、`goals`；其他设置保留。
- Agent 的 `config_file` 使用共享安装中的绝对路径。
- 每个账号仅把 `plugins/cache/sisyphuslabs` 链接到共享目录；其他插件缓存保持独立。
- 不读取或复制账号认证文件，不共享会话、数据库、记忆或整个 `CODEX_HOME`，不继承默认账号的模型和权限策略。
- `--all --apply` 创建 `~/.codex-profiles/.cx-shared-plugins`，表示用户已启用启动前同步。无此标记时，原有启动行为不变。

## 备份与回滚

改变已有配置前，在账号目录生成权限为 600 的 `config.toml.cx-backup-*`；替换已有插件缓存目录或链接前，将其改名为 `sisyphuslabs.cx-backup-*`。不删除旧安装。

回滚时先移除 `.cx-shared-plugins` 标记以停止持续同步，再在受影响账号恢复本次备份的配置和缓存路径；仅移除本次创建的缓存链接。没有旧配置的新增账号可以移除本次生成的配置。备份可能包含账号私有配置，不要提交到仓库。

已有会话不会热加载这些插件配置。同步后退出该账号的 Codex，再通过 `cx <账号>` 启动新会话验证 `ulw`。

## 验证

在仓库根目录运行以下命令。测试只使用临时目录，不读取真实账号、认证或 Codex 进程：

```sh
bash -n cx/bin/cx
python3 -B -m unittest discover -s cx/tests -p 'test_*.py' -v
```
