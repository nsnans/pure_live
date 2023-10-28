import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_aliplayer/flutter_aliplayer.dart';
import 'package:flutter_aliplayer/flutter_aliplayer_factory.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/danmaku_text.dart';
import 'package:pure_live/plugins/barrage.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'video_controller_panel.dart';
import 'package:better_player/better_player.dart';
import 'package:fijkplayer/fijkplayer.dart';

class VideoController with ChangeNotifier {
  final GlobalKey playerKey;
  final LiveRoom room;
  final String datasourceType;
  String datasource;
  final bool allowBackgroundPlay;
  final bool allowScreenKeepOn;
  final bool allowFullScreen;
  final bool fullScreenByDefault;
  final bool autoPlay;
  final Map<String, String> headers;
  final isVertical = false.obs;
  final videoFit = BoxFit.contain.obs;

  final mediaPlayerControllerInitialized = false.obs;
  ScreenBrightness brightnessController = ScreenBrightness();
  BetterPlayerController? mobileController;
  double initBrightness = 0.0;
  final hasError = false.obs;
  final isPlaying = false.obs;
  final isBuffering = false.obs;
  final isPipMode = false.obs;
  final isFullscreen = false.obs;
  final isWindowFullscreen = false.obs;
  bool get supportPip => Platform.isAndroid;
  bool get supportWindowFull => Platform.isWindows || Platform.isLinux;
  bool get fullscreenUI => isFullscreen.value || isWindowFullscreen.value;
  final refreshCompleted = true.obs;
  // Video player status
  // A [GlobalKey<VideoState>] is required to access the programmatic fullscreen interface.
  late final GlobalKey<media_kit_video.VideoState> key =
      GlobalKey<media_kit_video.VideoState>();

  // Create a [Player] to control playback.
  late Player player;
  // CeoController] to handle video output from [Player].
  late media_kit_video.VideoController mediaPlayerController;

  late FijkPlayer fijkPlayer;

  final playerRefresh = false.obs;

  late FlutterAliplayer fAliplayer;
  GlobalKey<BrightnessVolumnDargAreaState> brightnessKey =
      GlobalKey<BrightnessVolumnDargAreaState>();

  LivePlayController livePlayController = Get.find<LivePlayController>();
  final SettingsService settings = Get.find<SettingsService>();
  int videoPlayerIndex = 1;
  bool enableCodec = true;
  // Controller ui status
  Timer? showControllerTimer;
  final showController = true.obs;
  final showSettting = false.obs;
  final showLocked = false.obs;
  final danmuKey = GlobalKey();
  double volume = 0.0;
  void enableController() {
    showControllerTimer?.cancel();
    showControllerTimer = Timer(const Duration(seconds: 2), () {
      showController.value = false;
    });
    showController.value = true;
  }

  // Danmaku player control
  BarrageWallController danmakuController = BarrageWallController();
  final hideDanmaku = false.obs;
  final danmakuArea = 1.0.obs;
  final danmakuSpeed = 8.0.obs;
  final danmakuFontSize = 16.0.obs;
  final danmakuFontBorder = 0.5.obs;
  final danmakuOpacity = 1.0.obs;
  VideoController({
    required this.playerKey,
    required this.room,
    required this.datasourceType,
    required this.datasource,
    required this.headers,
    this.allowBackgroundPlay = false,
    this.allowScreenKeepOn = false,
    this.allowFullScreen = true,
    this.fullScreenByDefault = false,
    this.autoPlay = true,
    BoxFit fitMode = BoxFit.contain,
  }) {
    videoFit.value = settings.videofitArrary[settings.videoFitIndex.value];
    hideDanmaku.value = settings.hideDanmaku.value;
    danmakuArea.value = settings.danmakuArea.value;
    danmakuSpeed.value = settings.danmakuSpeed.value;
    danmakuFontSize.value = settings.danmakuFontSize.value;
    danmakuFontBorder.value = settings.danmakuFontBorder.value;
    danmakuOpacity.value = settings.danmakuOpacity.value;
    initPagesConfig();
  }

  initPagesConfig() {
    if (allowScreenKeepOn) WakelockPlus.enable();
    initVideoController();
    initDanmaku();
    initBattery();
  }

  // Battery level control
  final Battery _battery = Battery();
  final batteryLevel = 100.obs;
  void initBattery() {
    if (Platform.isAndroid || Platform.isIOS) {
      _battery.batteryLevel.then((value) => batteryLevel.value = value);
      _battery.onBatteryStateChanged.listen((BatteryState state) async {
        batteryLevel.value = await _battery.batteryLevel;
      });
    }
  }

  void initVideoController() async {
    FlutterVolumeController.showSystemUI = false;
    videoPlayerIndex = settings.videoPlayerIndex.value;
    enableCodec = settings.enableCodec.value;
    if (Platform.isWindows || Platform.isLinux) {
      player = Player();
      if (player.platform is NativePlayer) {
        await (player.platform as dynamic).setProperty('cache', 'no');
      }
      mediaPlayerController = media_kit_video.VideoController(player);
      setDataSource(datasource);
      mediaPlayerController.player.stream.playing.listen((bool playing) {
        if (playing) {
          isPlaying.value = true;
        } else {
          isPlaying.value = false;
        }
      });
      mediaPlayerController.player.stream.error.listen((event) {
        hasError.value = true;
        isPlaying.value = false;
      });
      mediaPlayerControllerInitialized.value = true;
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (videoPlayerIndex == 0) {
        mobileController = BetterPlayerController(
          BetterPlayerConfiguration(
            autoPlay: true,
            fit: videoFit.value,
            allowedScreenSleep: !allowScreenKeepOn,
            autoDetectFullscreenDeviceOrientation: true,
            autoDetectFullscreenAspectRatio: true,
            errorBuilder: (context, errorMessage) => Container(),
            routePageBuilder:
                (context, animation, second, controllerProvider) =>
                    AnimatedBuilder(
              animation: animation,
              builder: (context, child) => MobileFullscreen(
                controller: this,
                controllerProvider: controllerProvider,
              ),
            ),
          ),
        );
        mobileController?.setControlsEnabled(false);
        setDataSource(datasource);
        mobileController?.addEventsListener(mobileStateListener);
      } else if (videoPlayerIndex == 1) {
        setDataSource(datasource);
      } else if (videoPlayerIndex == 2) {
        setDataSource(datasource);
      }
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
    debounce(hasError, (callback) {
      if (hasError.value) {
        livePlayController.changePlayLine();
      }
    }, time: const Duration(seconds: 1));
    // fix auto fullscreen
    if (fullScreenByDefault && datasource.isNotEmpty) {
      Timer(const Duration(milliseconds: 500), () => toggleFullScreen());
    }
  }

  void _playerValueChanged() {
    FijkValue value = fijkPlayer.value;
    bool playing = (value.state == FijkState.started);
    hasError.value = (value.state == FijkState.error);
    isPlaying.value = playing;
  }

  dynamic mobileStateListener(dynamic state) {
    if (mobileController?.videoPlayerController != null) {
      hasError.value =
          mobileController?.videoPlayerController?.value.hasError ?? true;
      isPlaying.value = mobileController?.isPlaying() ?? false;
      isBuffering.value = mobileController?.isBuffering() ?? false;
      isPipMode.value =
          mobileController?.videoPlayerController?.value.isPip ?? false;
    }
  }

  refreshView() {
    refreshCompleted.value = false;
    Timer(const Duration(microseconds: 200), () {
      brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();
      refreshCompleted.value = true;
    });
  }

  void initDanmaku() {
    hideDanmaku.value = PrefUtil.getBool('hideDanmaku') ?? false;
    hideDanmaku.listen((data) {
      PrefUtil.setBool('hideDanmaku', data);
    });
    danmakuArea.value = PrefUtil.getDouble('danmakuArea') ?? 1.0;
    danmakuArea.listen((data) {
      PrefUtil.setDouble('danmakuArea', data);
    });
    danmakuSpeed.value = PrefUtil.getDouble('danmakuSpeed') ?? 8;
    danmakuSpeed.listen((data) {
      PrefUtil.setDouble('danmakuSpeed', data);
    });
    danmakuFontSize.value = PrefUtil.getDouble('danmakuFontSize') ?? 16;
    danmakuFontSize.listen((data) {
      PrefUtil.setDouble('danmakuFontSize', data);
    });
    danmakuFontBorder.value = PrefUtil.getDouble('danmakuFontBorder') ?? 0.5;
    danmakuFontBorder.listen((data) {
      PrefUtil.setDouble('danmakuFontBorder', data);
    });
    danmakuOpacity.value = PrefUtil.getDouble('danmakuOpacity') ?? 1.0;
    danmakuOpacity.listen((data) {
      PrefUtil.setDouble('danmakuOpacity', data);
    });
  }

  void sendDanmaku(LiveMessage msg) {
    if (hideDanmaku.value) return;
    danmakuController.send([
      Bullet(
        child: DanmakuText(
          msg.message,
          fontSize: danmakuFontSize.value,
          strokeWidth: danmakuFontBorder.value,
          color: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b),
        ),
      ),
    ]);
  }

  @override
  void dispose() {
    if (allowScreenKeepOn) WakelockPlus.disable();
    if (Platform.isAndroid || Platform.isIOS) {
      if (videoPlayerIndex == 0) {
        mobileController?.removeEventsListener(mobileStateListener);
        mobileController?.dispose();
        mobileController = null;
      } else if (videoPlayerIndex == 1) {
        fijkPlayer.removeListener(_playerValueChanged);
        fijkPlayer.release();
      } else if (videoPlayerIndex == 2) {
        fAliplayer.destroy();
      }
      brightnessController.resetScreenBrightness();
    } else {
      if (key.currentState?.isFullscreen() ?? false) {
        key.currentState?.exitFullscreen();
      }
      mediaPlayerController.player.pause();
      player.dispose();
    }
    super.dispose();
  }

  void refresh() {
    if (Platform.isWindows || Platform.isLinux) {
      setDataSource(datasource);
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (videoPlayerIndex == 0) {
        if (mobileController?.videoPlayerController != null) {
          mobileController?.retryDataSource();
        }
      } else if (videoPlayerIndex == 1) {
        setFijkPlayerDataSource(refresh: true);
      } else if (videoPlayerIndex == 2) {
        setAliplayPlayerDataSource(refresh: true);
      }
    }
  }

  void setDataSource(String url, {bool refresh = false}) async {
    datasource = url;
    // fix datasource empty error
    if (datasource.isEmpty) {
      hasError.value = true;
      return;
    } else {
      hasError.value = false;
    }
    if (Platform.isWindows || Platform.isLinux) {
      player.pause();
      player.open(Media(datasource, httpHeaders: headers));
      mediaPlayerController.player.open(Media(datasource));
    } else {
      if (videoPlayerIndex == 0) {
        mobileController?.setupDataSource(BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          url,
          liveStream: true,
          headers: headers,
          bufferingConfiguration: const BetterPlayerBufferingConfiguration(
            minBufferMs: 30000 * 1000,
            maxBufferMs: 45000 * 1000,
            bufferForPlaybackMs: 1500,
            bufferForPlaybackAfterRebufferMs: 5000,
          ),
          notificationConfiguration: allowBackgroundPlay
              ? BetterPlayerNotificationConfiguration(
                  showNotification: true,
                  title: room.title,
                  imageUrl: room.avatar,
                  author: room.nick,
                  activityName: "MainActivity",
                  packageName: 'com.mystyle.purelive')
              : null,
        ));
        mobileController?.pause();
      } else if (videoPlayerIndex == 1) {
        setFijkPlayerDataSource(refresh: refresh);
      } else if (videoPlayerIndex == 2) {
        setAliplayPlayerDataSource(refresh: refresh);
      }
    }
    notifyListeners();
  }

  onViewPlayerCreated(viewId) {
    fAliplayer.setPlayerView(viewId);
  }

  setAliplayPlayerDataSource({bool refresh = false}) async {
    if (refresh) {
      playerRefresh.value = refresh;
      await fAliplayer.destroy();
    }
    fAliplayer = FlutterAliPlayerFactory.createAliPlayer();
    fAliplayer.register();
    await fAliplayer.setPreferPlayerName('纯粹直播');
    await fAliplayer.setEnableHardwareDecoder(enableCodec);
    fAliplayer.setOnStateChanged((newState, playerId) {
      if (newState == 3) {
        isPlaying.value = true;
      } else {
        isPlaying.value = false;
      }
      if (newState == 7) {
        hasError.value = true;
      }
    });
    fAliplayer.setOnError((errorCode, errorExtra, errorMsg, playerId) {
      hasError.value = true;
    });
    playerRefresh.value = false;
    await fAliplayer.setUrl(datasource);
    fAliplayer.setAutoPlay(true);
    await fAliplayer.prepare();
  }

  setFijkPlayerDataSource({bool refresh = false}) async {
    if (refresh) {
      playerRefresh.value = refresh;
      await fijkPlayer.stop();
      await fijkPlayer.release();
      fijkPlayer.removeListener(_playerValueChanged);
    }
    fijkPlayer = FijkPlayer();
    fijkPlayer.addListener(_playerValueChanged);
    await setIjkplayer();
    await fijkPlayer.reset();
    playerRefresh.value = false;
    await fijkPlayer.setDataSource(datasource, autoPlay: true);
    await fijkPlayer.prepareAsync();
  }

  Future setIjkplayer() async {
    var headersArr = [];
    headers.forEach((key, value) {
      headersArr.add('$key:$value');
    });
    fijkPlayer.setOption(
        FijkOption.formatCategory, "headers", headersArr.join('\r\n'));
    fijkPlayer.setOption(FijkOption.hostCategory, "request-screen-on", 1);
    fijkPlayer.setOption(FijkOption.hostCategory, "request-audio-focus", 1);
    fijkPlayer.setOption(FijkOption.playerCategory, "mediacodec-all-videos", 1);
    if (enableCodec) {
      fijkPlayer.setOption(FijkOption.codecCategory, "mediacodec", 1);
      fijkPlayer.setOption(
          FijkOption.codecCategory, "mediacodec-auto-rotate", 1);
      fijkPlayer.setOption(
          FijkOption.codecCategory, "mediacodec-handle-resolution-change", 1);
    }
  }

  void setVideoFit(BoxFit fit) {
    videoFit.value = fit;
    if (Platform.isWindows || Platform.isLinux) {
      key.currentState?.update(fit: fit);
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (videoPlayerIndex == 0) {
        mobileController?.setOverriddenFit(videoFit.value);
        mobileController?.retryDataSource();
      } else if (videoPlayerIndex == 1) {
        // fijkPlayer.s
      } else if (videoPlayerIndex == 2) {
        if (fit == BoxFit.contain) {
          fAliplayer.setScalingMode(FlutterAvpdef.AVP_SCALINGMODE_SCALETOFILL);
        } else if (fit == BoxFit.cover || fit == BoxFit.fill) {
          fAliplayer
              .setScalingMode(FlutterAvpdef.AVP_SCALINGMODE_SCALEASPECTFILL);
        } else if (fit == BoxFit.fitHeight || fit == BoxFit.fitWidth) {
          fAliplayer
              .setScalingMode(FlutterAvpdef.AVP_SCALINGMODE_SCALEASPECTFIT);
        }
      }
    }
    notifyListeners();
  }

  void togglePlayPause() {
    if (Platform.isWindows || Platform.isLinux) {
      mediaPlayerController.player.playOrPause();
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (videoPlayerIndex == 0) {
        isPlaying.value ? mobileController!.pause() : mobileController!.play();
      } else if (videoPlayerIndex == 1) {
        if (isPlaying.value) {
          fijkPlayer.pause();
        } else {
          fijkPlayer.start();
        }
      } else if (videoPlayerIndex == 2) {
        if (isPlaying.value) {
          fAliplayer.pause();
        } else {
          fAliplayer.play();
        }
      }
    }
  }

  Future<void> exitFullScreen() async {
    if (Platform.isAndroid) {
      if (videoPlayerIndex == 0) {
        mobileController?.exitFullScreen();
      } else if (videoPlayerIndex == 1) {
        fijkPlayer.exitFullScreen();
      }
      showSettting.value = false;
    }
  }

  /// 设置横屏
  Future setLandscapeOrientation() async {
    isVertical.value = false;
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(!isFullscreen.value
          ? SystemUiMode.edgeToEdge
          : SystemUiMode.immersiveSticky);
    }
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// 设置竖屏
  Future setPortraitOrientation() async {
    isVertical.value = true;
    SystemChrome.setEnabledSystemUIMode(!isFullscreen.value
        ? SystemUiMode.edgeToEdge
        : SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void toggleFullScreen() async {
    // disable locked
    showLocked.value = false;
    // fix danmaku overlap bug
    if (!hideDanmaku.value) {
      hideDanmaku.value = true;
      Timer(const Duration(milliseconds: 500), () {
        hideDanmaku.value = false;
      });
    }
    // fix obx setstate when build
    showControllerTimer?.cancel();
    Timer(const Duration(milliseconds: 500), () {
      enableController();
    });

    if (Platform.isWindows || Platform.isLinux) {
      if (key.currentState?.isFullscreen() ?? false) {
        key.currentState?.exitFullscreen();
      } else {
        key.currentState?.enterFullscreen();
      }
      isFullscreen.toggle();
    } else {
      if (videoPlayerIndex == 0) {
        mobileController?.toggleFullScreen();
        Timer(const Duration(milliseconds: 400), () {
          isFullscreen.toggle();
          // fix immersion status bar problem
          if (Platform.isAndroid) {
            SystemChrome.setEnabledSystemUIMode(!isFullscreen.value
                ? SystemUiMode.edgeToEdge
                : SystemUiMode.immersiveSticky);
          }
        });
      } else if (videoPlayerIndex == 1) {
        if (fijkPlayer.value.fullScreen) {
          fijkPlayer.exitFullScreen();
          Navigator.pop(Get.context!);
        } else {
          fijkPlayer.enterFullScreen();
          Navigator.push(
            Get.context!,
            MaterialPageRoute(
              builder: (context) => FijkFullscreen(
                controller: this,
              ),
            ),
          );
        }
        isFullscreen.toggle();
      } else if (videoPlayerIndex == 2) {
        if (isFullscreen.value) {
          Navigator.pop(Get.context!);
        } else {
          Navigator.push(
            Get.context!,
            MaterialPageRoute(
              builder: (context) => AliPlayerFullscreen(
                controller: this,
              ),
            ),
          );
        }
        isFullscreen.toggle();
      }
    }
    refreshView();
  }

  void toggleWindowFullScreen() {
    // disable locked
    showLocked.value = false;
    // fix danmaku overlap bug
    if (!hideDanmaku.value) {
      hideDanmaku.value = true;
      Timer(const Duration(milliseconds: 500), () {
        hideDanmaku.value = false;
      });
    }
    // fix obx setstate when build
    showControllerTimer?.cancel();
    Timer(const Duration(milliseconds: 500), () {
      enableController();
    });

    if (Platform.isWindows || Platform.isLinux) {
      if (!isWindowFullscreen.value) {
        Get.to(() => DesktopFullscreen(
              controller: this,
              key: UniqueKey(),
            ));
      } else {
        Get.back();
      }
      isWindowFullscreen.toggle();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
    enableController();
    refreshView();
  }

  void enterPipMode(BuildContext context) async {
    if ((Platform.isAndroid || Platform.isIOS)) {
      if (videoPlayerIndex == 0) {
        if (await mobileController?.isPictureInPictureSupported() ?? false) {
          isPipMode.value = true;
          mobileController?.enablePictureInPicture(playerKey);
        }
      }
    }
  }

  // volumn & brightness
  Future<double?> volumn() async {
    return await FlutterVolumeController.getVolume();
  }

  Future<double> brightness() async {
    return await brightnessController.current;
  }

  void setVolumn(double value) async {
    await FlutterVolumeController.setVolume(value);
  }

  void setBrightness(double value) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await brightnessController.setScreenBrightness(value);
    }
  }
}

// use fullscreen with controller provider

class DesktopFullscreen extends StatelessWidget {
  const DesktopFullscreen({Key? key, required this.controller})
      : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            Obx(() => media_kit_video.Video(
                  controller: controller.mediaPlayerController,
                  fit: controller.videoFit.value,
                  controls: (state) =>
                      VideoControllerPanel(controller: controller),
                ))
          ],
        ),
      ),
    );
  }
}

// use fullscreen with controller provider
class MobileFullscreen extends StatefulWidget {
  const MobileFullscreen({
    Key? key,
    required this.controller,
    required this.controllerProvider,
  }) : super(key: key);

  final VideoController controller;
  final BetterPlayerControllerProvider controllerProvider;

  @override
  State<MobileFullscreen> createState() => _MobileFullscreenState();
}

class _MobileFullscreenState extends State<MobileFullscreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (Platform.isAndroid || Platform.isIOS) {
        widget.controller.refresh();
      }
    }
  }

  @override
  dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: WillPopScope(
        onWillPop: () {
          widget.controller.toggleFullScreen();
          return Future(() => true);
        },
        child: Container(
          alignment: Alignment.center,
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              widget.controllerProvider,
              VideoControllerPanel(controller: widget.controller),
            ],
          ),
        ),
      ),
    );
  }
}

class FijkFullscreen extends StatefulWidget {
  const FijkFullscreen({Key? key, required this.controller}) : super(key: key);

  final VideoController controller;

  @override
  State<FijkFullscreen> createState() => _FijkFullscreenState();
}

class _FijkFullscreenState extends State<FijkFullscreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (Platform.isAndroid || Platform.isIOS) {
        widget.controller.refresh();
      }
    }
  }

  ImageProvider? getRoomCover(cover) {
    try {
      return CachedNetworkImageProvider(cover);
    } catch (e) {
      return null;
    }
  }

  FijkFit getFijkFit(BoxFit boxFit) {
    FijkFit fijkFit = FijkFit.contain;
    if (boxFit == BoxFit.contain) {
      fijkFit = FijkFit.contain;
    } else if (boxFit == BoxFit.cover) {
      fijkFit = FijkFit.cover;
    } else if (boxFit == BoxFit.fill) {
      fijkFit = FijkFit.fill;
    } else if (boxFit == BoxFit.fitHeight) {
      fijkFit = FijkFit.fitHeight;
    } else if (boxFit == BoxFit.fitWidth) {
      fijkFit = FijkFit.fitWidth;
    }
    return fijkFit;
  }

  Widget _buildIjkPanel(FijkPlayer fijkPlayer, FijkData fijkData,
      BuildContext context, Size viewSize, Rect texturePos) {
    return VideoControllerPanel(controller: widget.controller);
  }

  @override
  dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.setPortraitOrientation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isFullScreen = widget.controller.fijkPlayer.value.fullScreen;
    if (isFullScreen) {
      widget.controller.setLandscapeOrientation();
    }
    return Scaffold(
      body: Obx(() => FijkView(
            player: widget.controller.fijkPlayer,
            color: Colors.black,
            fit: getFijkFit(widget.controller.videoFit.value),
            cover: getRoomCover(widget.controller.room.cover),
            fs: false,
            panelBuilder: _buildIjkPanel,
          )),
    );
  }
}

class AliPlayerFullscreen extends StatefulWidget {
  const AliPlayerFullscreen({Key? key, required this.controller})
      : super(key: key);

  final VideoController controller;

  @override
  State<AliPlayerFullscreen> createState() => _AliPlayerFullscreenState();
}

class _AliPlayerFullscreenState extends State<AliPlayerFullscreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    bool isFullScreen = widget.controller.isFullscreen.value;
    if (isFullScreen) {
      widget.controller.setLandscapeOrientation();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (Platform.isAndroid || Platform.isIOS) {
        widget.controller.refresh();
      }
    }
  }

  @override
  dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.setPortraitOrientation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Stack(
      children: [
        AliPlayerView(
            onCreated: widget.controller.onViewPlayerCreated,
            x: 0.0,
            y: 0.0,
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height),
        VideoControllerPanel(controller: widget.controller)
      ],
    ));
  }
}
