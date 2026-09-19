# ZN-M180G Tools

中国移动 ZN-M180G / ZX279128S 的静态 Dropbear SSH 服务端。**从 v0.2.0 起统一使用 root 安装和启动**，默认目录 `/usr/data/sshd-root`，地址 `192.168.1.1:2222`，仅公钥认证。

## 下载与安装

从 [Releases](https://github.com/eeelin/zn-m180g-tools/releases) 下载 **同一个版本**的 `install.sh` 和 `zn-m180g-ssh.tar.gz`。

这台光猫的旧 TLS 无法直接连接 GitHub，推荐在电脑下载，再通过局域网 HTTP 传入光猫。完整步骤、升级方式与重启说明见 [中文安装说明](docs/INSTALL-zh.md)。在 root shell 中安装：

```sh
sh /var/tmp/install.sh --archive /var/tmp/zn-m180g-ssh.tar.gz \
  --key 'ssh-ed25519 AAAA...你的完整公钥...'
```

已有 `/usr/data/sshd-root` 的用户使用下面的升级命令，**保留 authorized_keys 和 host_ed25519**，不需要重新传公钥：

```sh
sh /var/tmp/install.sh --archive /var/tmp/zn-m180g-ssh.tar.gz --upgrade
```

安装器校验内置 SHA256 和包内清单，生成新的主机密钥或保留旧密钥，并启动服务。`--no-start` 仅安装（升级时仍会先停止旧监听服务）。不要将 csp 的旧目录当成 root 目录升级，改为全新 root 安装。

支持现代 TLS 的设备也可以使用：

```sh
curl -fsSL https://raw.githubusercontent.com/eeelin/zn-m180g-tools/main/install.sh | sh -s -- --key 'ssh-ed25519 AAAA...你的完整公钥...'
```

## 服务控制

安装包内提供以下脚本，不需要额外 nohup 或 `&`：

```sh
sh /usr/data/sshd-root/start.sh
sh /usr/data/sshd-root/status.sh
sh /usr/data/sshd-root/stop.sh
sh /usr/data/sshd-root/restart.sh
```

- start 在后台启动，并修正 root 目录/密钥权限，避免 `.` 目录权限错误；重复启动不会新增进程。
- start 在 `/dev/pts` 尚未挂载 devpts 时尝试挂载。失败会提示使用 `ssh -T`，不阻止无 PTY SSH。
- stop 核对进程的程序、工作目录、UID、命令参数及启动时间，不向 PID 文件中无关的进程发送信号。只停止监听主进程，现有 SSH 会话可能继续。
- status 运行时返回 0，未运行或 PID 无效时返回 3。
- restart 先停止再启动；stop 不卸载共享的 devpts。
- `service.sh start|stop|status|restart` 是统一入口，`start-sshd.sh` 为兼容别名。

从电脑连接，首次核对安装器显示的主机密钥指纹：

```sh
ssh -p 2222 -i ~/.ssh/zn_m180g root@192.168.1.1
```

未配置开机自启。重启后以 root 执行 `start.sh` 即可尝试恢复挂载并启动服务；`/usr/data` 文件通常保留，`/var/tmp` 文件不保留。固件升级、恢复出厂及 root 获取方式的持久性不在本工具控制范围内。

## 本地构建与测试

构建环境为 Linux x86_64，需要 curl、make、tar、xz、bzip2、sha256sum、python3。无需系统 GCC 或 root。

```sh
./scripts/build.sh
QEMU_ARM=/path/to/qemu-arm-static python3 scripts/smoke-test.py
QEMU_ARM=/path/to/qemu-arm-static python3 scripts/test-installer.py
```

构建脚本校验固定版本的 Dropbear 2026.94 和 Bootlin GCC 14.3.0 / musl 1.2.5 工具链。目标为 ARMv7 小端、EABI5 软浮点，静态链接，不依赖光猫的旧 glibc/OpenSSL。未修改上游源码，编译选项在 `config/localoptions.h`。第三方许可证见 `licenses/`。

产物位于 `dist/`：安装包、源码包、对应 SHA256、带安装包固定校验值的 `install.sh`。构建缓存和产物不进入 Git。源码包包含上游源码和完整构建脚本，解压后可执行 `scripts/build.sh`。

二进制认证测试使用 QEMU；root 安装和服务控制测试使用隔离的 Linux user namespace（需要启用 unprivileged user namespaces），覆盖安装/升级、密钥保留、启动/重复启动、停止/重启、陈旧 PID、无关进程保护及错误安装包。user namespace 中无法模拟固件全部行为；测试适配 QEMU 启动、程序路径和 localhost 端口，不操作光猫。原始设备检查记录见 `docs/VALIDATION-original.txt`。

## 发布

```sh
./scripts/build.sh
cp dist/install.sh install.sh
# 运行上面的测试，然后提交所有修改
./scripts/release.sh v0.2.0
```

发布脚本校验安装器与安装包、版本号和测试产物，推送当前提交并创建 Release，包含控制脚本的安装包、源码包、独立安装器、说明及测试报告。不会覆盖已有 Release。
