# ZN-M180G root 部署（v0.2.0）

本版本统一以 root 安装、启动和管理 Dropbear SSH，保留公钥认证。无需修改系统密码、账号、固件启动文件或防火墙。默认监听管理地址 `192.168.1.1:2222`，不自动配置开机启动。

## 1. 在电脑准备文件和 SSH 公钥

从同一版本的 [GitHub Release](https://github.com/eeelin/zn-m180g-tools/releases/tag/v0.2.0) 下载 `install.sh`、`zn-m180g-ssh.tar.gz` 及对应 `.sha256` 到独立目录。可以在电脑执行 `sha256sum -c 文件名.sha256` 核对下载完整性。

查看已有 Ed25519 公钥：`cat ~/.ssh/zn_m180g.pub`。没有时执行 `ssh-keygen -t ed25519 -f ~/.ssh/zn_m180g`，不要覆盖已有私钥。只把 `.pub` 的完整一行提供给安装器；私钥留在电脑。

光猫的旧 curl/OpenSSL 不支持 GitHub 要求的 TLS，`curl -k` 不能解决协议版本错误。在下载目录启动临时局域网服务：

```sh
python3 -m http.server 8000
```

## 2. 在光猫 root shell 中安装

执行 `id` 确认 UID 为 0。以下命令把 `电脑IP` 换成光猫可以访问的电脑 LAN 地址：

```sh
cd /var/tmp &&
curl -f http://电脑IP:8000/install.sh -o install.sh &&
curl -f http://电脑IP:8000/zn-m180g-ssh.tar.gz -o zn-m180g-ssh.tar.gz &&
sh install.sh --archive /var/tmp/zn-m180g-ssh.tar.gz \
  --key 'ssh-ed25519 AAAA...你的完整公钥...'
```

安装目录默认为 `/usr/data/sshd-root`。安装器核对内置 SHA256 后才解包，设置目录 700、认证文件 600，并现场生成主机密钥，打印其公钥和指纹，最后启动服务。安装完成后关闭电脑上的临时 HTTP 服务。

已有目录会被拒绝覆盖。`--dir /绝对路径` 可更换目录；`--no-start` 安装后不启动。

## 3. 升级之前手动部署的 root 服务

保留旧的 `authorized_keys`、`host_ed25519` 和安装目录，下载新的脚本和安装包后执行：

```sh
sh /var/tmp/install.sh --archive /var/tmp/zn-m180g-ssh.tar.gz --upgrade
```

升级要求现有目录和两个密钥文件为 root 所有且不是符号链接；若曾用旧包手工解压导致所有权不符，先核对目录和文件再执行：

```sh
chown 0:0 /usr/data/sshd-root /usr/data/sshd-root/authorized_keys /usr/data/sshd-root/host_ed25519
chmod 700 /usr/data/sshd-root
chmod 600 /usr/data/sshd-root/authorized_keys /usr/data/sshd-root/host_ed25519
```

升级先校验新包，再通过新控制器核验并停止旧监听进程，替换程序/脚本，保留公钥和主机密钥，随后启动。失败时保留目录、密钥和日志供排查，不承诺整包事务回滚。`--upgrade --no-start` 会停止旧监听服务后更新文件，但不启动。

旧的 csp 部署仍使用 `/usr/data/sshd-csp`，不要通过修改所有权直接把它当成可信 root 安装升级；使用全新 root 目录，并先按旧部署方式停止占用 2222 的旧服务。

## 4. start / stop / status / restart

```sh
sh /usr/data/sshd-root/start.sh
sh /usr/data/sshd-root/status.sh
sh /usr/data/sshd-root/stop.sh
sh /usr/data/sshd-root/restart.sh
cat /usr/data/sshd-root/sshd.log
```

无需再包一层 nohup。start 自动后台运行且避免重复启动；status 返回 0 表示运行，3 表示未运行或 PID 无效。停止前核对程序路径、工作目录、UID、命令行和记录的启动时间，PID 已过期或属于其他进程时不发送信号。旧手动服务没有 sshd.state 时仍必须通过其余身份检查。

stop 只停止监听主进程，已经建立的 SSH 会话可能继续，不会卸载其他终端共享的 devpts。`start-sshd.sh` 现在是后台 start 的兼容别名；旧的手工 `start-root.sh` 不再使用。

## 5. 连接和终端

```sh
ssh -p 2222 -i ~/.ssh/zn_m180g root@192.168.1.1
```

首次连接核对主机密钥指纹。升级保留主机密钥，正常情况下不应改变指纹。

start 在确认 `/dev/pts` 未挂载 devpts 后，尝试执行 `mount -t devpts devpts /dev/pts -o mode=0600`。若内核不支持或挂载失败，会给出提示；用 `ssh -T -p 2222 -i ~/.ssh/zn_m180g root@192.168.1.1` 运行无 PTY shell。程序保留上游 PTY 权限检查。

若仍出现 `.` 权限错误，使用新 start 脚本并确认没有另外运行旧服务。新脚本始终先进入安装目录，将目录设为 700，并使用 `-F -D .`，保证认证读取的是该目录下的公钥文件。

未提供 SFTP/scp；可通过 SSH 标准输入传文件。仅绑定管理地址不等于按来源限制访问，实际可达范围依赖已有路由和防火墙。

## 6. 重启和验证范围

`/usr/data` 是此前检查到的持久化 JFFS2，程序、密钥和权限通常跨重启保留；`/var/tmp` 是临时存储。重启后服务停止，手动 devpts 挂载也消失。重新获得 root 后运行 start.sh 可恢复服务。没有配置开机自启，也没有确认 root 权限获取方式是否跨重启保留。

目标 CPU 是 ZX279128S 双核 Cortex-A9、ARMv7 小端软浮点 EABI5，内核 Linux 4.1.25，原系统 glibc 2.26。二进制使用静态 musl，不依赖设备的 glibc/OpenSSL。

软件经过本地 ARM 模拟和隔离 root 环境的脚本测试，没有由助手在光猫上安装或操作服务。QEMU 使用宿主内核，不能替代固件实测；用户此前已反馈旧版 root 服务成功连接。历史检查记录见 VALIDATION-original.txt，当前测试结果随 Release 提供。
