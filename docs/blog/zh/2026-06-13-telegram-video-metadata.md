# 一次 Telegram 视频比例错误背后的媒体元数据课

2026-06-13

有些 bug 的价值不在于改了多少代码，而在于它迫使我们把一个平时“差不多能用”的抽象重新看清楚。

这次的问题看起来很具体：通过 save_it 下载并用 bot 发到 Telegram 的视频，有时候横纵比不正确；但同一个原始文件，手动下载以后再手动上传到 Telegram，比例又是对的。另一个相邻现象是，大一点的视频似乎也不太会自动加载，体验不像 Telegram 客户端里正常发送的视频。

第一反应很自然：这是 Telegram Bot API 或 ex_gram 的限制吗？

答案是：一部分是限制，一部分不是。

## 现象为什么迷惑

如果原始文件是正确的，手动上传也是正确的，那么“文件坏了”基本可以排除。剩下的怀疑对象通常有三个：

- Telegram Bot API 对视频做了不同处理。
- ex_gram 上传时丢了什么参数。
- 我们下载到的 MP4 虽然能播放，但容器元数据不够适合 bot 上传。

真正容易误判的是第二点。ex_gram 只是把我们传给它的参数发给 Telegram；如果我们只传了视频文件和 `supports_streaming: true`，它不会凭空知道视频的展示宽高、旋转信息、时长，或者帮我们重排 MP4 容器结构。

也就是说，问题不在“ex_gram 把正确的信息发错了”，而在“我们根本没有把 Telegram 需要的展示信息显式交出去”。

## `supports_streaming` 不是魔法开关

Telegram Bot API 的 `sendVideo` 支持 `duration`、`width`、`height` 和 `supports_streaming`。官方文档也明确说，普通 Bot API 上传视频目前有 50 MB 限制；如果使用 Local Bot API Server，上传上限可以到 2000 MB。

这解释了两个现象：

- 对于大视频，普通 Bot API 的 50 MB 限制是真限制，不是代码里一个参数就能绕过去。
- `supports_streaming: true` 只是告诉 Telegram“这个上传的视频适合流式播放”，它不等于“Telegram 一定会自动加载并按预期处理所有 MP4”。

MP4 是否适合流式播放，还和文件内部的 `moov` atom 位置有关。很多网页下载下来的 MP4 可以正常播放，但 `moov` 信息可能在文件末尾。浏览器或本地播放器可以容忍这个结构；但如果我们希望客户端更快拿到索引信息，就应该让 MP4 变成 faststart 形式。

## 比例错误的关键：展示尺寸不是编码尺寸

视频文件里有一个很容易被忽略的细节：编码宽高和展示宽高不一定相同。

常见例子是手机竖屏视频。它可能以横向尺寸编码，同时在 metadata 里写了 rotation。播放器读取 rotation 后会按竖屏展示，所以你看起来觉得“原始文件比例正确”。但如果某个上传链路没有把这个展示意图传递好，接收端就可能按原始编码宽高推断，结果视频被横着展示或比例异常。

手动上传时，Telegram 客户端很可能会做一次本地分析或处理，把视频变成 Telegram 更容易理解的形式。而 bot 上传没有这层客户端帮忙，服务端只能根据我们提供的文件和参数做判断。

这就是这次修复的核心：不要让 Telegram 猜。我们自己读出视频的展示尺寸，再明确传给 `sendVideo`。

## 修复策略

最终修复分成两步。

第一步，上传前尝试无转码重封装：

```sh
ffmpeg -c copy -movflags +faststart
```

这里没有重新编码视频，只是尽量把 MP4 容器整理成更适合流式播放的结构。这样做成本低，也避免引入转码带来的画质、耗时和 CPU 问题。

第二步，用 `ffprobe` 读取视频元数据：

- `width`
- `height`
- `duration`
- `rotation`

如果 rotation 是 90 或 270 度，就交换宽高，把编码尺寸转换成展示尺寸。然后调用 Telegram `sendVideo` 时传入：

```elixir
[
  supports_streaming: true,
  width: display_width,
  height: display_height,
  duration: duration
]
```

这里还有一个重要取舍：metadata 处理失败不能影响用户拿到视频。

所以实现里做了降级：

- `ffmpeg` 成功，`ffprobe` 失败：仍然发送 faststart 后的视频，只是不带尺寸元数据。
- `ffmpeg` 失败：回退原文件发送，并再尝试直接探测原文件元数据。
- `ffmpeg` 和 `ffprobe` 都失败：按原逻辑发送原文件。

这个策略比“失败就报错”更适合 bot。用户发链接是为了保存和转发媒体，不是为了调试我们的媒体处理链路。

## 为什么这次 issue 很有价值

它提醒我们：Bot API 不是 Telegram 客户端。

客户端上传视频时，用户看不到背后的预处理；bot 上传时，很多事情都要我们显式处理。尤其是媒体文件，能播放不代表适合上传，适合上传不代表接收端一定能推断出正确展示方式。

这次也让 save_it 的视频发送链路从“把文件丢给 Telegram”变成了更可靠的媒体处理流程：

1. 下载视频。
2. 尝试整理 MP4 结构，让它更适合流式播放。
3. 读取展示尺寸和时长。
4. 把展示信息显式传给 Telegram。
5. 所有处理失败都可降级，不阻断发送。

这个变化不大，但边界更清楚了：API 限制归 API 限制，metadata 问题归 metadata 问题，用户体验问题尽量在上传前解决。

## 可以复用的经验

如果你也在用 Telegram Bot API 发送视频，可以记住这几条：

- 普通 Bot API 的视频上传限制要按 50 MB 设计；超过这个边界，考虑 Local Bot API Server、外部存储或发送链接。
- `supports_streaming` 值得传，但它不是自动播放保证。
- MP4 上传前尽量做 faststart。
- 对带旋转 metadata 的视频，不要只相信编码宽高，要计算展示宽高。
- 能从文件里读出的关键媒体信息，尽量显式传给 API。
- 媒体预处理失败时，优先降级，而不是让用户请求失败。

这个 bug 的修复最终不是某个神秘参数，而是把“文件可以播放”和“文件适合被 bot 上传并正确展示”这两件事拆开处理。

很多有价值的工程问题都是这样：表面是一个小异常，底下是一层被我们默认忽略的系统边界。

## References

- [Telegram Bot API: sendVideo](https://core.telegram.org/bots/api#sendvideo)
- [Telegram Bot API: Using a Local Bot API Server](https://core.telegram.org/bots/api#using-a-local-bot-api-server)
