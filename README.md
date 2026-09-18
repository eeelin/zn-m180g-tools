# ZN-M180G Tools

中国移动 ZN-M180G 光猫工具，当前提供适配 ZX279128S 的静态 Dropbear SSH 服务端。

- ARMv7 little-endian / EABI5 / soft-float，适配检查到的 Linux 4.1.25 环境。
- Dropbear 2026.94 + musl 1.2.5，服务端与密钥生成器合并为约 358 KiB 的静态程序。
- 使用现有 `csp` 用户和公钥认证，默认监听 `192.168.1.1:2222`。
- 不包含设备账号密码、登录私钥或预生成主机私钥；不修改光猫配置，不配置自动启动。

## 下载与安装

从 [GitHub Releases](https://github.com/eeelin/zn-m180g-tools/releases) 下载 `zn-m180g-ssh.tar.gz` 和对应 `.sha256`。

完整步骤：[中文安装说明](docs/INSTALL-zh.md)。

当前检查到的设备没有挂载 devpts，现有账号也不是 root，请使用 `ssh -T`。完整 PTY 终端的前提与处理方式见安装说明。SSH 登录后的用户名是 `csp`，权限不会提升。

## 本地构建

构建环境：Linux x86_64，安装 `curl`、`make`、`tar`、`xz`、`bzip2`、`sha256sum`、`python3` 以及常见 POSIX 工具。不需要系统 GCC 或 root；脚本下载固定版本的交叉工具链。

```sh
git clone https://github.com/eeelin/zn-m180g-tools.git
cd zn-m180g-tools
./scripts/build.sh
```

脚本先核对 `sources.sha256`，再解压、编译和打包。默认并行 4 个任务，可用 `JOBS=2 ./scripts/build.sh` 调整。

下载缓存位于 `downloads/`，源码与工具链位于 `build/`，产物位于 `dist/`，这些目录均不提交进 Git。`config/localoptions.h` 存放定制选项；没有修改上游源码。

主要产物：

| 文件 | 用途 |
| --- | --- |
| `dist/zn-m180g-ssh.tar.gz` | 设备安装包，包含二进制、启动脚本、说明、许可证和内部校验清单 |
| `dist/zn-m180g-ssh-source.tar.gz` | 原始 Dropbear 源码包、构建/打包/测试脚本及配置；工具链在构建时下载 |
| `dist/*.sha256` | 发布包 SHA256 |
| `dist/zn-m180g-ssh/ELF-info.txt` | ELF 架构及程序段信息 |

源码包也可直接解压后运行 `./scripts/build.sh`。源码与工具链来自 [Dropbear](https://matt.ucc.asn.au/dropbear/dropbear.html) 和 [Bootlin](https://toolchains.bootlin.com/releases_armv5-eabi.html)。第三方许可证位于 `licenses/`，同时收入安装包。

## 本地验证

安装 QEMU user-mode 和 OpenSSH 客户端后，以普通用户运行：

```sh
python3 scripts/smoke-test.py
# 如 QEMU 不在 PATH 中：
QEMU_ARM=/absolute/path/qemu-arm-static python3 scripts/smoke-test.py
```

测试启动本地 ARM Cortex-A9 模拟进程，只监听 localhost 的临时端口，检查公钥登录、命令执行，以及错误密钥/错误用户/可写认证目录被拒绝。测试密钥位于临时目录并自动清理；结果写入 `dist/SMOKE-TEST.txt`。

QEMU user-mode 使用宿主内核，不等同于真机 Linux 4.1.25 测试。没有在光猫上上传或执行产物；原始检查和验证记录见 [VALIDATION-original.txt](docs/VALIDATION-original.txt)。

## 发布

仓库代码提交后，重新构建并运行测试，再发布：

```sh
./scripts/build.sh
python3 scripts/smoke-test.py
./scripts/release.sh v0.1.0
```

需要配置 Git 和 GitHub CLI 的仓库写权限。发布脚本将当前提交推送到 `main`，然后在该提交上创建带安装包、源码包、校验值、测试结果和中文安装说明的 Release；不会覆盖已有 Release。
