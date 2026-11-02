import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/config.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'widgets.dart';

/// Picks the one feed tile that plays: the most visible GIF or video that's
/// at least 60% on screen. One shared instance covers every feed; tiles on
/// covered pages report nothing visible, and tiles also check that their
/// route is on top.
class FeedAutoplay extends ChangeNotifier {
  FeedAutoplay._();

  static final instance = FeedAutoplay._();

  final _visible = <Key, double>{};
  Key? _active;

  bool isActive(Key key) => _active == key;

  /// For a disposed tile. The tree is locked then, so listeners hear about
  /// it after the frame.
  void forget(Key key) {
    _visible.remove(key);
    if (_active == key) scheduleMicrotask(() => report(key, 0));
  }

  void report(Key key, double fraction) {
    if (fraction < .6) {
      _visible.remove(key);
    } else {
      _visible[key] = fraction;
    }
    // Keep the current tile while it's still visible enough, so two tiles
    // don't trade places while scrolling slowly.
    var next = _visible.containsKey(_active) ? _active : null;
    if (next == null) {
      var best = 0.0;
      for (final entry in _visible.entries) {
        if (entry.value > best) {
          best = entry.value;
          next = entry.key;
        }
      }
    }
    if (next != _active) {
      _active = next;
      notifyListeners();
    }
  }
}

/// Full URLs for preview-only files, found by fetching their post once.
final _resolved = <String, String?>{};

/// A GIF or video tile that plays muted and looping while it's the
/// [FeedAutoplay] pick. Otherwise it shows [still] (the thumbnail or a
/// placeholder) under [overlay].
class AutoplayMedia extends StatefulWidget {
  const AutoplayMedia({
    super.key,
    required this.post,
    required this.file,
    required this.still,
    required this.overlay,
  });

  final Post post;
  final MediaFile file;
  final Widget still;

  /// Badges drawn over the still; the play badge is hidden while playing.
  final Widget Function(bool playing) overlay;

  @override
  State<AutoplayMedia> createState() => _AutoplayMediaState();
}

class _AutoplayMediaState extends State<AutoplayMedia> {
  final _key = UniqueKey();
  Timer? _start;
  bool _wanted = false;
  String? _url;
  VideoPlayerController? _video;
  bool _failed = false;
  bool _enabled = false;
  bool _onTop = true;

  @override
  void initState() {
    super.initState();
    FeedAutoplay.instance.addListener(_update);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also runs when the route is covered or uncovered.
    _enabled = AppScope.of(context).settings.autoplayVideos;
    _onTop = ModalRoute.isCurrentOf(context) ?? true;
    _update(rebuild: false);
  }

  @override
  void dispose() {
    FeedAutoplay.instance
      ..removeListener(_update)
      ..forget(_key);
    _start?.cancel();
    _video?.dispose();
    super.dispose();
  }

  void _update({bool rebuild = true}) {
    if (!mounted) return;
    final wanted =
        _enabled && _onTop && !_failed && FeedAutoplay.instance.isActive(_key);
    if (wanted == _wanted) return;
    _wanted = wanted;
    _start?.cancel();
    if (wanted) {
      // A short wait so flinging past a tile doesn't start a download.
      _start = Timer(const Duration(milliseconds: 400), _play);
    } else {
      _video?.pause();
      if (rebuild) setState(() {});
    }
  }

  Future<void> _play() async {
    try {
      _url ??= await _fullUrl();
      if (_url == null) throw StateError('No file URL');
      if (widget.file.isVideo && _video == null) {
        final video = VideoPlayerController.networkUrl(
          Uri.parse(_url!),
          httpHeaders: mediaHeaders,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        _video = video;
        await video.initialize();
        await video.setVolume(0);
        await video.setLooping(true);
      }
      if (!mounted || !_wanted) return;
      await _video?.play();
      setState(() {});
    } catch (_) {
      // Leave the still in place; the viewer still opens the file on tap.
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<String?> _fullUrl() async {
    final direct = widget.file.fullUrl;
    if (direct != null) return direct;
    final path = widget.file.path;
    if (_resolved.containsKey(path)) return _resolved[path];
    final post = await AppScope.read(context).api
        .post(widget.post.service, widget.post.user, widget.post.id);
    for (final file in post.files) {
      _resolved[file.path] = file.fullUrl;
    }
    return _resolved[path];
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final playing =
        _wanted &&
        _url != null &&
        (video == null || (video.value.isInitialized && video.value.isPlaying));
    return VisibilityDetector(
      key: _key,
      onVisibilityChanged: (info) =>
          FeedAutoplay.instance.report(_key, info.visibleFraction),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.still,
          if (playing && video != null)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: video.value.size.width,
                height: video.value.size.height,
                child: VideoPlayer(video),
              ),
            )
          else if (playing)
            NetImage(_url!, placeholder: widget.still),
          widget.overlay(playing),
        ],
      ),
    );
  }
}
