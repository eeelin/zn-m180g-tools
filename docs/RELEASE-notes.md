v0.2.0 将 ZN-M180G 的 SSH 部署统一切换为 root，默认安装目录 /usr/data/sshd-root。

- 安装包加入 start.sh、stop.sh、status.sh、restart.sh 和统一 service.sh。
- 启动时修正认证目录/文件权限，并在缺少 devpts 时尝试挂载；重复启动不产生额外服务。
- 停止前核验进程身份和启动时间，避免陈旧 PID 文件误杀其他进程。
- 安装器新增 --upgrade，保留原 authorized_keys 和 host_ed25519，支持迁移先前手动 root 部署。
- 推荐电脑下载后通过局域网传入，使用 --archive 离线安装，解决光猫旧 TLS 无法访问 GitHub 的问题。
- ARMv7 little-endian / EABI5 soft-float，静态 Dropbear 2026.94 + musl；仍仅支持公钥认证。

全新安装：sh install.sh --archive /var/tmp/zn-m180g-ssh.tar.gz --key 'ssh-ed25519 完整公钥'
已有 root 安装：sh install.sh --archive /var/tmp/zn-m180g-ssh.tar.gz --upgrade

本地通过 QEMU 二进制测试及隔离 user namespace 的 root 安装/服务控制测试。测试适配了 QEMU 执行和 localhost 监听，未由助手在光猫上部署。没有配置开机自启；重启后以 root 运行 start.sh。stop 只停止监听进程，现有连接可能继续。
