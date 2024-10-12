# 关于此 NeteaseMusic 解析程序

> 此程序使用的接口来自 NeteaseCloudMusicApi 项目，由衷感谢 Binaryify 为开源事业的付出！

### 音质

Q：此程序可以解析到什么格式的音频？

A：程序可以解析到 MP3 与 FLAC 格式的音频。程序并不对服务器接口进行破解，所以使用者只能获取到其被 NeteaseMusic 许可收听的歌曲。

Q：解析到的音乐音质如何呢？

A：在特定条件下，程序解析得到的音频音质按照 NeteaseMusic 官方标准可以分为四档，分别是：低、中、高、无损，而程序会解析其所能得到的最高音质。

### 使用

Q：`listid` 是什么？如何获取？

A：这是 NeteaseMusic 中歌单的标识。`listid` 通常包含在歌单链接当中。在链接 `https://music.163.com/#/playlist?id=xxxxxxxxxx` 中，`listid` 为 `xxxxxxxxxx`。

Q：`Cookie` 是什么？又该如何获取？

A：`Cookie` 是服务器在用户设备上存储的小文本文件，用于记录用户行为和状态信息。以 Chrome 为例，在 QQMusic 的官方网页上按下 `F12` 启动 DevTools，在底部 Console 选项卡中输入：`javascript:alert(document.cookie)`，Cookie 便会以弹窗形式出现。

## 关于程序本身

### 基于此项目进行开发

1. 将此项目保存至本地

2. 在 `pubspec.yaml` 所在路径下运行指令以获取依赖

   ```
   dart pub get
   ```