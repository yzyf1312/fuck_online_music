import 'dart:async' as async;
import 'dart:io' as io;
import 'dart:convert' as convert;
import 'dart:math' as math;
import 'dart:typed_data' as typed_data;

import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart' as dio;
import 'package:pointycastle/export.dart' as pointycastle;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart' as crypto;

// 获取程序所在目录
final String scriptDirectory = path.dirname(path.fromUri(io.Platform.script));
// 获取当前工作目录
final String currentDirectory = io.Directory.current.path;

void main(List<String> arguments) async {
  String? listId;
  if (arguments.length > 1) {
    print("请不要输入过多参数");
  } else if (arguments.length == 1) {
    final int? disstidFromArguments = int.tryParse(arguments[0]);

    if (disstidFromArguments == null) {
      switch (arguments[0]) {
        case '-h':
          print("你可以将目标歌单的 listid 作为参数传入程序");
          return;
        default:
          print("Undefine argument! Try -h to get help.");
          return;
      }
    } else {
      listId = disstidFromArguments.toString();
    }
  }

  final String? cookieString = await getCookieFromTXT();
  if (listId == null) {
    neteaseWithAccount(cookieString ?? "");
  } else {
    neteaseIndex(listId, cookieString);
  }
}

Future<void> neteaseIndex(
    final String? listId, final String? cookieString) async {
  if (cookieString == null || listId == null) {
    print("Cookie 和 listid 缺一不可!");
    return;
  }

  // 定义常量
  // 循环间时间间隔的范围(防止可能存在的风控)
  const double minWait = 0.3;
  const double maxWait = 0.8;

  final Map<String, dynamic>? playlistDetail =
      await postPlaylistDetail(cookieString, listId);
  if (playlistDetail == null || playlistDetail["playlist"] == null) {
    print("请提供正确的 listid!");
    return;
  }

  final String playlistName =
      cleartext(playlistDetail["playlist"]["name"] as String);

  print("开始下载歌单: $playlistName");

  // 确保目录存在
  io.Directory dissdir =
      io.Directory(path.join(currentDirectory, playlistName));
  if (!await dissdir.exists()) {
    await dissdir.create();
  }

  io.File dataFile =
      io.File(path.join(currentDirectory, playlistName, "data.json"));
  if (!(await dataFile.exists())) {
    await dataFile.create();
    await dataFile.writeAsString('{"netease":{}}');
  }
  String dataStr = await dataFile.readAsString();
  if (dataStr.isEmpty) {
    await dataFile.writeAsString('{"netease":{}}');
    dataStr = '{"netease":{}}';
  }
  Map<String, dynamic> data =
      convert.jsonDecode(dataStr) as Map<String, dynamic>;

  if (data["netease"] is! Map || data["netease"].containsKey(listId) != true) {
    List<int> nullIntList = [];
    data["netease"] = {
      listId: {"success": nullIntList}
    };
  }

  int skipTimes = 0;
  for (final Map<String, dynamic> songData in List<Map<String, dynamic>>.from(
      playlistDetail["playlist"]["tracks"] as List)) {
    // 伪断点续传
    if (data["netease"][listId]["success"].contains(songData["id"]) == true) {
      continue;
    }

    final String songName = songData["name"] as String;

    // 获取歌手
    // 下面一行用于初始化，变量 is_first_singer 用于判断是否为第一个歌手
    bool isFirstSinger = true;
    String singerNameString = "";
    String singerNameData = "";
    for (final Map<String, dynamic> singerData
        in List<Map<String, dynamic>>.from(songData["ar"] as List)) {
      final String singerNameTemp = cleartext(singerData["name"] as String);
      if (isFirstSinger) {
        isFirstSinger = false;
        singerNameString = singerNameTemp;
        singerNameData = singerNameTemp;
      } else {
        singerNameString = "$singerNameString、$singerNameTemp";
        singerNameData = "$singerNameData;$singerNameTemp";
      }
    }

    print("$songName: ${songData["id"]}");

    String songUrl = await postSongUrl(cookieString, songData["id"] as int);

    if (songUrl == "") {
      print("歌曲链接为空，跳过歌曲");
      skipTimes++;
      continue;
    }

    String localFilename =
        "${cleartext(songName)} - $singerNameString${path.extension(Uri.parse(songUrl).path)}";
    // 使用os.path.join来构建正确的文件路径
    String localFile = path.join(currentDirectory, playlistName, localFilename);

    double waitTime = randomDouble(minWait, maxWait);
    io.sleep(Duration(milliseconds: (waitTime * 1000).toInt()));

    String albumPicFilename = "${cleartext(songName)} - $singerNameString.jpg";
    String lyricFilename = "${cleartext(songName)} - $singerNameString.lrc";
    String albumPicFile =
        path.join(currentDirectory, playlistName, albumPicFilename);
    String lyricFile = path.join(currentDirectory, playlistName, lyricFilename);
    String albumPicUrlData = songData["al"]["picUrl"] as String;
    String albumNameData = songData["al"]["name"] as String;

    if ((await downloadFile(
            songUrl, "$localFile.temp", "$localFilename.temp")) ==
        -1) {
      skipTimes++;
      continue;
    }
    await downloadFile(albumPicUrlData, albumPicFile, albumPicFilename,
        byGet: true);
    await updateSongTagsByFfmpeg(
        localFile, albumPicFile, songName, singerNameData, albumNameData);
    await lyricDownload(songData["id"] as int, lyricFile);

    data["netease"][listId]["success"].add(songData["id"]);
    dataFile.writeAsString(convert.jsonEncode(data));
  }

  print("歌单 $playlistName 已下载完成");
  if (skipTimes != 0) {
    print("本次跳过了 $skipTimes 首歌曲");
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

double randomDouble(double min, double max) {
  return min + math.Random().nextDouble() * (max - min);
}

Future<int> downloadFile(String url, String savePath, String fileName,
    {bool byGet = false}) async {
  // 0 means succeed, -1 means skip

  int retryTimes = 0;
  if (!isFilePath(savePath)) {
    savePath = path.join(savePath, fileName);
  }
  while (retryTimes < 4) {
    try {
      if (byGet) {
        const Map<String, String> headerData = {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36' // 根据需要设置User-Agent
        };
        // 发起GET请求
        final response = await http
            .get(Uri.parse(url), headers: headerData)
            .timeout(Duration(seconds: 16));

        // 检查请求是否成功
        if (response.statusCode == 200) {
          // 将下载的文件写入指定路径
          final file = io.File(savePath);
          await file.writeAsBytes(response.bodyBytes);
          print("文件 $fileName 下载成功");
        } else {
          print('文件 $fileName 下载失败，状态码: ${response.statusCode}');
        }
      } else {
        await dio.Dio().download(url, savePath).timeout(Duration(seconds: 16));
        print("文件 $fileName 下载成功");
      }
      return 0;
    } catch (error) {
      switch (error) {
        case async.TimeoutException _:
          retryTimes++;
          print("下载超时，进行第 $retryTimes 次重试");
          break;
        case dio.DioException _:
          print("下载文件时服务器响应错误，跳过文件 $fileName");
          print(error);
          return -1;
        default:
          print("Undefine error: $error\n"
              "It's type is ${error.runtimeType}\n"
              "StackTrace: ${StackTrace.current}");
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
          "默认歌曲封面不存在\n请将一个 jpg 文件存储为程序目录下的 default_cover.jpg\ndefault_cover.jpg 的路径应为 $defaultCoverFilePath");
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
    '0:0',
    '-map',
    '1:0',
    '-c',
    'copy',
    '-id3v2_version',
    '3',
    '-metadata',
    'title=$songName',
    '-metadata',
    'artist=$singerName',
    '-metadata',
    'album=$albumName',
    songFilePath,
  ];

  int resultCode = await cliWithoutTimeout(command);
  switch (resultCode) {
    case 0:
      print("歌曲 $songName 标签元数据更新成功");
      try {
        await io.File(tempFilePath).delete();
      } catch (error) {
        print("Undefine error: $error\n"
            "It's type is ${error.runtimeType}\n"
            "StackTrace: ${StackTrace.current}");
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
      switch (error) {
        case async.TimeoutException _:
          retryTimes++;
          if (retryTimes >= 4) {
            print("子进程超时 $retryTimes 次，跳过此歌曲");
            return 1;
          } else {
            print("子进程超时，进行第 $retryTimes 次重试");
          }
          break;
        default:
          print("Undefine error: $error\n"
              "It's type is ${error.runtimeType}\n"
              "StackTrace: ${StackTrace.current}");
          return 2;
      }
    }
  }
  return 2;
}

Future<void> lyricDownload(int songId, String lyricFile) async {
  // 构造链接
  Uri targetUrl =
      Uri.https("music.163.com", "weapi/song/lyric", {"csrf_token": null});

  // 构造请求头
  const Map<String, String> headerData = {
    'Referer': 'https://music.163.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
  };

  Map<String, dynamic> d = {
    "id": "$songId",
    "lv": -1,
    "tv": -1,
    "csrf_token": '',
  };

  Map<String, String> data = weapi(d);

  int retryTimes = 0;
  while (retryTimes < 8) {
    try {
      http.Response response = await http
          .post(targetUrl, headers: headerData, body: data)
          .timeout(Duration(seconds: 4));

      Map<String, dynamic> responseData =
          convert.jsonDecode(response.body) as Map<String, dynamic>;
      io.File lyric = io.File(lyricFile);
      if (!responseData.containsKey('lrc')) {
        await lyric.writeAsString("[00:00:00]此歌曲暂无歌词");
        print("无法找到歌词数据，写入空数据");
        return;
      }
      Map<String, dynamic> lrcData =
          responseData["lrc"] as Map<String, dynamic>;
      if (!lrcData.containsKey('lyric')) {
        await lyric.writeAsString("[00:00:00]此歌曲暂无歌词");
        print("无法找到歌词数据，写入空数据");
        return;
      }
      await lyric.writeAsString(lrcData["lyric"] as String);
      print("歌词写入完成");
      return;
    } catch (error) {
      switch (error) {
        case async.TimeoutException _:
          retryTimes++;
          if (retryTimes >= 4) {
            print("请求超时 $retryTimes 次，跳过此歌词");
            return;
          } else {
            print("请求超时，进行第 $retryTimes 次重试");
          }
          break;
        default:
          print("Undefine error: $error\n"
              "It's type is ${error.runtimeType}\n"
              "StackTrace: ${StackTrace.current}");
          return;
      }
    }
  }
}

//
//
//
// 以下函数用于获取歌曲直链
Future<String> postSongUrl(String cookieString, int songId) async {
  Uri targetUrl =
      Uri.https("interface3.music.163.com", "eapi/song/enhance/player/url");

  const String eapiUrl = '/api/song/enhance/player/url';
  Map<String, dynamic> d = {
    "ids": "[$songId]",
    "br": 999000,
  };
  Map<String, String> data = eapi(eapiUrl, d);
  Map<String, String> headerData = {
    'Cookie': cookieString,
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36' // 根据需要设置User-Agent
  };
  http.Response response =
      await http.post(targetUrl, headers: headerData, body: data);

  return (convert.jsonDecode(response.body)["data"][0]["url"] ?? "") as String;
}

Map<String, String> eapi(String url, Map<String, dynamic> object) {
  const String eapiKey = 'e82ckenh8dichen8';
  String text = convert.jsonEncode(object);
  String message = "nobody${url}use${text}md5forencrypt";

  String digest = computeMD5(message);
  String data = '$url-36cd479b6b5-$text-36cd479b6b5-$digest';

  return {
    "params":
        strToHex(aesEncrypt(data, eapiKey, 'AES-ECB').base64).toUpperCase(),
  };
}

String strToHex(String inputStr) {
  StringBuffer hexBuffer = StringBuffer(); // 创建一个 StringBuffer 用于构建十六进制字符串

  typed_data.Uint8List inputData = convert.base64Decode(inputStr);

  for (int i = 0; i < inputData.length; i++) {
    int codeUnit = inputData[i]; // 获取字符的 Unicode 编码值
    if (codeUnit < 16) {
      hexBuffer.write('0'); // 如果编码值小于 16，前面加 '0'
    }
    hexBuffer.write(codeUnit.toRadixString(16)); // 转换为十六进制并追加
  }

  return hexBuffer.toString(); // 返回构建的十六进制字符串
}
// 以上函数用于获取歌曲直链
//
//
//

//
//
//
// 以下函数用于获取歌单信息
Future<Map<String, dynamic>?> postPlaylistDetail(
    String cookieString, String listId) async {
  Uri targetUrl = Uri.https("music.163.com", "weapi/v3/playlist/detail");
  Map<String, dynamic> d = {
    "id": listId,
    "offset": 0,
    "total": true,
    "limit": 1000,
    "n": 1000,
    "csrf_token": '',
  };
  Map<String, String> data = weapi(d);
  Map<String, String> headerData = {
    'Cookie': cookieString,
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36' // 根据需要设置User-Agent
  };

  http.Response response =
      await http.post(targetUrl, headers: headerData, body: data);

  return convert.jsonDecode(response.body) as Map<String, dynamic>;
}

String createSecretKey(int size) {
  const String choice = '012345679abcdef';
  List<String> result = [];
  for (int i = 0; i < size; i++) {
    int index = math.Random().nextInt(choice.length);
    result.add(choice[index]);
  }
  return result.join('');
}

Map<String, String> weapi(Map<String, dynamic> inputMap) {
  const String modulus =
      '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b72'
      '5152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbd'
      'a92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe48'
      '75d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';
  const String nonce = '0CoJUm6Qyw8W8jud';
  const String pubKey = '010001';
  String text = convert.jsonEncode(inputMap);
  String secKey = createSecretKey(16);
  String encText =
      aesEncrypt(aesEncrypt(text, nonce, 'AES-CBC').base64, secKey, 'AES-CBC')
          .base64;
  String encSecKey = rsaEncrypt(secKey, pubKey, modulus);
  return {
    "params": encText,
    "encSecKey": encSecKey,
  };
}

String rsaEncrypt(String text, String pubKeyHex, String modulusHex) {
  // 反转文本
  String reversedText = text.split('').reversed.join();

  // 转换为字节
  List<int> bytes = convert.utf8.encode(reversedText);

  // 将十六进制字符串转换为大整数
  BigInt modulus = BigInt.parse(modulusHex, radix: 16);
  BigInt pubKey = BigInt.parse(pubKeyHex, radix: 16);

  // 创建 RSA 密钥对
  pointycastle.RSAPublicKey rsaKey = pointycastle.RSAPublicKey(modulus, pubKey);

  // 加密
  pointycastle.RSAEngine cipher = pointycastle.RSAEngine();
  cipher.init(
      true, pointycastle.PublicKeyParameter<pointycastle.RSAPublicKey>(rsaKey));

  // 执行加密
  typed_data.Uint8List encrypted =
      cipher.process(typed_data.Uint8List.fromList(bytes));

  // 返回十六进制格式的加密字符串
  return encrypted
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .padLeft(256, '0');
}

encrypt.Encrypted aesEncrypt(String plainText, String keyStr, String algo) {
  encrypt.Key key = encrypt.Key.fromUtf8(keyStr);

  // 生成一个16字节的IV（初始化向量）
  encrypt.IV iv = encrypt.IV.fromUtf8('0102030405060708');

  encrypt.Encrypter encrypter;
  switch (algo.toUpperCase()) {
    case "AES-CBC":
      encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
      break;
    case 'AES-ECB':
      encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.ecb));
      break;
    default:
      encrypter = encrypt.Encrypter(encrypt.AES(key));
  }

  // 加密明文
  encrypt.Encrypted encrypted = encrypter.encrypt(plainText, iv: iv);
  return encrypted;
}

String computeMD5(String inputStr) {
  // 计算MD5哈希并将结果存储为哈希对象
  // 将哈希对象转换为十六进制字符串并返回
  return crypto.md5.convert(convert.utf8.encode(inputStr)).toString();
}
// 以上函数用于获取歌单信息
//
//
//

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

Future<Map<String, dynamic>> getUser(String cookieString) async {
  Uri url = Uri.https("music.163.com", "api/nuser/account/get");
  Map<String, String> encryptReqData = weapi({});

  Map<String, String> headerData = {
    'Cookie': cookieString,
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36' // 根据需要设置User-Agent
  };
  http.Response response =
      await http.post(url, headers: headerData, body: encryptReqData);

  return convert.jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> getUserPlaylist(
    int userId, String cookieString) async {
  Uri targetUrl = Uri.https("music.163.com", "api/user/playlist");
  Map<String, String> reqData = {
    "uid": "$userId",
    "limit": "1000",
    "offset": "0",
    "includeVideo": "true"
  };
  Map<String, String> headerData = {
    'Cookie': cookieString,
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36' // 根据需要设置User-Agent
  };

  http.Response response =
      await http.post(targetUrl, body: reqData, headers: headerData);

  return convert.jsonDecode(response.body) as Map<String, dynamic>;
}

void neteaseWithAccount(String cookieString) async {
  List<({int id, String name})> createPlaylist = [];
  List<({int id, String name})> favouritePlaylist = [];
  List<({int id, String name})> unknowPlaylist = [];

  for (Map<String, dynamic> element in List<Map<String, dynamic>>.from(
      (await getUserPlaylist(
          (await getUser(cookieString))["account"]["id"] as int,
          cookieString))["playlist"] as List)) {
    switch (element["subscribed"]) {
      case true:
        favouritePlaylist.add((name: element["name"], id: element["id"]));
        break;
      case false:
        createPlaylist.add((name: element["name"], id: element["id"]));
        break;
      default:
        unknowPlaylist.add((name: element["name"], id: element["id"]));
    }
  }

  print("我创建的歌单");
  int i = 0;
  for (({int id, String name}) element in createPlaylist) {
    i++;
    print("$i: ${element.name}");
  }
  print("");

  print("我收藏的歌单");
  i = 0;
  for (({int id, String name}) element in favouritePlaylist) {
    i++;
    print("$i: ${element.name}");
  }
  print("");

  bool isFinish = false;
  while (!isFinish) {
    switch (input("你希望获取哪里的歌单?\n"
            "输入 c 为我创建的歌单, F 为我收藏的歌单, id 为另外提供歌单的 listid, ac 为他人账户的歌单\n"
            "不区分大小写(c/F/id/ac)")!
        .toUpperCase()) {
      case "C":
        String? inputStr = input("请输入歌单对应的编号:");
        int inputInt = (int.tryParse(inputStr ?? "1") ?? 1) - 1;
        neteaseIndex(createPlaylist[inputInt].id.toString(), cookieString);
        isFinish = true;
        break;
      case "F":
        String? inputStr = input("请输入歌单对应的编号:");
        int inputInt = (int.tryParse(inputStr ?? "1") ?? 1) - 1;
        neteaseIndex(favouritePlaylist[inputInt].id.toString(), cookieString);
        isFinish = true;
        break;
      case "ID":
        String? listId;
        listId ??= input("输入目标歌单的 listid:");
        await neteaseIndex(listId, cookieString);
        isFinish = true;
        break;
      case "AC":
        List<({int id, String name})> otherCreatePlaylist = [];
        List<({int id, String name})> otherFavouritePlaylist = [];
        List<({int id, String name})> otherUnknowPlaylist = [];

        for (Map<String, dynamic> element in List<Map<String, dynamic>>.from(
            (await getUserPlaylist(
                int.tryParse(input("请输入他人账户的 id:") ?? "1") ?? 1,
                cookieString))["playlist"] as List)) {
          switch (element["subscribed"]) {
            case true:
              otherFavouritePlaylist
                  .add((name: element["name"], id: element["id"]));
              break;
            case false:
              otherCreatePlaylist
                  .add((name: element["name"], id: element["id"]));
              break;
            default:
              otherUnknowPlaylist
                  .add((name: element["name"], id: element["id"]));
          }
        }

        print("此账户创建的歌单");
        int i = 0;
        for (({int id, String name}) element in otherCreatePlaylist) {
          i++;
          print("$i: ${element.name}");
        }
        print("");

        print("此账户收藏的歌单");
        i = 0;
        for (({int id, String name}) element in otherFavouritePlaylist) {
          i++;
          print("$i: ${element.name}");
        }
        print("");

        bool isFinish = false;
        while (!isFinish) {
          switch (input("你希望获取哪里的歌单?\n"
                  "输入 c 为此账户创建的歌单, F 为此账户收藏的歌单\n"
                  "不区分大小写(c/F)")!
              .toUpperCase()) {
            case "C":
              String? inputStr = input("请输入歌单对应的编号:");
              int inputInt = (int.tryParse(inputStr ?? "1") ?? 1) - 1;
              neteaseIndex(
                  otherCreatePlaylist[inputInt].id.toString(), cookieString);
              isFinish = true;
              break;
            case "F":
              String? inputStr = input("请输入歌单对应的编号:");
              int inputInt = (int.tryParse(inputStr ?? "1") ?? 1) - 1;
              neteaseIndex(
                  otherFavouritePlaylist[inputInt].id.toString(), cookieString);
              isFinish = true;
              break;
            default:
              print("请提供正确的输入!");
          }
        }
        break;
      default:
        print("请提供正确的输入!");
    }
  }
}
