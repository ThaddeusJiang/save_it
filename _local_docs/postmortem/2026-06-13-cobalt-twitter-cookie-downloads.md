# Cobalt Twitter Cookie Downloads

## What happened

用户发送 X/Twitter 视频 URL 后，bot 没有成功保存。应用日志中出现 Cobalt HTTP 400，随后因为链接下载失败且没有可用 thumbnail fallback，保存流程中断。

## Root cause

本地 Docker Compose 里的 Cobalt 服务仍在使用 v10 image，并且没有提供已登录的 Twitter cookies。一些 X/Twitter 帖子需要登录、敏感内容或年龄门槛访问，因此匿名 Cobalt 请求会在拿到可下载媒体 URL 或 fallback thumbnail 之前失败。

最初的 Compose 配置还把本地 cookie 文件路径藏在环境变量 fallback 表达式里，并且可能回退到 example 文件，导致实际运行配置不够直观、难 review。

## Fix applied

本地和 Zeabur 的 Cobalt 服务都升级到 v11。本地 Docker Compose 现在固定把 root 下 gitignored 的 `cobalt-cookies.json` 挂载到 `/cookies.json`，并设置 `COOKIE_PATH=/cookies.json`。示例文件保留为 `cobalt-cookies.example.json`，只作为模板，不再作为运行时默认文件。

README 已记录本地 cookie 文件格式和路径，`.gitignore` 也会避免真实 cookie 文件进入 git。

## What we learned

对第三方下载服务来说，image 版本和认证状态都是保存链路的一部分。Compose 里的本地 secret bind mount 应该显式、可 review，尤其是当服务失败表面上只是一个泛化的 upstream 400 时。
