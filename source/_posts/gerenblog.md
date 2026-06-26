---
title: 从零搭建个人博客
date: 2026-06-26 22:29:16
categories: 技术分享
tags: [博客, Hexo, Linux, 部署]
---
## 为什么写这篇文章

在建这个博客之前，我以为搭建博客就是“装个 Hexo，改个配置，push 到 GitHub”那么简单。实际上，我花了远比预期更多的时间，遇到了各种各样的坑。这篇文章记录的，就是我真实的搭建过程，希望对想自己搭博客的人有用。

## 一、为什么选 Hexo + 自建服务器

我选 Hexo 的原因很简单：静态博客快、安全、不需要数据库。而且我是计算机学生，想顺便学习 Linux 运维，所以选择了自建服务器（之前文章提到的 Azure 的学生免费实例）而不是用 GitHub Pages。

### 技术栈最终变成了这样：
- **框架**：Hexo
- **主题**：Butterfly（我尝试过很多主题，比如 Shiro，后来因为各种原因换成了这个主题）
- **部署方式**：起初在本地生成静态文件，通过 rsync 推送到 Azure 服务器。后来改用 GitHub Actions 自动部署
- **Web 服务器**：Nginx
- **域名管理**：Cloudflare（DNS + CDN + 免费 SSL）
- **评论系统**：Giscus（基于 GitHub Discussions）

整个过程没有用 GitHub Pages 或 Vercel，因为我想保留对服务器的完全控制。

---

## 二、第一步：初始化本地博客

在 WSL 里执行：

```bash
cd /mnt/d/myblog
hexo init
npm install
hexo server
```

然后在浏览器打开 `http://localhost:4000`，看到 Hexo 默认页面，说明成功了。

**踩坑记录**：一开始我用的是 Windows 原生 cmd 而不是 WSL，后来发现很多 Linux 命令在 WSL 里更顺畅，于是全程在 WSL 里操作。

---

## 三、第二步：选择主题

我第一个装的主题是 Shiro，外观感觉一般，而且它的配置文档对新手不够友好，调整颜色时总是无法同步到服务器。换到 Butterfly 之后舒服很多，社区活跃，文档齐全。

> 补充一下：如果你发现本地预览正常但部署后没变化，很可能是浏览器或 Cloudflare 缓存的问题，强制刷新（Ctrl+F5）或清除 Cloudflare 缓存。

---

## 四、第三步：服务器配置

我的服务器是 Azure 的 1 核 1G 学生实例（`Standard_B2ats_v2`），系统 Ubuntu 22.04。

主要做了三件事：

1. 安装 Nginx
2. 创建 `/var/www/blog/` 目录
3. 配置 Nginx 指向该目录，并设置 `server_name blog.oldplum.dev`

Nginx 配置的关键是：

```nginx
server {
    listen 80 default_server;
    server_name blog.oldplum.dev;
    root /var/www/blog;
    index index.html;
}
```

这里有一个容易忽略的点：`default_server` 意味着如果请求没有匹配的 `server_name`，会落到这个配置。我一开始没注意，导致访问 IP 时跳到了我自己的网盘服务。
当然不设置问题应该也不大，只是调试没那么方便。

---

## 五、第四步：部署流程

### 最初方案：手动 rsync 部署

本地生成并同步到服务器，我用的是 rsync：

```bash
hexo clean && hexo generate
rsync -avz --delete -e "ssh -i ~/.ssh/id_rsa" public/ azureuser@服务器IP:/var/www/blog/
```

为了方便，我最初是写了一个 `deploy.sh` 脚本，一键完成生成和同步。

**踩坑记录**：

- 第一次用 rsync 时密钥权限报错，因为 Windows 下的私钥权限是 `0444`，需要改成 `600`，或者在 WSL 里复制到 `~/.ssh/` 目录。
- 后来迁移了 WSL 到 F 盘，重新配置了 Node 环境，才彻底稳定。

### 改进方案：GitHub Actions 自动部署

手动部署久了还是觉得麻烦——每次写完文章都要切到 WSL 跑脚本。于是改成了 GitHub Actions，push 代码后自动部署。

在仓库里创建 `.github/workflows/deploy.yml`：

```yaml
name: 自动部署到服务器

on:
  push:
    branches:
      - main  # 推送到 main 分支时触发部署

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - name: 签出代码
      uses: actions/checkout@v4

    - name: 设置 Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '20'
        cache: 'npm'

    - name: 安装依赖
      run: npm install

    - name: 清理并生成静态文件
      run: |
        npx hexo clean
        npx hexo generate

    - name: 安装 SSH 密钥
      uses: webfactory/ssh-agent@v0.9.0
      with:
        ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}

    - name: 添加服务器到已知主机
      run: |
        mkdir -p ~/.ssh
        ssh-keyscan -H 服务器IP >> ~/.ssh/known_hosts

    - name: 通过 rsync 部署到服务器
      run: |
        rsync -avz --delete public/ ${{ secrets.SSH_USER }}@服务器IP:/var/www/blog/
```

**配置 Secrets**：在 GitHub 仓库的 `Settings → Secrets and variables → Actions` 中添加两个密钥：
- `SSH_PRIVATE_KEY`：服务器的 SSH 私钥内容
- `SSH_USER`：服务器用户名（如 `azureuser`）

**踩坑记录**：
- `webfactory/ssh-agent` 这个 Action 会自动处理 SSH 密钥权限问题，比手动 `chmod 600` 更可靠。
- `ssh-keyscan` 步骤很重要，缺少它的话 rsync 会因为无法验证主机指纹而失败。
- `hexo clean` 要在 `hexo generate` 之前执行，否则缓存可能导致旧 CSS 残留，和之前遇到的问题一样。

现在工作流变成：**写完文章 → push 到 GitHub → 几分钟后自动部署上线**，不用再手动开 WSL 了。

---

## 六、第五步：域名与 HTTPS

域名我在 Name.com 用 GitHub 学生包免费申请了 `oldplum.dev`，然后通过 Cloudflare 管理 DNS。

HTTPS 由 Cloudflare 提供（边缘证书 + 灵活加密模式），不需要在服务器上配置 SSL 证书。这个方案对低配服务器特别友好。

---

## 七、我自己遇到的问题和解决方案

### 1. Node.js 版本不兼容
Hexo 8 需要 Node 20+，但我装了 Node 18，导致部署时报 `ERR_REQUIRE_ESM`。解决方法是切换 Node 版本：

```bash
nvm install 20
nvm use 20
```

### 2. WSL 文件系统损坏
有段时间 WSL 频繁报 I/O 错误，原因是我的电脑的 C 盘满了。最后把 WSL 迁移到了 F 盘：

```bash
wsl --export Ubuntu F:\ubuntu_backup.tar
wsl --unregister Ubuntu
wsl --import Ubuntu F:\wsl_data\ F:\ubuntu_backup.tar
```

### 3. 快捷方式部署环境不一致
双击 .bat 文件部署时总是报错，但在 WSL 手动执行 `./deploy.sh` 却成功。原因是快捷方式没有加载 `~/.bashrc`，导致 nvm 未生效。最后在脚本里加了 `source ~/.nvm/nvm.sh` 解决。

### 4. 修改主题颜色后同步失败
本地预览正常，但部署后颜色没变。排查发现是因为没有 `hexo clean`，旧的 CSS 缓存没清除。养成习惯后就好了：

```bash
hexo clean && hexo generate && ./deploy.sh
```

### 5. 白屏问题
有几次部署后浏览器显示白屏，看不到任何内容。排查顺序：
1. 清除浏览器缓存（Ctrl+F5）
2. 清除 Cloudflare 缓存
3. 检查 `hexo generate` 是否成功
4. 检查服务器上 `index.html` 是否存在

---

## 八、配置评论系统：Giscus

我用 Giscus 替代了内嵌评论系统，它的好处是所有评论存储在 GitHub 仓库里，不需要额外维护数据库。

配置步骤：
1. 在 GitHub 上创建或指定一个公开仓库，开启 Discussions
2. 安装 Giscus App，授权该仓库
3. 在 Butterfly 主题配置中填入 repo、category 等信息

---

## 九、现在你看到的博客

这个博客目前支持：
- 分类 / 标签
- 本地搜索
- 文章归档
- Giscus 评论
- 暗黑模式
- 自定义主题色（主色 #224294，这是我的偶像*周深*的应援色）

后续计划不止写技术的内容，也加入更多内容方向（足球、地理、甚至*周深*）。

---

## 十、一点感触

这个博客从搭建到稳定运行，前后折腾了好几个天。中间很多次想放弃，但回头看，每一次踩坑都让我对 Linux 和 Web 运维的理解更深了一点。

搭建并维护一个真实的博客，是比看一百遍教程更有效的学习方式。

---

*最后，文章里提到的技术点如果有不清楚的地方或者认为有错误，欢迎在评论区留言讨论。*