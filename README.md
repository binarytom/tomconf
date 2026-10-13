# tomconf

个人配置文件仓库。当前配置使用 [chezmoi](https://www.chezmoi.io/) 管理：
`mac/` 是实际生效的 macOS chezmoi source state，`server/` 保留服务器专用配置，
不参与 macOS 的 chezmoi 安装。

## 为什么选择 chezmoi

| 工具 | 优点 | 局限 | 结论 |
| --- | --- | --- | --- |
| [chezmoi](https://www.chezmoi.io/) | 原生支持保存、预览、安装、跨平台模板和密钥管理 | 需要学习 source state 的命名规则 | 当前采用 |
| [yadm](https://yadm.io/) | 操作方式接近 Git，支持 alternate files 和加密 | 多平台模板能力不如 chezmoi 集中 | 适合偏好直接管理 `$HOME` 的仓库 |
| [GNU Stow](https://www.gnu.org/software/stow/manual/stow.html) | 简单、透明，只创建软链接 | 需要自行处理跨平台差异、秘密和安装流程 | 适合单机或配置很少的场景 |

chezmoi 将仓库中的期望状态复制到 `$HOME`，而不是让配置依赖仓库路径下的
软链接。它也会在覆盖本地修改前提示，并提供 `diff` 和 dry-run。

## 一键安装

在 macOS 新机器上克隆仓库后运行：

```sh
git clone https://github.com/binarytom/tomconf.git
cd tomconf
./install.sh
```

脚本可以重复执行，并依次完成：

1. 检查 Xcode Command Line Tools，缺失时启动 Apple 的安装程序；
2. 缺少 Homebrew 时下载并运行官方安装器；
3. 用根目录的 `Brewfile` 安装 Shell、编辑器、LSP、BasicTeX 和 GUI 工具；
4. 安装 Rust stable、Node.js LTS、`proximity-sort` 和 VimTeX 所需的 `latexmk`；
5. 安装 Alacritty，并通过 chezmoi 将 `mac/` 应用到 `$HOME`。

Homebrew 或 Xcode 安装过程中可能要求确认或管理员密码。脚本不会执行
`brew bundle cleanup`，所以不会删除机器上已有的其他软件包。

只检查依赖、不安装或应用任何内容：

```sh
./install.sh --check
```

只安装工具、暂不应用配置：

```sh
./install.sh --skip-config
```

Alacritty 的 Homebrew cask 当前因 Gatekeeper 检查失败而被禁用，因此没有写入
`Brewfile`。安装脚本改为下载固定版本的官方 DMG、校验 SHA-256 后安装到
`~/Applications`；它不会关闭或绕过 macOS 的安全策略。若首次启动被拦截，请在
Finder 中右键 Alacritty 并选择“打开”。

脚本只安装 `aws`、`pass` 等客户端，不会创建或导入云凭据、GPG 密钥和密码库；
这些有意保留为安装后的人工配置。

如果工具已经装好，也可以只初始化和应用配置：

```sh
chezmoi init --source "$PWD"
chezmoi diff --source "$PWD"
chezmoi apply --source "$PWD"
```

`diff` 只预览；确认无误后再运行 `apply`。`server/` 不由此脚本安装或应用。

## 日常操作

直接修改 `$HOME` 中的配置后，一条命令保存所有已管理文件：

```sh
chezmoi re-add
```

然后检查并提交：

```sh
chezmoi diff
chezmoi git -- status --short
chezmoi git -- add mac
chezmoi git -- commit
chezmoi git -- push
```

在另一台已经初始化的机器上，一条命令拉取并安装最新配置：

```sh
chezmoi update
```

常用的安全检查：

```sh
chezmoi status
chezmoi diff
chezmoi apply --dry-run --verbose
chezmoi doctor
```

要新增一个配置文件，显式加入它；不要直接加入整个 `~/.config`：

```sh
chezmoi add ~/.config/example/config.toml
```

显式添加可以避免把 token、缓存、数据库或软件运行状态误收进仓库。

## 当前管理范围

- Shell：`.bashrc`、`.profile`、`.tcshrc`、`.zshenv`、`.zshrc` 和 Fish 配置。
- 开发工具：Git 全局配置、全局 ignore、Neovim 配置及插件锁文件。
- 终端：Alacritty 和 tmux 配置。
- 当前桌面配置只面向 macOS；`server/` 保留服务器专用配置。
- `binarytommini` 专用的 Git 本地代理通过主机名模板隔离，其他机器不会依赖
  本机的 Clash 端口。

以下内容有意不纳入版本控制：

- shell 历史、`.viminfo`、`.DS_Store` 等历史和缓存；
- `.claude.json`、Clash 配置、订阅、数据库等可能包含凭据或隐私的数据；
- `fish_variables`、`.testcontainers.properties`、`cagent` 和 Raycast 状态等机器生成文件；
- SSH 私钥、密码管理器内容和任何真实 token。

如果将来确实需要管理秘密，优先使用 chezmoi 的
[加密功能](https://www.chezmoi.io/user-guide/encryption/)或密码管理器模板，
不要提交明文。

## 仓库布局

```text
.
├── .chezmoiroot       # 指定 mac/ 为 source state
├── Brewfile           # macOS 软件包的声明式清单
├── install.sh         # 软件、语言工具链和配置的一键安装入口
├── mac/               # 当前 macOS 配置；按 chezmoi 规则映射到 $HOME
└── server/            # 服务器专用配置，不参与 macOS 安装
```

例如 `mac/dot_zshrc` 对应 `~/.zshrc`，
`mac/dot_config/nvim/init.lua` 对应 `~/.config/nvim/init.lua`，而 `.tmpl`
后缀表示该文件会先按当前主机信息渲染。
