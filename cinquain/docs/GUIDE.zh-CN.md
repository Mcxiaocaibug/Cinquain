# Cinquain 小白部署指南（中文版）

本指南面向没有服务器运维经验的新手。跟着做，大约 15 分钟就能拥有一台属于自己的
Matrix 聊天服务器（可以和全世界的 Matrix 用户互通，类似自己开一台"微信服务器"）。

---

## 第 0 步：你需要准备什么

| 需要的东西 | 说明 | 大概费用 |
|---|---|---|
| 一台云服务器（VPS） | 全新安装的 Debian 12 / Ubuntu 22.04+ 或 Fedora/RHEL 系统，至少 2 GB 内存、10 GB 硬盘 | 每月几美元起 |
| 一个域名 | 例如 `example.com`，将来你的账号会长这样：`@你:matrix.example.com` | 每年 $10 左右 |
| 你自己的电脑 | Windows / macOS / Linux 都可以，需要能用终端（命令行） | — |

> **重要**：域名一旦部署就**不能更换**（Matrix 协议决定的），换域名等于全部重来。
> 请想好再填。

### 先做一件事：域名解析

到你买域名的网站（阿里云、Cloudflare、Namecheap 等），添加一条 DNS 记录：

- **类型**：A
- **主机名**：`matrix`（这样完整域名就是 `matrix.example.com`）
- **值**：你服务器的公网 IP 地址

等 5–10 分钟让解析生效。可以在电脑上运行 `ping matrix.example.com`
检查——如果显示的是你服务器的 IP，就说明成功了。

另外确认云服务商的**安全组/防火墙**放行了 **80 和 443** 两个 TCP 端口
（SSH 的 22 端口通常默认已放行）。

---

## 第 1 步：在服务器上运行一条命令

用 SSH 登录你的服务器（Windows 可用系统自带的"终端"或 PowerShell）：

```bash
ssh root@你的服务器IP
```

登录后有两种方式，任选一种。

### 方式一（最省事）：一条命令全自动部署

把域名和你的邮箱直接写在命令里，全程无需再操作：

```bash
curl -fsSL https://raw.githubusercontent.com/Mcxiaocaibug/Cinquain/cinquain-v0.0.1/cinquain/bootstrap.sh \
  | sudo sh -s -- matrix.example.com admin@example.com
```

把 `matrix.example.com` 换成你的 Matrix 域名，`admin@example.com` 换成你的邮箱
（用于接收证书到期提醒）。

它会自动装好依赖、检查 DNS 与端口、申请 HTTPS 证书、启动服务，最后直接打印
**首次注册令牌**。看到令牌就说明成功了，可以跳到下面的「创建你的账户」。

如果域名还没解析到这台服务器，或者 80/443 端口被别的程序占用，命令会立刻停下并
告诉你具体原因——不会等到最后才失败。

### 方式二：网页面板一步步来

不写域名和邮箱，就只安装面板，在浏览器里填写：

```bash
curl -fsSL https://raw.githubusercontent.com/Mcxiaocaibug/Cinquain/cinquain-v0.0.1/cinquain/bootstrap.sh | sudo sh
```

它会自动安装 Docker 等所有依赖，并启动一个**只有你能访问**的网页部署面板。
运行结束时屏幕会打印两行关键信息，类似：

```
在你的电脑上执行: ssh -N -L 7080:127.0.0.1:7080 root@203.0.113.10
然后打开: http://127.0.0.1:7080/#token=一长串字母数字
```

**把这两行复制保存下来。**

---

## 第 2 步：在你自己的电脑上打开面板

面板出于安全考虑不对公网开放，需要先建立一条"SSH 隧道"（可以理解为
从你电脑到服务器的加密专线）：

1. 在**你自己的电脑**上新开一个终端窗口，粘贴运行第 1 步打印的那条
   `ssh -N -L 7080:...` 命令。
2. 运行后**看起来卡住不动是正常的**——隧道正在工作，别关这个窗口。
3. 打开浏览器，访问第 1 步打印的 `http://127.0.0.1:7080/#token=...` 完整网址。

看到 Cinquain 部署面板就成功了。

---

## 第 3 步：在网页上完成部署

1. 填写 **Matrix 域名**（例如 `matrix.example.com`，就是第 0 步解析的那个）。
2. 填写 **管理员邮箱**（用于申请免费 HTTPS 证书，填你常用邮箱即可）。
3. 点击 **验证并自动部署**。

面板会实时滚动显示部署进度：拉取镜像 → 生成配置 → 启动服务 → 自动申请
HTTPS 证书 → 健康检查。全程 2–5 分钟，不需要任何操作。

全部变绿后，面板会显示一个**一次性注册令牌**（registration token）。
复制它——这是创建管理员账号的钥匙，只能用一次。

---

## 第 4 步：注册你的管理员账号

1. 打开面板给出的注册页面：`https://matrix.example.com/_continuwuity/account/register/`
2. 填用户名、密码，并粘贴刚才的注册令牌。
3. 注册成功——**第一个注册的账号自动成为服务器管理员**。

---

## 第 5 步：开始聊天

1. 下载 Matrix 客户端 **Element**（[element.io](https://element.io/download)，
   有手机版和电脑版）。
2. 登录时选择 **"其他/自定义服务器"**，填入 `https://matrix.example.com`。
3. 输入刚注册的用户名和密码，登录成功！

你的完整 Matrix ID 是 `@用户名:matrix.example.com`，可以邀请任何 Matrix
用户聊天，包括 `matrix.org` 上的用户。

---

## 日常维护（可选，但建议看一眼）

所有命令都在**服务器**上的 `/opt/cinquain` 目录下运行：

```bash
cd /opt/cinquain

./cinquain status     # 查看服务是否正常运行
./cinquain doctor     # 全面健康体检
./cinquain logs       # 查看日志
./cinquain backup     # 手动备份（备份文件在 backups/ 目录）
./cinquain restore backups/某个备份文件.tar.gz   # 从备份恢复
./cinquain upgrade    # 升级到新版本（会先自动备份，失败自动回滚）
```

建议：

- **定期备份**，并把 `backups/` 里的文件下载到服务器之外的地方保存
  （备份文件包含全部聊天数据，请当作机密保管）。
- 部署完成后如果不再需要面板，可以关掉它：
  ```bash
  sudo systemctl disable --now cinquain-panel
  ```
  以后想用随时 `sudo systemctl start cinquain-panel` 再打开。

---

## 常见问题

**Q：浏览器打开面板显示"面板令牌无效"？**
网址必须带上完整的 `#token=...` 部分。重新完整复制第 1 步打印的网址。
令牌也保存在服务器的 `/etc/cinquain/panel.env` 里，`sudo cat` 可以查看。

**Q：部署卡在申请 HTTPS 证书？**
九成是 DNS 没生效或 80/443 端口没放行。检查第 0 步的两项准备，然后在
面板里重新点部署（命令是幂等的，重复执行是安全的）。

**Q：注册令牌显示为空？**
说明管理员已经注册过了（令牌只能用一次），或服务还没就绪。
在服务器上运行 `cd /opt/cinquain && ./cinquain token` 查看。

**Q：想换域名怎么办？**
不能换。只能清空数据重来：备份好需要的东西后删除 Docker 卷重新部署。

**Q：服务器重启后服务会自动恢复吗？**
会。所有容器都配置了自动重启，无需手动干预。
