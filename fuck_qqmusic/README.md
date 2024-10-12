# 关于此 QQMusic 解析程序

> 程序使用 QQMusic 的未加密接口，按照现在的趋势，此类接口可能很快会被取消，故开发者不对程序长久可用性做保证。

### 音质

Q：这个程序可以解析到什么格式的音乐？

A：程序仅对 MP3 格式进行解析。根据对接口的测试，flac 格式的音乐已经在服务器上完成加密。进行解密会损害 QQMusic 及其背后运营公司的权益，触犯法律。

Q：解析到的音乐音质如何呢？

A：通过此程序可以解析到比特率为 128kbps 和 320kbps 的音频。此外，程序优先获取 320kbps 的音频。

### 使用

Q：`disstid` 是什么？如何获取？

A：这是 QQMusic 中歌单的标识。`disstid` 通常包含在歌单链接当中。在链接 `https://y.qq.com/n/ryqq/playlist/xxxxxxxx` 中，`disstid` 为 `xxxxxxxx`。

Q：`Cookie` 是什么？又该如何获取？

A：`Cookie` 是服务器在用户设备上存储的小文本文件，用于记录用户行为和状态信息。以 Chrome 为例，在 QQMusic 的官方网页上按下 `F12` 启动 DevTools，在底部 Console 选项卡中输入：`javascript:alert(document.cookie)`，Cookie 便会以弹窗形式出现。

## 关于程序本身

程序分为两个版本：[Python](https://github.com/yzyf1312/small-things/tree/main/Fuck_some_music/fuck_qqmusic) 和 Dart。

### 两版本关系

Python 版本最先完成，Dart 版本基于 Python 版本重构。Dart 版本的程序更为健壮，更推荐使用，并且其代码更符合 Dart 规范，便于学习。（这种垃圾代码实际上没有学习的必要，其实还是便于改 Bug）

### 基于此项目进行开发

1. 将此项目保存至本地

2. 在 `pubspec.yaml` 所在路径下运行指令以获取依赖

   ```
   dart pub get
   ```