# Deferred work

- `server/editor/.config/nvim/init.vim` 和 `server/shell/.tmux.conf` 仍依赖
  `~/Project/others/base16/...`，前者还写死了 `~/dev/go/bin`；这些路径在目录布局不同的
  服务器上会失效，应改为仓库内资源、环境变量或存在性检查。
- `server/shell/.tmux.conf` 将 Fish 固定为 `/usr/bin/fish`；同时
  `server/.config/fish/config.fish` 仍设置第三方姓名和邮箱 `Jon Gjengset` / `jon@tsp.io`，
  应在应用 server 配置前改为动态命令路径并确认身份信息归属。
- Git 历史中的 `f0ddf15`、`3c76380`、`b65aa43` 和 `a608b21` 仍包含旧的
  密码管理器条目名及 AWS/OpenStack 凭据调用代码，但没有检测到真实秘密；若仓库
  暴露这些元数据也不可接受，需要协调后重写历史并强制推送。
