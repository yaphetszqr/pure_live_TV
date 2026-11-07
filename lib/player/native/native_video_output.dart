import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';
import 'package:pure_live/core/utils/hive_pref_util.dart';

/// mpv drawn into a native Android SurfaceView instead of a Flutter texture.
///
/// TVs often render their UI at 1080p and scale it to a 4K panel. A texture is
/// composited into that UI layer, so a 1440p or 2160p stream is squeezed to
/// 1080p first. A SurfaceView embedded with Hybrid Composition gets its own
/// hardware layer: with `hwdec=mediacodec` and `vo=mediacodec_embed` the
/// decoder writes straight into it and the TV scales the frames to the panel.
///
/// The surface has to be wired before mpv starts decoding. Switching the
/// output of a player that is already decoding rebuilds the video decoder,
/// which then waits for the next keyframe: seconds of sound without picture on
/// a live stream. So the room mounts [NativeVideoSurfaceHost] when it opens,
/// and every media_kit player reports itself here the moment it is created
/// ([adapterCreated]), before its source is opened.
///
/// All mpv writes for the surface run through one queue: they are synchronous
/// on the UI thread, and interleaving two of them is how a stale detach used to
/// clobber a fresh attach.
class NativeVideoOutput {
  NativeVideoOutput._();

  static final NativeVideoOutput instance = NativeVideoOutput._();

  static const String _prefKey = 'nativeVideoSurface';

  /// The user's choice. Applies to rooms opened after it changes.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(HivePrefUtil.getBool(_prefKey) ?? false);

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await HivePrefUtil.setBool(_prefKey, value);
  }

  /// Whether rooms render through the native surface.
  static bool get active => Platform.isAndroid && enabled.value;

  /// The player the surface belongs to. Set the moment a player is built,
  /// before it is initialized.
  final ValueNotifier<MediaKitPlayerAdapter?> owner = ValueNotifier<MediaKitPlayerAdapter?>(null);

  /// The player currently drawing into the surface, initialized by then.
  /// Hosts lay the surface out by its video size and fit.
  final ValueNotifier<MediaKitPlayerAdapter?> attached = ValueNotifier<MediaKitPlayerAdapter?>(null);

  Object? _host;
  int _wid = 0;
  int _width = 0;
  int _height = 0;

  MediaKitPlayerAdapter? _attachedTo;
  int _attachedWid = 0;

  Future<void> _queue = Future<void>.value();

  /// media_kit's Android controller of each player whose `wid` listener is
  /// unhooked while the surface drives it.
  final Expando<Object> _unhooked = Expando<Object>();

  /// Players whose video track this class turned off; it is turned back on
  /// when they get a surface again.
  final Expando<bool> _videoOff = Expando<bool>();

  /// Players whose texture output was given back without being redrawn.
  final Expando<Object> _pendingTextureRestore = Expando<Object>();

  // ---------------------------------------------------------------------------
  // Players
  // ---------------------------------------------------------------------------

  /// A media_kit player was just built, its source not opened yet.
  ///
  /// It takes the surface unless another live player holds it (a player that
  /// is no longer [MediaKitPlayerAdapter.available] has been released). That happens
  /// when an engine switch stages a new player while the old one still plays:
  /// a Surface accepts one producer, so the new player takes over at commit,
  /// through [claim].
  void adapterCreated(MediaKitPlayerAdapter adapter) {
    if (!active) return;
    final MediaKitPlayerAdapter? current = owner.value;
    if (current != null && current.available && current != adapter) return;
    owner.value = adapter;
    _sync();
  }

  /// [adapter] is the player the room now shows.
  void claim(MediaKitPlayerAdapter adapter) {
    if (!active || owner.value == adapter) return;
    owner.value = adapter;
    _sync();
  }

  // ---------------------------------------------------------------------------
  // Surface (reported by the host's platform view)
  // ---------------------------------------------------------------------------

  void _surfaceAvailable(Object host, int wid, int width, int height) {
    _host = host;
    _wid = wid;
    _width = width;
    _height = height;
    _sync();
  }

  void _surfaceResized(Object host, int width, int height) {
    if (host != _host) return;
    _width = width;
    _height = height;
    _enqueue(() async {
      final MediaKitPlayerAdapter? adapter = _attachedTo;
      if (adapter != null && adapter.available) await _set(adapter, 'android-surface-size', '${width}x$height');
    });
  }

  /// The host's surface is gone (view removed, or the app went to the
  /// background). A newer host may already have taken over.
  void _surfaceGone(Object host) {
    if (host != _host) return;
    _host = null;
    _wid = 0;
    _sync();
  }

  // ---------------------------------------------------------------------------
  // Wiring
  // ---------------------------------------------------------------------------

  void _enqueue(Future<void> Function() step) {
    _queue = _queue.then((_) => step()).catchError((Object e) {
      debugPrint('native video output: $e');
    });
  }

  /// Brings mpv in line with the current surface and owner. Every decision is
  /// taken when the step runs, so a burst of changes settles on the last one.
  void _sync() {
    _enqueue(() async {
      final MediaKitPlayerAdapter? target = owner.value;
      final int wid = _wid;
      // A just-built owner is not initialized (not `available`) yet; _attach
      // waits for that.
      final bool wanted = target != null && wid != 0;
      final MediaKitPlayerAdapter? current = _attachedTo;

      if (current != null && (!wanted || current != target || _attachedWid != wid)) {
        _attachedTo = null;
        _attachedWid = 0;
        attached.value = null;
        if (current.available) await _detach(current, keepUnhooked: wanted && current == target);
      }
      if (wanted && _attachedTo == null) await _attach(target, wid);
    });
  }

  Future<void> _attach(MediaKitPlayerAdapter adapter, int wid) async {
    final dynamic controller = await _textureController(adapter);
    if (controller == null || !adapter.available || owner.value != adapter || _wid != wid) return;

    // AndroidVideoController is not exported; its `wid` notifier and
    // `widListener` are public members, reached dynamically.
    if (_unhooked[adapter.player] == null) {
      (controller.wid as ValueNotifier<int?>).removeListener(controller.widListener as VoidCallback);
      _unhooked[adapter.player] = controller;
    }
    _pendingTextureRestore[adapter.player] = null;

    // media_kit's own order: vo=null first, then size and wid, then the real vo.
    await _set(adapter, 'vo', 'null');
    await _set(adapter, 'hwdec', 'mediacodec');
    await _set(adapter, 'android-surface-size', '${_width}x$_height');
    await _set(adapter, 'wid', '$wid');
    await _set(adapter, 'vo', 'mediacodec_embed');
    if (_videoOff[adapter.player] == true) {
      _videoOff[adapter.player] = null;
      await _set(adapter, 'vid', 'auto');
    }
    _attachedTo = adapter;
    _attachedWid = wid;
    attached.value = adapter;
  }

  /// Takes the surface away from [adapter].
  ///
  /// Video decoding stops first: dropping the output while frames are still
  /// decoding makes mpv rebuild the decoder in software, and these writes are
  /// synchronous on the UI thread. With no video track the rest is instant.
  Future<void> _detach(MediaKitPlayerAdapter adapter, {required bool keepUnhooked}) async {
    _videoOff[adapter.player] = true;
    await _set(adapter, 'vid', 'no');
    await _set(adapter, 'vo', 'null');
    await _set(adapter, 'wid', '0');
    if (!keepUnhooked) await _releaseTexture(adapter);
  }

  /// Gives `wid` back to media_kit and puts its decoder setting back, without
  /// redrawing: see [restoreTextureIfNeeded].
  Future<void> _releaseTexture(MediaKitPlayerAdapter adapter) async {
    final dynamic controller = _unhooked[adapter.player];
    if (controller == null) return;
    _unhooked[adapter.player] = null;
    (controller.wid as ValueNotifier<int?>).addListener(controller.widListener as VoidCallback);
    final String? hwdec = (controller.configuration as VideoControllerConfiguration).hwdec;
    if (hwdec != null) await _set(adapter, 'hwdec', hwdec);
    _pendingTextureRestore[adapter.player] = controller;
  }

  /// media_kit's Android controller of [adapter], once the adapter has been
  /// initialized and the controller created. Null for an audio-only player.
  Future<dynamic> _textureController(MediaKitPlayerAdapter adapter) async {
    // The kernel initializes a player right after building it; the controller
    // exists from then on.
    for (var i = 0; i < 100 && adapter.videoController == null; i++) {
      if (owner.value != adapter) return null;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    final controller = adapter.videoController;
    if (controller == null) return null;
    return controller.platform.future;
  }

  Future<void> _set(MediaKitPlayerAdapter adapter, String name, String value) async {
    try {
      final native = adapter.player.platform;
      if (native is NativePlayer) await native.setProperty(name, value);
    } catch (e) {
      debugPrint('native video output: mpv rejected $name=$value: $e');
    }
  }

  /// Re-arms media_kit's texture output for [adapter] if the surface left it
  /// idle. Called before the texture view is built for the same player.
  ///
  /// Not done when the surface goes away: re-initialising the output while
  /// video is decoding makes mpv rebuild its decoder, in software, through
  /// synchronous writes on the UI thread. Most of the time the player is
  /// closing anyway.
  void restoreTextureIfNeeded(MediaKitPlayerAdapter adapter) {
    final Player player;
    try {
      player = adapter.player;
    } catch (_) {
      return;
    }
    final dynamic controller = _pendingTextureRestore[player];
    if (controller == null) return;
    _pendingTextureRestore[player] = null;
    _enqueue(() async {
      if (!adapter.available) return;
      if (_videoOff[player] == true) {
        _videoOff[player] = null;
        await _set(adapter, 'vid', 'auto');
      }
      await (controller.widListener() as Future<void>);
    });
  }
}

/// The native SurfaceView a room shows mpv through. Mounted with the room, so
/// the surface exists before the player starts decoding.
class NativeVideoSurfaceHost extends StatefulWidget {
  const NativeVideoSurfaceHost({super.key});

  @override
  State<NativeVideoSurfaceHost> createState() => _NativeVideoSurfaceHostState();
}

class _NativeVideoSurfaceHostState extends State<NativeVideoSurfaceHost> {
  static const String _viewType = 'purelive/native_video_surface';

  final NativeVideoOutput _output = NativeVideoOutput.instance;
  final Object _token = Object();
  MethodChannel? _channel;
  final List<StreamSubscription<int?>> _sizeSubscriptions = [];
  MediaKitPlayerAdapter? _watched;

  @override
  void initState() {
    super.initState();
    _output.attached.addListener(_onAttachedChanged);
    _onAttachedChanged();
  }

  /// Follows the attached player's video size, which lays the surface out.
  void _onAttachedChanged() {
    final MediaKitPlayerAdapter? adapter = _output.attached.value;
    if (adapter == _watched) return;
    _watched = adapter;
    for (final subscription in _sizeSubscriptions) {
      unawaited(subscription.cancel());
    }
    _sizeSubscriptions.clear();
    if (adapter != null && adapter.available) {
      final Player player = adapter.player;
      _sizeSubscriptions.add(player.stream.width.listen((_) => _rebuild()));
      _sizeSubscriptions.add(player.stream.height.listen((_) => _rebuild()));
    }
    _rebuild();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('$_viewType/$id');
    _channel = channel;
    channel.setMethodCallHandler(_onCall);
    // The surface may already exist; ask for it now that Dart listens.
    unawaited(channel.invokeMethod<void>('sync').catchError((Object _) {}));
  }

  Future<dynamic> _onCall(MethodCall call) async {
    final Map<dynamic, dynamic> args = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'attach':
        _output._surfaceAvailable(_token, args['wid'] as int, args['width'] as int, args['height'] as int);
      case 'resize':
        _output._surfaceResized(_token, args['width'] as int, args['height'] as int);
      case 'detach':
        _output._surfaceGone(_token);
    }
  }

  @override
  void dispose() {
    _output.attached.removeListener(_onAttachedChanged);
    for (final subscription in _sizeSubscriptions) {
      unawaited(subscription.cancel());
    }
    _channel?.setMethodCallHandler(null);
    _output._surfaceGone(_token);
    super.dispose();
  }

  /// mediacodec_embed fills the whole surface, so the surface itself is laid
  /// out with the video's aspect ratio and the owner's fit.
  Size _surfaceSize(BoxConstraints constraints, BoxFit fit) {
    final Size box = constraints.biggest;
    final MediaKitPlayerAdapter? adapter = _watched;
    if (adapter == null || !adapter.available || !box.isFinite) return box;
    final int width = adapter.player.state.width ?? 0;
    final int height = adapter.player.state.height ?? 0;
    if (width <= 0 || height <= 0) return box;
    return applyBoxFit(fit, Size(width.toDouble(), height.toDouble()), box).destination;
  }

  @override
  Widget build(BuildContext context) {
    final ValueListenable<BoxFit> fitListenable = _watched?.fitListenable ?? const _FixedFit(BoxFit.contain);
    return ValueListenableBuilder<BoxFit>(
      valueListenable: fitListenable,
      builder: (context, fit, _) => LayoutBuilder(
        builder: (context, constraints) {
          final Size size = _surfaceSize(constraints, fit);
          return ClipRect(
            child: OverflowBox(
              maxWidth: size.width,
              maxHeight: size.height,
              child: SizedBox.fromSize(
                size: size,
                child: PlatformViewLink(
                  viewType: _viewType,
                  surfaceFactory: (context, controller) => AndroidViewSurface(
                    controller: controller as AndroidViewController,
                    gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
                    hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                  ),
                  onCreatePlatformView: (params) =>
                      PlatformViewsService.initExpensiveAndroidView(
                          id: params.id,
                          viewType: _viewType,
                          layoutDirection: TextDirection.ltr,
                          creationParamsCodec: const StandardMessageCodec(),
                        )
                        ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                        ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
                        ..create(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A fit that never changes, for when no player owns the surface yet.
class _FixedFit implements ValueListenable<BoxFit> {
  const _FixedFit(this.value);

  @override
  final BoxFit value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
