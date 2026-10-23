# iMPF Script Runner v5.1

Windows 下的 PostgreSQL 多脚本执行工具。先选择一个备份 SQL，再选择客户 SQL、调整顺序、输入密码；连接预检成功后显示总览，点击 **Yes** 才开始执行。

## 本版修复

v5 在输入密码后同步等待连接预检进程返回，没有显式超时，可能长时间停在总览之前。v5.1 为这一步增加了：

- 每个地址 10 秒的连接超时，以及整个预检 30 秒的等待上限。
- 每 5 秒在窗口和运行报告中显示等待进度。
- 禁止预检再次提示输入密码，关闭分页并关闭预检的标准输入。
- 并发读取标准输出与错误输出，超时后终止预检。

30 秒限制仅适用于只读连接预检。备份和客户 SQL 沿用原有执行流程，不设置这个运行时限。连接阶段为什么等待，仍需根据实际网络与认证错误排查。

## 使用

1. 安装 Windows PowerShell 5.1 和 PostgreSQL `psql.exe`（也可以使用 pgAdmin 附带的版本）。
2. 将 `iMPF-Run-Scripts.cmd`、`iMPF-Run-Scripts.ps1` 放在同一目录。
3. 编辑 CMD 顶部的 `PG_PSQL_EXE`、`PG_HOST`、`PG_PORT`、`PG_DATABASE` 和 `PG_USERNAME`。仓库中提供的是占位配置。
4. 保持 `PG_PASSWORD` 为空，运行时通过密码对话框输入。
5. 双击 CMD，选择备份与客户脚本并调整顺序；核对预检总览后点击 Yes。

从旧版升级时，先备份旧文件；也可只替换 PS1，继续使用你已有的同名 CMD 及连接配置。

## 执行与日志

- 每个脚本使用独立 `psql` 会话，以 `-1` 请求单事务执行，并设置 `ON_ERROR_STOP=1`。脚本自带的事务控制及不支持事务的语句需要自行审核。
- 备份成功才运行客户脚本，任何一步失败后停止后续步骤；已经成功提交的前序脚本不会自动回滚。
- 每个脚本的同名 `.log` 会被覆盖；整体报告 `PostgreSQL_Run_*.log` 写在备份 SQL 所在目录。
- 密码不写入运行报告，运行时通过进程环境传给 psql。
- 预检失败或超时，所选备份和客户 SQL 均不启动。

## 验证

已在 Linux、PowerShell 7.6.7 中使用模拟进程验证成功返回、认证失败、异常结果、数据库不匹配、大量双流输出、30 秒超时和进程清理。测试不会连接数据库。Windows PowerShell 5.1 界面、Windows 参数传递及真实数据库连接仍需本机验收。

Linux/macOS 中安装 Python 3 和 PowerShell 后运行：

```sh
python3 tests/run_precheck_tests.py
```

可通过 `--pwsh /path/to/pwsh` 指定 PowerShell 启动器。测试中的模拟可执行文件使用 POSIX shebang，不作为 Windows 自动化验收。
