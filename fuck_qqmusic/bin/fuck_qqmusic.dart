import 'dart:async';
import 'dart:io' as io;
import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart' as dio;

// 获取程序所在目录
final String scriptDirectory = path.dirname(path.fromUri(io.Platform.script));
// 获取当前工作目录
final String currentDirectory = io.Directory.current.path;

void main(List<String> arguments) async {
  String? disstidData;
  if (arguments.length > 1) {
    print("请不要输入过多参数");
  } else if (arguments.length == 1) {
    int? disstidFromArguments = int.tryParse(arguments[0]);

    if (disstidFromArguments == null) {
      switch (arguments[0]) {
        case '-h':
          print("你可以将目标歌单的 disstid 作为参数传入程序");
          return;
        default:
          print("Undefine argument! Try -h to get help.");
          return;
      }
    } else {
      disstidData = disstidFromArguments.toString();
    }
  }

  try {
    String? cookieString = await getCookieFromTXT();

    disstidData ??= input("输入目标歌单的 disstid:");
    if (disstidData == null || int.tryParse(disstidData) == null) {
      print("请提供正确的 disstid");
    }

    index(disstidData, cookieString);
  } catch (error) {
    switch (error.runtimeType) {
      case RangeError _:
        print("请将正确的数据保存于 cookie.txt 中");
        return;
      default:
        print(
            "Undefine error: $error\nIt's type is ${error.runtimeType}\nStackTrace: ${StackTrace.current}");
        return;
    }
  }
}

Future<String?> getCookieFromTXT() async {
  String cookieFilePath = path.join(currentDirectory, "cookie.txt");
  String cookieFileWithScriptPath = path.join(scriptDirectory, "cookie.txt");
  io.File cookieFile = io.File(cookieFilePath);

  if (!(await cookieFile.exists())) {
    cookieFile = io.File(cookieFileWithScriptPath);
    if (!(await cookieFile.exists())) {
      print("请将 Cookie 字符串保存于与程序同目录下或运行目录下的 cookie.txt 中\n"
          "程序同目录下的 cookie.txt 应为 $cookieFileWithScriptPath");
      await cookieFile.create();
      return null;
    }
  }
  try {
    return (await cookieFile.readAsLines())[0];
  } catch (error) {
    switch (error) {
      case RangeError _:
        print("请将正确的数据保存于 cookie.txt 中");
        return null;
      default:
        print("Undefine error: $error\n"
            "It's type is ${error.runtimeType}\n"
            "StackTrace: ${StackTrace.current}");
        return null;
    }
  }
}

String? input(String? str) {
  io.stdout.write(str);
  return io.stdin.readLineSync();
}

String cleartext(String originalString) {
  RegExp specialCharsWithSpaces = RegExp(r'\s*[\\\/\:\*\?"<>|\-]\s*');

  String replacedString =
      originalString.replaceAll(specialCharsWithSpaces, '_');
  return replacedString;
}

Future<void> index(String? disstidData, String? cookieString) async {
  if (cookieString == null || disstidData == null) {
    print("Cookie 和 disstid 缺一不可!");
    return;
  }

  // 定义常量
  // 循环间时间间隔的范围(防止可能存在的风控)
  double minWait = 0.3;
  double maxWait = 0.8;

  String? fcgDataStr = await getCdinfoFcg(disstidData);
  if (fcgDataStr == null) {
    print("获取歌单信息失败");
    return;
  }
  Map<String, dynamic> fcgData = jsonDecode(fcgDataStr) as Map<String, dynamic>;
  // 确保 cdlist 是 List<Map<String, dynamic>> 类型
  List<Map<String, dynamic>> cdlist =
      List<Map<String, dynamic>>.from(fcgData["cdlist"] as List);

  int skipTimes = 0;
  for (Map<String, dynamic> cdlistItem in cdlist) {
    List<Map<String, dynamic>> songlistData =
        List<Map<String, dynamic>>.from((cdlistItem["songlist"]) as List);
    String dissnameData = cleartext(cdlistItem["dissname"] as String);

    for (Map<String, dynamic> songData in songlistData) {
      // 安全地获取每个歌曲的信息，如果不存在则使用默认值
      String songSongname =
          (songData["songname"] ?? "Default Song Name") as String;
      String songAlbumname =
          (songData["albumname"] ?? "Default Song Albumname") as String;
      String songAlbummid = (songData["albummid"]) as String;
      String songSongmid =
          (songData["songmid"] ?? "Default Song MID") as String;

      // 获取歌手
      // 下面一行用于初始化，变量 is_first_singer 用于判断是否为第一个歌手
      bool isFirstSinger = true;
      String singerNameString = "";
      String singerNameData = "";
      for (Map<String, dynamic> singerData
          in List<Map<String, dynamic>>.from(songData["singer"] as List)) {
        String singerNameTemp = cleartext(singerData["name"] as String);
        if (isFirstSinger) {
          isFirstSinger = false;
          singerNameString = singerNameTemp;
          singerNameData = singerNameTemp;
        } else {
          singerNameString = "$singerNameString、$singerNameTemp";
          singerNameData = "$singerNameData;$singerNameTemp";
        }
      }
      String localFilename =
          "${cleartext(songSongname)} - $singerNameString.mp3";

      // 使用os.path.join来构建正确的文件路径
      String localFile =
          path.join(currentDirectory, dissnameData, localFilename);

      // 伪断点续传
      if (await io.File(localFile).exists()) {
        continue;
      }

      double waitTime = randomDouble(minWait, maxWait);
      io.sleep(Duration(milliseconds: (waitTime * 1000).toInt()));

      print("$songSongname : $songSongmid");

      int songSize320 = songData["size320"] as int;
      int songSize128 = songData["size128"] as int;

      String filenamePrefix;

      if (songSize320 != 0) {
        filenamePrefix = "M800";
      } else if (songSize128 != 0) {
        filenamePrefix = "M500";
      } else {
        print("$songSongname :找不到可用的音质");
        continue;
      }

      String purlData =
          await getPurlFromMusicuFcg(filenamePrefix, songSongmid, cookieString);

      if (purlData == "None") {
        skipTimes += 1;
        continue;
      }

      if (purlData == "" && songSize320 != 0 && songSize128 != 0) {
        print("链接获取失败");
        print("降低音质重试");
        filenamePrefix = "M500";
        purlData = await getPurlFromMusicuFcg(
            filenamePrefix, songSongmid, cookieString);
      }

      if (purlData == "") {
        print("链接获取失败");
      } else {
        String songUrlData = "http://ws.stream.qqmusic.qq.com/$purlData";
        String albumPicFilename =
            "${cleartext(songSongname)} - $singerNameString.jpg";
        String lyricFilename =
            "${cleartext(songSongname)} - $singerNameString.lrc";
        String albumPicUrlData =
            "https://y.gtimg.cn/music/photo_new/T002R800x800M000$songAlbummid.jpg";
        String albumPicFile =
            path.join(currentDirectory, dissnameData, albumPicFilename);
        String lyricFile =
            path.join(currentDirectory, dissnameData, lyricFilename);

        // 确保目录存在
        io.Directory dissdir = io.Directory(path.dirname(localFile));
        if (!await dissdir.exists()) {
          dissdir.create();
        }

        if ((await downloadFile(
                songUrlData, "$localFile.temp", "$localFilename.temp")) ==
            -1) {
          skipTimes++;
          continue;
        }
        await downloadFile(albumPicUrlData, albumPicFile, albumPicFilename);
        await updateSongTagsByFfmpeg(localFile, albumPicFile, songSongname,
            singerNameData, songAlbumname);
        await lyricDownload(songSongmid, lyricFile);
      }
    }
  }
  if (skipTimes != 0) {
    print("本次跳过了 $skipTimes 首歌曲");
  }
  return;
}

Future<String> getPurlFromMusicuFcg(
    String filenamePrefix, String songSongmid, String cookieString) async {
  // 获取 musicu.fcg

  // 构造请求使用到的文件名
  String filename = "$filenamePrefix$songSongmid$songSongmid.mp3";

  // 发送POST请求

  String? responseText =
      await postMusicuFcg(filename, songSongmid, cookieString);

  if (responseText == null) {
    return "None";
  }

  Map<String, dynamic> responseData =
      jsonDecode(responseText) as Map<String, dynamic>;
  String purlData =
      responseData["req_1"]["data"]["midurlinfo"][0]["purl"] as String;

  return purlData;
}

Future<String?> postMusicuFcg(
    String filename, String songmid, String cookieString) async {
  // 构建请求的载荷
  Map<String, dynamic> payload = {
    "req_1": {
      "module": "vkey.GetVkeyServer",
      "method": "CgiGetVkey",
      "param": {
        "filename": [filename],
        "guid": "10000",
        "songmid": [songmid],
        "songtype": [0],
        "uin": "0",
        "loginflag": 1,
        "platform": "20"
      }
    },
    "loginUin": "0",
    "comm": {"uin": "0", "format": "json", "ct": 24, "cv": 0}
  };
  Map<String, String> headerData = {
    'Content-Type': 'application/json',
    'Cookie': cookieString,
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36' // 根据需要设置User-Agent
  };
  // 要将payload转换为JSON格式的字符串，因为发送application/json格式

  int retryTimes = 0;
  while (retryTimes < 4) {
    try {
      Uri musicuFcgUrl = Uri.https('u.y.qq.com', 'cgi-bin/musicu.fcg');
      http.Response fcgResponse = await http
          .post(musicuFcgUrl, headers: headerData, body: jsonEncode(payload))
          .timeout(Duration(seconds: 10));
      if (fcgResponse.statusCode != 200) {
        print("Undefine statusCode: ${fcgResponse.statusCode}");
        return null;
      }
      return utf8.decode(fcgResponse.bodyBytes);
    } catch (error) {
      switch (error.runtimeType) {
        case TimeoutException _:
          retryTimes++;
          if (retryTimes >= 4) {
            print("请求超时 $retryTimes 次，跳过此歌曲");
            return null;
          } else {
            print("请求超时，进行第 $retryTimes 次重试");
          }
          break;
        default:
          print(
              "Undefine error: $error\nIt's type is ${error.runtimeType}\nStackTrace: ${StackTrace.current}");
          return null;
      }
    }
  }
  return null;
}

double randomDouble(double min, double max) {
  return min + Random().nextDouble() * (max - min);
}

Future<String?> getCdinfoFcg(String disstidData) async {
  // 配置载荷
  Uri targetUrl = Uri.https(
      "i.y.qq.com", "qzone-music/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg", {
    "type": "1",
    "json": "1",
    "utf8": "1",
    "onlysong": "0",
    "nosign": "1",
    "disstid": disstidData,
    "g_tk": "5381",
    "loginUin": "0",
    "hostUin": "0",
    "format": "json",
    "inCharset": "GB2312",
    "outCharset": "utf-8",
    "notice": "0",
    "platform": "yqq",
    "needNewCode": "0"
  });

  // 构造请求头
  // // Rederer 非常重要!
  Map<String, String> headerData = {
    'Referer': 'https://y.qq.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
  };

  int retryTimes = 0;
  while (retryTimes < 4) {
    try {
      http.Response r = await http.get(targetUrl, headers: headerData);
      return r.body;
    } catch (error) {
      switch (error.runtimeType) {
        case TimeoutException _:
          retryTimes++;
          if (retryTimes >= 4) {
            print("请求超时 $retryTimes 次，不再重试");
            return null;
          } else {
            print("请求超时，进行第 $retryTimes 次重试");
          }
          break;
        default:
          print("Undefine error:$error\nIt's type is ${error.runtimeType}");
          return null;
      }
    }
  }
  return null;
}

Future<int> downloadFile(String url, String savePath, String fileName) async {
  // 0 means succeed, -1 means skip

  int retryTimes = 0;
  if (!isFilePath(savePath)) {
    savePath = path.join(savePath, fileName);
  }
  while (retryTimes < 4) {
    try {
      await dio.Dio().download(url, savePath).timeout(Duration(seconds: 8));
      print("文件 $fileName 下载成功");
      return 0;
    } catch (error) {
      switch (error.runtimeType) {
        case TimeoutException _:
          retryTimes++;
          print("下载超时，进行第 $retryTimes 次重试");
          break;
        case dio.DioException _:
          print("下载文件时服务器响应错误，跳过文件 $fileName");
          return -1;
        default:
          print(
              "Undefine error: $error\nIt's type is ${error.runtimeType}\nStackTrace: ${StackTrace.current}");
          return -1;
      }
    }
  }
  print("超时 $retryTimes 次，取消下载");
  return -1;
}

bool isFilePath(String pathStr) {
  return path.extension(pathStr) != "";
}

Future<void> updateSongTagsByFfmpeg(String songFilePath, String albumPic,
    String songName, String singerName, String albumName) async {
  String tempFilePath = "$songFilePath.temp";

  io.File albumPicFile = io.File(albumPic);
  if (!(await albumPicFile.exists())) {
    print("使用默认歌曲封面");
    String defaultCoverFilePath =
        path.join(scriptDirectory, "default_cover.jpg");
    io.File defaultCoverFile = io.File(defaultCoverFilePath);
    if (!(await defaultCoverFile.exists())) {
      print(
          "默认歌曲封面不存在\n请将一个 jpg 文件存储为程序目录下的 default_cover.jpg\ndefault_cover.jpg 的路径应为 $defaultCoverFile");
      io.exit(0);
    }
    albumPic = defaultCoverFilePath;
  }

  List<String> command = [
    path.join(scriptDirectory, 'ffmpeg.exe'),
    '-y',
    '-i',
    tempFilePath,
    '-i',
    albumPic,
    '-map',
    '0:a',
    '-map',
    '1',
    '-c',
    'copy',
    '-metadata',
    'title=$songName',
    '-metadata',
    'artist=$singerName',
    '-metadata',
    'album=$albumName',
    '-disposition:v',
    'attached_pic',
    songFilePath,
  ];

  int resultCode = await cliWithoutTimeout(command);
  switch (resultCode) {
    case 0:
      print("歌曲 $songName 标签元数据更新成功");
      try {
        await io.File(tempFilePath).delete();
      } catch (error) {
        print(
            "Undefine error: $error\nIt's type is ${error.runtimeType}\nStackTrace: ${StackTrace.current}");
      }
      break;
    case 1:
    case 2:
      print("歌曲 $songName 标签元数据更新失败");
      break;
    default:
      print("Undefine result code: $resultCode");
  }
}

Future<int> cliWithoutTimeout(List<String> command) async {
  //return code: 0 means succeed, 1 means timeout, 2 means error

  int retryTimes = 0;
  while (retryTimes < 4) {
    try {
      // 启动进程
      io.Process process =
          await io.Process.start(command[0], command.skip(1).toList());

      // 忽略标准输出和标准错误
      process.stdout.listen((data) {}).cancel();
      process.stderr.listen((data) {}).cancel();

      int processExitCode = await process.exitCode;

      if (processExitCode == 0) {
        return 0;
      } else {
        print("Undefine exitCode: $processExitCode");
        return 2;
      }
    } catch (error) {
      switch (error.runtimeType) {
        case TimeoutException _:
          retryTimes++;
          if (retryTimes >= 4) {
            print("子进程超时 $retryTimes 次，跳过此歌曲");
            return 1;
          } else {
            print("子进程超时，进行第 $retryTimes 次重试");
          }
          break;
        default:
          print(
              "Undefine error: $error\nIt's type is ${error.runtimeType}\nStackTrace: ${StackTrace.current}");
          return 2;
      }
    }
  }
  return 2;
}

Future<void> lyricDownload(String songSongmid, String lyricFile) async {
  // 构造链接
  Uri targetUrl =
      Uri.https("i.y.qq.com", "lyric/fcgi-bin/fcg_query_lyric_new.fcg", {
    "songmid": songSongmid,
    "g_tk": "5381",
    "format": "json",
    "inCharset": "utf8",
    "outCharset": "utf-8",
    "nobase64": "1"
  });

  // 构造请求头
  // Referer 非常重要!
  Map<String, String> headerData = {
    'Referer': 'https://y.qq.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
  };

  int retryTimes = 0;
  while (retryTimes < 8) {
    try {
      http.Response fcg = await http
          .get(targetUrl, headers: headerData)
          .timeout(Duration(seconds: 2));

      Map<String, dynamic> fcgData =
          jsonDecode(utf8.decode(fcg.bodyBytes)) as Map<String, dynamic>;

      io.File lyric = io.File(lyricFile);
      if (!fcgData.containsKey('lyric')) {
        await lyric.writeAsString("[00:00:00]此歌曲暂无歌词");
        print("无法找到歌词数据，写入空数据");
        return;
      }
      await lyric.writeAsString(fcgData["lyric"] as String);
      print("歌词写入完成");
      return;
    } catch (error) {
      switch (error.runtimeType) {
        case TimeoutException _:
          retryTimes++;
          if (retryTimes >= 4) {
            print("请求超时 $retryTimes 次，跳过此歌词");
            return;
          } else {
            print("请求超时，进行第 $retryTimes 次重试");
          }
          break;
        default:
          print(
              "Undefine error: $error\nIt's type is ${error.runtimeType}\nStackTrace: ${StackTrace.current}");
          return;
      }
    }
  }
}
