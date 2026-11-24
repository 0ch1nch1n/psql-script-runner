# PSQL Script Runner v5.4

在 Windows 上按顺序执行多个 PostgreSQL SQL 脚本。

## 使用方法

1. 准备 Windows PowerShell 5.1 和 PostgreSQL 的 `psql.exe`。也可使用 pgAdmin 附带的 `psql.exe`。
2. [下载 `PSQL-Script-Runner-v5.4.cmd`](https://github.com/0ch1nch1n/psql-script-runner/releases/download/v5.4/PSQL-Script-Runner-v5.4.cmd)。它是可以直接双击的单文件启动器。
3. 编辑 CMD 顶部的 `PG_PSQL_EXE`、`PG_HOST`、`PG_PORT`、`PG_DATABASE` 和 `PG_USERNAME`。保留 `PG_PASSWORD` 为空，运行时在弹窗中输入密码。
4. 双击 CMD，先选备份 SQL，再选客户 SQL 并调整顺序。连接预检通过后，核对目标库、执行顺序和编码结果，再点 **Yes**。

**跳过实际备份**时，将内容为 `SELECT 1;` 的 UTF-8 文件 `skip_backup.sql` 选为备份脚本。Runner 会先执行这条只读语句。

**从旧版升级**时，将原 CMD 的连接配置复制到新版 CMD 顶部，然后使用新版 CMD 启动。

## 功能边界

- **编码**：备份与客户 SQL 都必须是有效的 UTF-8，支持带 BOM 和不带 BOM。总览及运行报告逐个显示结果。任一文件无法读取或未通过检查，整批停止。
- **连接预检**：使用只读查询，最长等待 30 秒。失败或超时会阻止整批执行。这个时限仅适用于预检。
- **执行与事务**：每个脚本在独立的 `psql` 会话中运行，使用 `-1` 请求单事务执行，并设置 `ON_ERROR_STOP=1`。备份脚本成功后才执行客户 SQL。遇错停止后续步骤，已提交的前序脚本不会自动回滚。脚本自带事务控制或包含事务内不支持的命令时，需要提前审核。
- **日志**：同名脚本 `.log` 会被覆盖。`PostgreSQL_Run_*.log` 写在备份 SQL 所在目录，运行报告不记录密码。启动日志位于 `%LOCALAPPDATA%\psql\Logs`，该位置不可写时使用 `%TEMP%\psql\Logs`。

## 版本更新

| 版本 | 主要变更 |
| --- | --- |
| [v5.4](https://github.com/0ch1nch1n/psql-script-runner/releases/tag/v5.4) | 将 CMD 和 PowerShell 合并为一个带版本号的 CMD 文件。 |
| [v5.3](https://github.com/0ch1nch1n/psql-script-runner/releases/tag/v5.3) | 设置 `psql` 客户端编码为 UTF-8，增加执行前逐文件检查。 |
| v5.2 | 改用 WinForms 密码窗口，增加本地启动阶段日志。 |
| v5.1 | 为连接预检增加 30 秒总时限和等待进度。 |

[完整更新日志](CHANGELOG.md)
