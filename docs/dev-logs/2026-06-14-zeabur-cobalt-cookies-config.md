# Zeabur Cobalt cookies 配置文件挂载

## 背景

`save_it` 的 Zeabur template 需要让 self-hosted Cobalt 读取 Twitter/X cookies，以支持下载需要登录、敏感内容或验证访问的 X 资源。

Cobalt 官方 Docker 示例使用 `COOKIE_PATH=/cookies.json`，并把宿主机的 `cookies.json` 挂载到容器内 `/cookies.json`。但 Zeabur template 的 `volumes` 语义和 Docker Compose 的 file bind mount 不一样。

## 结论

不要在 Zeabur template 里用 `volumes.dir: /cookies.json` 挂载单个文件。

Zeabur Volume 挂载的是目录。如果把 Volume 的 mount directory 写成 `/cookies.json`，Zeabur 会创建并挂载一个名为 `cookies.json` 的目录，Cobalt 无法把它当作 cookies 文件读取。

单个配置文件应该使用 Zeabur Config Editor / template `configs`：

```yaml
env:
  COOKIE_PATH:
    default: /cookies.json
    expose: false

configs:
  - path: /cookies.json
    template: |
      {
        "twitter": []
      }
    permission: 256
```

## 持久化行为

普通容器文件系统里的手动文件不可靠，service restart / redeploy 后可能恢复到镜像初始状态。

Zeabur 对这类文件的解决方式是 Config Editor：

- `volumes` 用于持久化目录，例如 `/data`。
- `configs` 用于持久化并挂载单个配置文件，例如 `/cookies.json`。
- 服务启动时，Zeabur 会把 Config Editor 管理的文件挂载到指定路径。

因此，`/cookies.json` 不需要 Volume；只要它由 `configs` 管理，就会在服务启动时重新挂载。

## 用户操作

在 Zeabur 中配置 Cobalt cookies：

1. 打开 `cobalt-api` service。
2. 进入 `Settings > Configs`。
3. 编辑 `/cookies.json`。
4. 填入实际 cookies，例如：

```json
{
  "twitter": [
    "auth_token=<token>; ct0=<csrf>"
  ]
}
```

5. 保存并重启 `cobalt-api` service。

## 参考

- Zeabur Volumes: https://zeabur.com/docs/en-US/data-management/volumes
- Zeabur Config Editor: https://zeabur.com/docs/en-US/operations/data/config-file-management
- Zeabur Template configs: https://zeabur.com/docs/en-US/template/template-format
- Cobalt `COOKIE_PATH`: https://github.com/imputnet/cobalt/blob/main/docs/api-env-variables.md
