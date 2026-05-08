# 校园网开机自动登录

自动登录校园 ePortal 认证的脚本，支持 Windows 和 macOS。当前默认配置已经在中国石油大学（华东）校园网环境下验证过，适合电脑开机或用户登录后自动完成校园网认证。

脚本会先检测当前是否已经可以访问互联网。如果还没有联网，并且检测请求被重定向到校园网认证页，就会自动向 ePortal 登录接口提交账号、密码和服务类型，然后再次检测联网状态。

## 功能特点

- 支持 Windows 计划任务自启。
- 支持 macOS LaunchAgent 登录自启。
- 支持手动运行测试，方便先确认配置是否正确。
- 默认跳过系统代理，避免请求被本机代理端口拦截。
- 支持通过 `config.json` 配置账号、密码、运营商服务和登录接口。
- 登录日志默认写入 `campus_login.log`，便于排查问题。

## 文件说明

- `campus_login.py`：自动登录主脚本。
- `config.example.json`：配置模板，复制为 `config.json` 后使用。
- `setup.ps1`：Windows 交互式配置引导脚本。
- `install_task.ps1`：安装 Windows 开机自启计划任务。
- `check_task.ps1`：检查 Windows 计划任务配置、最近运行结果和日志。
- `setup_macos.sh`：macOS 交互式配置引导脚本。
- `install_launch_agent.sh`：安装 macOS 登录自启 LaunchAgent。
- `check_launch_agent.sh`：检查 macOS LaunchAgent 配置、加载状态和日志。
- `requirements.txt`：Python 依赖列表。
- `.gitignore`：忽略本地配置、日志和 Python 缓存文件。

## 获取项目

使用 Git 克隆项目：

```bash
git clone https://github.com/FFspiky/campus-network-auto-login.git
cd campus-network-auto-login
```

也可以在 GitHub 页面点击 `Code`，选择 `Download ZIP` 下载后解压。

## Windows 快速开始

1. 安装 Python 3。
2. 在项目目录打开 PowerShell。
3. 运行交互式引导：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

如果要覆盖已有 `config.json`，可以运行：

```powershell
.\setup.ps1 -Force
```

引导会检查 Python、安装依赖、创建或更新 `config.json`、录入账号密码、选择 `service`、可选执行一次手动登录测试，并可选安装 Windows 开机自启任务。

## macOS 快速开始

1. 安装 Python 3。可以使用系统已有 Python，也可以用 Homebrew 安装：

```bash
brew install python
```

2. 在项目目录打开终端，赋予脚本执行权限：

```bash
chmod +x setup_macos.sh install_launch_agent.sh check_launch_agent.sh
```

3. 运行交互式引导：

```bash
./setup_macos.sh
```

如果要覆盖已有 `config.json`，可以运行：

```bash
./setup_macos.sh --force
```

引导会检查 Python、安装依赖、创建或更新 `config.json`、录入账号密码、选择 `service`、可选执行一次手动登录测试，并可选安装 macOS LaunchAgent。

macOS 使用用户级 LaunchAgent，安装位置是：

```text
~/Library/LaunchAgents/com.ffspiky.campus-network-auto-login.plist
```

它会在用户登录时运行一次，并每 300 秒运行一次。脚本如果发现已经联网，会直接退出。

## 手动配置

如果不使用交互式引导，也可以手动执行下面步骤。

Windows 安装依赖：

```powershell
python -m pip install -r requirements.txt
```

macOS 安装依赖：

```bash
python3 -m pip install -r requirements.txt
```

复制配置模板：

```bash
cp config.example.json config.json
```

Windows PowerShell 可以使用：

```powershell
Copy-Item .\config.example.json .\config.json
notepad .\config.json
```

至少需要修改这几项：

```json
{
  "username": "你的校园网账号",
  "password": "你的校园网密码",
  "service": "cmcc"
}
```

中国石油大学（华东）ePortal 常用 `service` 字段如下：

| service 值 | 页面显示 |
| --- | --- |
| `default` | 校园网 |
| `local` | 校园内网 |
| `cmcc` | 中国移动 |
| `unicom` | 中国联通 |
| `ctcc` | 中国电信 |

如果你使用中国移动，保持：

```json
"service": "cmcc"
```

也可以让脚本从门户接口读取可用服务：

```bash
python3 campus_login.py --config config.json --list-services
```

Windows PowerShell 可以使用：

```powershell
python .\campus_login.py --config .\config.json --list-services
```

已经验证可用的登录接口是：

```json
"login_url": "http://wlan.upc.edu.cn/eportal/InterFace.do?method=login"
```

注意：`config.json` 会保存明文密码，已经被 `.gitignore` 忽略。不要把它提交到 GitHub。

## 手动测试

先退出校园网登录，或者断开 Wi-Fi 后重新连接，确保浏览器访问网页会跳到校园网认证页。

macOS：

```bash
python3 campus_login.py --config config.json
```

Windows：

```powershell
python .\campus_login.py --config .\config.json
```

成功时会看到类似日志：

```text
Campus login started.
Network check redirected to portal: ...
Submitting campus login request to http://wlan.upc.edu.cn/eportal/InterFace.do?method=login.
Login response: HTTP 200.
Login response indicates success.
Internet is already reachable.
Campus login completed.
```

如果已经联网，脚本会直接输出：

```text
Internet is already reachable.
```

## Windows 安装开机自启

手动测试成功后，用管理员身份打开 PowerShell，进入项目目录后运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install_task.ps1
```

看到以下内容表示计划任务安装成功：

```text
Scheduled task 'CampusNetworkAutoLogin' installed.
```

安装后可以在 Windows “任务计划程序”中找到：

```text
CampusNetworkAutoLogin
```

如果之前已经安装过旧版本任务，重新用管理员 PowerShell 运行 `.\install_task.ps1` 即可覆盖更新。

检查任务：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\check_task.ps1
```

查看日志：

```powershell
Get-Content .\campus_login.log -Tail 50
```

## macOS 安装登录自启

手动测试成功后，在项目目录运行：

```bash
./install_launch_agent.sh
```

看到以下内容表示 LaunchAgent 安装成功：

```text
LaunchAgent 'com.ffspiky.campus-network-auto-login' installed.
```

检查 LaunchAgent：

```bash
./check_launch_agent.sh
```

查看主日志：

```bash
tail -n 50 campus_login.log
```

查看 launchd 标准输出和错误日志：

```bash
tail -n 50 logs/launchd.out.log
tail -n 50 logs/launchd.err.log
```

## 验证自动登录

1. 退出校园网登录，或者断开 Wi-Fi 后重新连接。
2. 重启电脑，或在 macOS 上退出再登录当前用户。
3. 等待 10 到 30 秒。
4. 打开浏览器访问网页，确认是否已联网。
5. 如果没有联网，查看 `campus_login.log` 和对应平台的任务检查脚本输出。

## 常见问题

### 提示 service 不能为空

说明 `config.json` 中的 `service` 为空，或者没有按门户要求填写真实字段值。中国移动应填写：

```json
"service": "cmcc"
```

不是：

```json
"service": "中国移动"
```

### HTTPS 握手失败

如果看到类似错误：

```text
sslv3 alert handshake failure
```

请确认 `login_url` 使用的是 `http`，不是 `https`：

```json
"login_url": "http://wlan.upc.edu.cn/eportal/InterFace.do?method=login"
```

### 请求走了本机代理

如果日志中出现 `127.0.0.1:7897` 之类的代理地址，说明系统代理影响了 Python 请求。当前脚本已经设置 `session.trust_env = False`，默认不会读取系统代理。

### macOS 重启后没有运行

macOS 的用户级 LaunchAgent 在用户登录后运行，不是在系统还停留在登录界面时运行。请确认当前用户已登录，并运行：

```bash
./check_launch_agent.sh
```

如果 LaunchAgent 未加载，可以重新安装：

```bash
./install_launch_agent.sh
```

### 如何确认真实登录请求

如果你的学校或门户配置不同，可以手动确认接口：

1. 退出校园网登录。
2. 打开校园网认证页。
3. 打开浏览器开发者工具。
4. 切换到 Network（网络）标签页。
5. 手动输入账号密码登录。
6. 找到登录请求。
7. 复制 Request URL、请求方法和表单数据。
8. 对应更新 `config.json` 中的 `login_url`、`login_method` 和 `login_payload`。

配置值中支持以下占位符：

- `{username}`
- `{password}`
- `{service}`
- `{portal_url}`
- `{query_string}`
- `{query_string_encoded}`

## 卸载自启任务

Windows：

```powershell
Unregister-ScheduledTask -TaskName CampusNetworkAutoLogin -Confirm:$false
```

macOS：

```bash
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/com.ffspiky.campus-network-auto-login.plist
rm ~/Library/LaunchAgents/com.ffspiky.campus-network-auto-login.plist
```

## 安全说明

- `config.json` 包含明文账号密码，只能保存在本机。
- 不要提交 `config.json`、`campus_login.log`、`logs/` 或任何包含真实账号密码的文件。
- 如果误提交了真实密码，请立即修改校园网密码，并清理 Git 历史后再公开仓库。
