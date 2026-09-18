# ZN-M180G 的 SSH 服务安装说明

本包是 Dropbear 2026.94（SSH 服务端及主机密钥生成器），不是 OpenSSH 的 sshd。
编译和模拟测试均在电脑上进行；未向光猫上传、安装或运行任何程序，未主动执行写文件、修改配置、挂载或重启命令。Telnet 登录本身可能被设备自行记入日志。

## 一键安装入口

仓库根目录的 [install.sh](https://github.com/eeelin/zn-m180g-tools/blob/main/install.sh) 已自动化本文的下载、校验、公钥配置、主机密钥生成和后台启动步骤。在 csp Telnet shell 中执行，把引号中的内容换成电脑上的完整 Ed25519 公钥：

```sh
wget -O- https://raw.githubusercontent.com/eeelin/zn-m180g-tools/main/install.sh | sh -s -- --key 'ssh-ed25519 AAAA...你的完整公钥...'
```

默认固定安装 v0.1.0 到 `/usr/data/sshd-csp`，不会覆盖已有安装，不配置开机自启。可用 `--no-start` 仅安装；HTTPS 不可用时，先在电脑下载并传入脚本和 v0.1.0 安装包，再执行 `sh install.sh --archive /path/to/zn-m180g-ssh.tar.gz --key '你的完整公钥'`。此时不再需要执行下文的手动安装步骤。脚本仅经过本地 QEMU 测试，尚未在设备上执行。

## 1. 已读取的设备信息

| 项目 | 实际结果 |
| --- | --- |
| 页面型号 | ZN-M180G |
| SoC | ZTE ZX279128S |
| CPU | 双核 ARMv7，CPU part 0xc09（Cortex-A9） |
| 字节序 / ABI | 32 位小端，ARM EABI5，soft-float |
| 内核 | Linux 4.1.25，2021-11-19 构建 |
| libc | glibc 2.26，/lib/ld-linux.so.3 |
| 内存 | MemTotal 461232 KiB |
| Telnet 后的身份 | csp，UID 108 / GID 110；不是 root |
| csp 的 home / shell | / 和 /bin/sh |
| 可考虑的存储 | /usr/data，JFFS2，检查时约 86 MiB 可用，目录权限 777 |
| 临时目录 | /tmp -> /var/tmp；/var 为 tmpfs，重启丢失 |
| PTY | 存在旧式 /dev/ptyp0、/dev/ttyp0；未挂载 devpts |

安装后 SSH 用户名应为 `csp`，不是 Telnet 输入的管理账号名。本包不含任何设备密码；仅支持公钥认证。登录后权限仍是 csp。

## 2. 电脑上准备登录公钥

在你将来用于 SSH 登录的电脑运行。若这个文件已存在，请使用已有公钥或另取文件名，不要覆盖原私钥。

```sh
ssh-keygen -t ed25519 -f ~/.ssh/zn_m180g -C zn-m180g
cat ~/.ssh/zn_m180g.pub
```

妥善保留 `~/.ssh/zn_m180g` 私钥。只把以 `ssh-ed25519` 开头的 `.pub` 文件内容传到光猫。

## 3. 传入安装包（以下是你自行安装时才执行的写操作）

将 `zn-m180g-ssh.tar.gz` 放在电脑上的单独目录，在该目录启动临时下载服务：

```sh
python3 -m http.server 8000 --bind 0.0.0.0
```

电脑地址必须能由光猫访问。如果光猫位于上级网段，可能需要将电脑临时接到光猫 LAN，让两者能直接通信。安装完成后用 Ctrl+C 关闭临时下载服务。

在 Telnet 中运行以下整段，把 `192.168.1.2` 换成电脑实际可达的 LAN 地址。`mkdir` 遇到已有安装目录会停止，避免覆盖已有密钥。

```sh
(
set -e
umask 077
mkdir /usr/data/sshd-csp
chmod 700 /usr/data/sshd-csp
cd /usr/data/sshd-csp
wget -O package.tar.gz http://192.168.1.2:8000/zn-m180g-ssh.tar.gz
tar -xzf package.tar.gz
sha256sum -c SHA256SUMS
chmod 700 dropbearmulti start-sshd.sh
)
```

若下载失败，先修正网络问题，再进入已创建的目录重试下载和解压，不要重复运行创建目录的整段。可以把压缩包的 SHA256 与随附文件 `zn-m180g-ssh.tar.gz.sha256` 比较。

## 4. 配置公钥和本机主机密钥

在 Telnet 中运行。将示例占位行完整替换成第 2 步打印的公钥；不要原样保留占位内容。

```sh
(
set -e
umask 077
cd /usr/data/sshd-csp
cat > authorized_keys <<'PUBLIC_KEY'
在这里粘贴你的 ssh-ed25519 公钥完整一行
PUBLIC_KEY
chmod 600 authorized_keys
./dropbearmulti dropbearkey -t ed25519 -f host_ed25519
chmod 600 host_ed25519
)
```

记下生成器打印的 `SHA256:...` 主机密钥指纹，首次 SSH 连接时核对。不要反复生成主机密钥。已存在时可用下面命令查看指纹：

```sh
/usr/data/sshd-csp/dropbearmulti dropbearkey -y -f /usr/data/sshd-csp/host_ed25519
```

## 5. 启动和连接

先在 Telnet 前台启动以便看到错误：

```sh
sh /usr/data/sshd-csp/start-sshd.sh
```

在电脑的另一个终端连接：

```sh
ssh -T -p 2222 -i ~/.ssh/zn_m180g -o IdentitiesOnly=yes csp@192.168.1.1 'id; uname -a'
```

需要连续输入命令时可以使用没有 PTY 的 shell：

```sh
ssh -T -p 2222 -i ~/.ssh/zn_m180g -o IdentitiesOnly=yes csp@192.168.1.1 /bin/sh
```

此方式通常不显示交互提示符，不适合 vi、top 等依赖终端的程序；输入 `exit` 结束。现有 csp 权限下，这是本包面向当前设备环境的使用方式。

确认可连接后，在 Telnet 前台按 Ctrl+C 停止刚才的服务，然后后台启动：

```sh
cd /usr/data/sshd-csp
umask 077
nohup sh ./start-sshd.sh > ./sshd.log 2>&1 < /dev/null &
```

查看日志、停止服务：

```sh
cat /usr/data/sshd-csp/sshd.log
# 先核对 PID 确实属于本安装的 dropbearmulti，再执行 kill。
cat /usr/data/sshd-csp/sshd.pid
ps | grep dropbearmulti
kill "$(cat /usr/data/sshd-csp/sshd.pid)"
```

启动脚本绑定 `192.168.1.1:2222`，禁用转发，仅支持公钥，不会修改防火墙。绑定管理地址不等于按来源地址限制访问，实际可达范围还取决于设备路由和防火墙。

没有配置开机自启。正常情况下 /usr/data 中的文件会跨重启保留，但固件升级或恢复出厂可能清理它；重启后需手动启动。没有确认厂商启动机制，因此不要直接改厂商 rc 文件。

## 6. 完整交互终端的限制

当前系统没有挂载 devpts；现有的旧式 PTY 属于 root，csp 不能正常调整其所有权。原版 Dropbear + musl 的 openpty 使用 /dev/ptmx 和 devpts，因此当前设备用普通 `ssh` 申请 PTY 可能失败。这不是 CPU 架构不匹配。

如果你之后取得 root，可由 root 检查并挂载 devpts，再尝试普通 SSH。这会更改运行时挂载状态，本文的检查阶段没有执行。确认尚未挂载后，典型命令为：

```sh
# 仅供已取得 root 后手动执行；不要在已有 devpts 挂载上重复执行。
mount -t devpts devpts /dev/pts -o mode=0600
```

然后仍以 csp 启动本包，再用 `ssh -t -p 2222 ... csp@192.168.1.1` 测试。设备内核是否启用了可用的 Unix98 PTY 仍须实机确认，挂载失败时继续使用 `-T`。不要将现有 /dev/tty* 批量 chmod/chown。本包没有放宽 PTY 所有权检查。

## 7. 文件传输与故障定位

未编入 SFTP，也没有随包提供 scp 客户端，所以普通 `sftp` / `scp` 不属于本包功能。需要传小文件时可以通过 SSH 标准输入，例如安装后在电脑运行：

```sh
ssh -T -p 2222 -i ~/.ssh/zn_m180g csp@192.168.1.1 \
  'umask 077; cat > /usr/data/sshd-csp/example.txt' < example.txt
```

- `Permission denied (publickey)`：检查使用的是 csp、匹配的私钥，以及 authorized_keys 为完整公钥一行。
- 目录/密钥权限报错：安装目录需 csp 所有且 700，authorized_keys 和 host_ed25519 需 csp 所有且 600。
- PTY allocation failed：使用 `ssh -T`，参阅第 6 节。
- 连接拒绝/超时：先在 Telnet 前台启动查看日志；确认光猫管理地址、端口和本机到光猫的网络路径。
- 不要去掉启动命令中的 `-F`：本包使用当前目录下的 `authorized_keys`，后台化由外层 nohup 完成。csp 的 home 是 /，而可写父目录权限较宽，直接指定绝对路径会触发上游公钥目录权限检查。`-F -D .` 保持在 csp 自有的 700 目录中运行，不修改上游源码或系统目录权限。

## 8. 编译来源和验证范围

- 上游发布源码：https://matt.ucc.asn.au/dropbear/releases/dropbear-2026.94.tar.bz2
- 官方介绍：https://matt.ucc.asn.au/dropbear/dropbear.html
- Bootlin 工具链：https://toolchains.bootlin.com/releases_armv5-eabi.html
- 工具链：armv5-eabi--musl--stable-2025.08-1，GCC 14.3.0 / musl 1.2.5。工具链采用软浮点，编译目标显式设为 `-march=armv7-a -marm -mfloat-abi=soft`。
- 产物：ARM ELF32 little-endian / EABI5 / soft-float，静态链接；无需在光猫安装 musl，也不使用光猫的 glibc / OpenSSL。
- 保留上游认证逻辑；禁用密码、PAM、SFTP、X11、zlib、syslog、utmp/wtmp/lastlog。
- 发布包和工具链 SHA256 已与 HTTPS 官方列表核对；未声称验证 PGP 签名。
- 验证：ELF 头/程序段/属性检查；QEMU Cortex-A9 下生成主机密钥、公钥登录、执行命令；错误公钥、错误用户名、可写认证目录均被拒绝。
- QEMU user-mode 使用电脑内核，不能证明光猫 4.1.25 内核上的全部运行行为。遵守只读要求，没有进行实机执行或连接测试；最终运行、固件策略和 PTY 仍需你安装后验证。

`ELF-info.txt` 为产物信息，`VALIDATION-original.txt` 为原始验证记录。另附 `zn-m180g-ssh-source.tar.gz`，包含原始源码包、实际构建脚本 `scripts/build.sh`、下载地址及校验值；解压后按 README.md 构建。当前构建的测试结果另附 SMOKE-TEST.txt。许可证见 LICENSE.dropbear 和 LICENSE.musl。
