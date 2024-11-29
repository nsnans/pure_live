import 'dart:math';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:crypto/crypto.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/model/live_anchor_item.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_search_result.dart';
import 'package:pure_live/core/danmaku/huya_danmaku.dart';
import 'package:pure_live/model/live_category_result.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';

class HuyaSite implements LiveSite {
  @override
  String id = "huya";

  @override
  String name = "虎牙直播";

  @override
  LiveDanmaku getDanmaku() => HuyaDanmaku();

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    List<LiveCategory> categories = [
      LiveCategory(id: "1", name: "网游", children: []),
      LiveCategory(id: "2", name: "单机", children: []),
      LiveCategory(id: "8", name: "娱乐", children: []),
      LiveCategory(id: "3", name: "手游", children: []),
    ];

    for (var item in categories) {
      var items = await getSubCategores(item);
      item.children.addAll(items);
    }
    return categories;
  }

  final String kUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.0.0 Safari/537.36";

  final SettingsService settings = Get.find<SettingsService>();
  Future<List<LiveArea>> getSubCategores(LiveCategory liveCategory) async {
    var result = await HttpClient.instance.getJson(
      "https://live.cdn.huya.com/liveconfig/game/bussLive",
      queryParameters: {
        "bussType": liveCategory.id,
      },
    );

    List<LiveArea> subs = [];
    for (var item in result["data"]) {
      var gid = (item["gid"])?.toInt().toString();
      var subCategory = LiveArea(
          areaId: gid!,
          areaName: item["gameFullName"].toString(),
          areaType: liveCategory.id,
          platform: Sites.huyaSite,
          areaPic: "https://huyaimg.msstatic.com/cdnimage/game/$gid-MS.jpg",
          typeName: liveCategory.name);
      subs.add(subCategory);
    }

    return subs;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveArea category, {int page = 1}) async {
    var resultText = await HttpClient.instance.getJson(
      "https://www.huya.com/cache.php",
      queryParameters: {
        "m": "LiveList",
        "do": "getLiveListByPage",
        "tagAll": 0,
        "gameId": category.areaId,
        "page": page
      },
      header: {
        "user-agent": kUserAgent,
        "Cookie": settings.huyaCookie.value,
      },
    );
    var result = json.decode(resultText);
    var items = <LiveRoom>[];
    for (var item in result["data"]["datas"]) {
      var cover = item["screenshot"].toString();
      if (!cover.contains("?")) {
        cover += "?x-oss-process=style/w338_h190&";
      }
      var title = item["introduction"]?.toString() ?? "";
      if (title.isEmpty) {
        title = item["roomName"]?.toString() ?? "";
      }
      var roomItem = LiveRoom(
        roomId: item["profileRoom"].toString(),
        title: title,
        cover: cover,
        nick: item["nick"].toString(),
        watching: item["totalCount"].toString(),
        avatar: item["avatar180"],
        area: item["gameFullName"].toString(),
        liveStatus: LiveStatus.live,
        status: true,
        platform: Sites.huyaSite,
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["page"] < result["data"]["totalPage"];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) {
    List<LivePlayQuality> qualities = <LivePlayQuality>[];
    var urlData = detail.data as HuyaUrlDataModel;
    if (urlData.bitRates.isEmpty) {
      urlData.bitRates = [
        HuyaBitRateModel(
          name: "原画",
          bitRate: 0,
        ),
        HuyaBitRateModel(name: "高清", bitRate: 2000),
      ];
    }
    for (var item in urlData.bitRates) {
      var urls = <String>[];
      for (var line in urlData.lines) {
        var src = line.line;
        src += "/${line.streamName}.flv";
        var parms = processAnticode(
          line.flvAntiCode,
          line.streamName,
        );
        src += "?$parms";
        if (item.bitRate > 0) {
          src += "&ratio=${item.bitRate}";
        }
        src = src.replaceAll("http://", "https://");
        urls.add(src);
      }
      qualities.add(LivePlayQuality(
        data: urls,
        quality: item.name,
      ));
    }

    return Future.value(qualities);
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    return quality.data as List<String>;
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1, required String nick}) async {
    var resultText = await HttpClient.instance.getJson(
      "https://www.huya.com/cache.php",
      queryParameters: {"m": "LiveList", "do": "getLiveListByPage", "tagAll": 0, "page": page},
      header: {
        "user-agent": kUserAgent,
        "Cookie": settings.huyaCookie.value,
      },
    );
    var result = json.decode(resultText);
    var items = <LiveRoom>[];
    for (var item in result["data"]["datas"]) {
      var cover = item["screenshot"].toString();
      if (!cover.contains("?")) {
        cover += "?x-oss-process=style/w338_h190&";
      }
      var title = item["introduction"]?.toString() ?? "";
      if (title.isEmpty) {
        title = item["roomName"]?.toString() ?? "";
      }
      var roomItem = LiveRoom(
        roomId: item["profileRoom"].toString(),
        title: title,
        cover: cover,
        area: item["gameFullName"].toString(),
        nick: item["nick"].toString(),
        avatar: item["avatar180"],
        watching: item["totalCount"].toString(),
        platform: Sites.huyaSite,
        liveStatus: LiveStatus.live,
        status: true,
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["page"] < result["data"]["totalPage"];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveRoom> getRoomDetail(
      {required String nick, required String platform, required String roomId, required String title}) async {
    var htmlInfo = await HttpClient.instance.getText('https://www.huya.com/$roomId', header: {
      'Accept': '*/*',
      'Origin': 'https://www.huya.com',
      'Referer': 'https://www.huya.com/',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-site',
      "user-agent": kUserAgent,
      "Cookie": settings.huyaCookie.value,
    });
    var result = json.decode(htmlInfo.split('stream: ')[1].split('};')[0].toString());
    if (result['data'] != null && result['data'][0] != null && result['data'][0]['gameStreamInfoList'] != null) {
      var data = result['data'][0]['gameLiveInfo'];
      bool isXingxiu = data['gid'] == 1663;
      String topSid = '0';
      String subSid = '0';
      var huyaLines = <HuyaLineModel>[];
      var huyaBiterates = <HuyaBitRateModel>[];
      //读取可用线路
      var lines = result['vMultiStreamInfo'];
      var baseSteamInfoList = result['data'][0]['gameStreamInfoList'];
      baseSteamInfoList = baseSteamInfoList
          .where(
              (item) => item["iPCPriorityRate"] > 0 && item["iWebPriorityRate"] > 0 && item["iMobilePriorityRate"] > 0)
          .toList();
      lines = lines.where((item) => item["iCompatibleFlag"] == 0).toList();
      for (var item in baseSteamInfoList) {
        topSid = item["lChannelId"].toString();
        subSid = item["lSubChannelId"].toString();
        huyaLines.add(HuyaLineModel(
          line: item['sFlvUrl'],
          lineType: HuyaLineType.flv,
          flvAntiCode: item["sFlvAntiCode"].toString(),
          hlsAntiCode: item["sHlsAntiCode"].toString(),
          streamName: item["sStreamName"].toString(),
        ));
      }
      //清晰度
      for (var item in lines) {
        var name = item["sDisplayName"].toString();
        if (huyaBiterates.map((e) => e.name).toList().every((element) => element != name)) {
          huyaBiterates.add(HuyaBitRateModel(
            bitRate: item["iBitRate"],
            name: name,
          ));
        }
      }
      return LiveRoom(
        cover: data['screenshot'] ?? '',
        watching: data['activityCount']?.toString() ?? '',
        roomId: roomId,
        area: data['gameFullName'] ?? '',
        title: data['introduction'] ?? '',
        nick: data['nick'] ?? '',
        avatar: data['avatar180'] ?? '',
        introduction: data['introduction'] ?? '',
        notice: data['welcomeText'] ?? '',
        status: baseSteamInfoList.length != 0,
        liveStatus: baseSteamInfoList.length != 0 ? LiveStatus.live : LiveStatus.offline,
        platform: Sites.huyaSite,
        data: HuyaUrlDataModel(
          url: "",
          lines: huyaLines,
          bitRates: huyaBiterates,
          uid: "",
          isXingxiu: isXingxiu,
        ),
        danmakuData: HuyaDanmakuArgs(
          ayyuid: int.parse(data["yyid"].toString()),
          topSid: int.parse(topSid.toString()),
          subSid: int.parse(subSid.toString()),
        ),
        link: "https://www.huya.com/$roomId",
      );
    } else {
      LiveRoom liveRoom = settings.getLiveRoomByRoomId(roomId, platform);
      liveRoom.liveStatus = LiveStatus.offline;
      liveRoom.status = false;
      return liveRoom;
    }
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) async {
    var resultText = await HttpClient.instance.getJson(
      "https://search.cdn.huya.com/",
      queryParameters: {
        "m": "Search",
        "do": "getSearchContent",
        "q": keyword,
        "uid": 0,
        "v": 4,
        "typ": -5,
        "livestate": 0,
        "rows": 20,
        "start": (page - 1) * 20,
      },
    );
    var result = json.decode(resultText);
    var items = <LiveRoom>[];
    var queryList = result["response"]["3"]["docs"] ?? [];
    for (var item in queryList) {
      var cover = item["game_screenshot"].toString();
      if (!cover.contains("?")) {
        cover += "?x-oss-process=style/w338_h190&";
      }

      var title = item["game_introduction"]?.toString() ?? "";
      if (title.isEmpty) {
        title = item["game_roomName"]?.toString() ?? "";
      }
      var roomItem = LiveRoom(
        roomId: item["room_id"].toString(),
        title: title,
        cover: cover,
        nick: item["game_nick"].toString(),
        area: item["gameName"].toString(),
        status: true,
        liveStatus: LiveStatus.live,
        avatar: item["game_imgUrl"].toString(),
        watching: item["game_total_count"].toString(),
        platform: Sites.huyaSite,
      );
      items.add(roomItem);
    }
    return LiveSearchRoomResult(hasMore: queryList.length > 0, items: items);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) async {
    var resultText = await HttpClient.instance.getJson(
      "https://search.cdn.huya.com/",
      queryParameters: {
        "m": "Search",
        "do": "getSearchContent",
        "q": keyword,
        "uid": 0,
        "v": 1,
        "typ": -5,
        "livestate": 0,
        "rows": 20,
        "start": (page - 1) * 20,
      },
    );
    var result = json.decode(resultText);
    var items = <LiveAnchorItem>[];
    for (var item in result["response"]["1"]["docs"]) {
      var anchorItem = LiveAnchorItem(
        roomId: item["room_id"].toString(),
        avatar: item["game_avatarUrl180"].toString(),
        userName: item["game_nick"].toString(),
        liveStatus: item["gameLiveOn"],
      );
      items.add(anchorItem);
    }
    var hasMore = result["response"]["1"]["numFound"] > (page * 20);
    return LiveSearchAnchorResult(hasMore: hasMore, items: items);
  }

  @override
  Future<bool> getLiveStatus(
      {required String nick, required String platform, required String roomId, required String title}) async {
    var resultText = await HttpClient.instance.getText("https://m.huya.com/$roomId", queryParameters: {}, header: {
      "user-agent": kUserAgent,
      'Accept': '*/*',
      'Origin': 'https://www.huya.com',
      'Referer': 'https://www.huya.com/',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-site',
    });
    var text =
        RegExp(r"window\.HNF_GLOBAL_INIT.=.\{(.*?)\}.</script>", multiLine: false).firstMatch(resultText)?.group(1);
    var jsonObj = json.decode("{$text}");
    return jsonObj["roomInfo"]["eLiveStatus"] == 2;
  }

  /// 匿名登录获取uid
  Future<String> getAnonymousUid() async {
    var result = await HttpClient.instance.postJson(
      "https://udblgn.huya.com/web/anonymousLogin",
      data: {"appId": 5002, "byPass": 3, "context": "", "version": "2.4", "data": {}},
      header: {
        "user-agent": kUserAgent,
        'Accept': '*/*',
        'Origin': 'https://www.huya.com',
        'Referer': 'https://www.huya.com/',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-site',
      },
    );
    return result["data"]["uid"].toString();
  }

  String getUUid(cookie, streamName) {
    return getUid(cookie, streamName).toString();
  }

  int getUid(String cookie, String streamName) {
    try {
      if (cookie.contains('yyuid=')) {
        final match = RegExp(r'yyuid=(\d+)').firstMatch(cookie);
        if (match != null && match.groupCount >= 1) {
          return int.parse(match.group(1)!);
        }
      }
      final parts = streamName.split('-');
      if (parts.isNotEmpty) {
        final anchorUid = int.tryParse(parts[0]);
        if (anchorUid != null && anchorUid > 0) {
          return anchorUid;
        }
      }
    } catch (e) {
      // 在这里可以选择打印错误信息或采取其他措施
      debugPrint('An error occurred: $e');
    }
    // 如果没有找到有效的UID，则生成一个随机数
    final random = Random();
    return 1400000000000 + random.nextInt(100000000000); // 生成范围内的随机整数
  }

  String processAnticode(String anticode, String streamName) {
    var query = Uri.splitQueryString(anticode);
    query["t"] = query["t"] ?? "100";
    final uid = int.parse(getUUid(settings.huyaCookie.value, streamName));
    final convertUid = (uid << 8 | uid >> 24) & 0xFFFFFFFF;
    final wsTime = query["wsTime"]!;
    final seqId = (DateTime.now().millisecondsSinceEpoch + uid).toString();
    int ct = ((int.parse(wsTime, radix: 16) + Random().nextDouble()) * 1000).toInt();
    final fm = utf8.decode(base64.decode(Uri.decodeComponent(query['fm']!)));
    final wsSecretPrefix = fm.split('_').first;
    final wsSecretHash = md5.convert(utf8.encode('$seqId|${query["ctype"]}|${query["t"]}')).toString();
    final wsSecret =
        md5.convert(utf8.encode('${wsSecretPrefix}_${convertUid}_${streamName}_${wsSecretHash}_$wsTime')).toString();

    return Uri(queryParameters: {
      "wsSecret": wsSecret,
      "wsTime": wsTime,
      "seqid": seqId,
      "ctype": query["ctype"]!,
      "ver": "1",
      "fs": query["fs"]!,
      "t": query["t"]!,
      "u": convertUid.toString(),
      "uuid": (((ct % 1e10 + Random().nextDouble()) * 1e3).toInt() & 0xFFFFFFFF).toString(),
      "sdk_sid": DateTime.now().millisecondsSinceEpoch.toString(),
      "codec": "264"
    }).query;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) {
    //尚不支持
    return Future.value([]);
  }
}

class HuyaUrlDataModel {
  final String url;
  final String uid;
  List<HuyaLineModel> lines;
  List<HuyaBitRateModel> bitRates;
  final bool isXingxiu;
  HuyaUrlDataModel({
    required this.bitRates,
    required this.lines,
    required this.url,
    required this.uid,
    required this.isXingxiu,
  });
}

enum HuyaLineType {
  flv,
  hls,
}

class HuyaLineModel {
  final String line;
  final String flvAntiCode;
  final String hlsAntiCode;
  final String streamName;
  final HuyaLineType lineType;

  HuyaLineModel({
    required this.line,
    required this.lineType,
    required this.flvAntiCode,
    required this.hlsAntiCode,
    required this.streamName,
  });
  @override
  String toString() {
    return 'HuyaLineModel{line: $line, flvAntiCode: $flvAntiCode, hlsAntiCode: $hlsAntiCode, streamName: $streamName, lineType: $lineType}';
  }
}

class HuyaBitRateModel {
  final String name;
  final int bitRate;
  HuyaBitRateModel({
    required this.bitRate,
    required this.name,
  });
}
