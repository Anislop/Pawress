import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'downloads.dart';
import 'theme.dart';
import 'widgets.dart';

/// Full-screen viewer for a post's images and videos, one under another in
/// a single vertical scroll. Images zoom with pinch and double-tap (the list
/// holds still while one is zoomed); a video plays while it's the item
/// filling most of the screen.
///
/// Full files need the post's signed `temp_url`s, which feed posts lack, so
/// the post is fetched again first when needed. Only items on screen load
/// their full file, through [_FullFileGate], keeping to Pawchive's download
/// limits.
class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.post, this.initialIndex = 0});

  final Post post;
  final int initialIndex;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late List<MediaFile> _media = widget.post.media;
  late int _index = widget.initialIndex;
  final _centerKey = UniqueKey();
  final _gate = _FullFileGate();

  /// On-screen height of each visible item.
  final _visible = <int, double>{};
  ScrollController? _scroll;
  bool _chrome = true;
  bool _zoomed = false;
  String? _error;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    if (_media.any((m) => m.fullUrl == null)) _resolve();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Opens with the tapped item just below the top bar; the list is
    // centered on it so earlier items grow upward without moving it.
    _scroll ??= ScrollController(initialScrollOffset: -_topInset);
  }

  double get _topInset => MediaQuery.paddingOf(context).top + kToolbarHeight;

  Future<void> _resolve() async {
    setState(() => _resolving = true);
    try {
      final post = widget.post;
      final full = await AppScope.read(context).api
          .post(post.service, post.user, post.id);
      if (!mounted) return;
      final byPath = {for (final m in full.media) m.path: m};
      setState(() => _media = [for (final m in _media) byPath[m.path] ?? m]);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _onVisible(int index, VisibilityInfo info) {
    if (!mounted) return;
    final height = info.visibleFraction == 0 ? 0.0 : info.visibleBounds.height;
    final wasVisible = _visible.containsKey(index);
    if (height == 0) {
      _visible.remove(index);
    } else {
      _visible[index] = height;
    }
    var current = _index;
    var most = 0.0;
    for (final MapEntry(key: i, value: shown) in _visible.entries) {
      if (shown > most || (shown == most && i < current)) {
        most = shown;
        current = i;
      }
    }
    if (current != _index || wasVisible != (height > 0)) {
      setState(() => _index = current);
    }
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  Widget _item(int index) {
    final item = _media[index];
    final Widget child;
    if (item.isVideo) {
      child = item.fullUrl == null
          ? AspectRatio(
              aspectRatio: 16 / 9,
              child: _Pending(resolving: _resolving, error: _error),
            )
          : _VideoItem(
              key: ValueKey(item.fullUrl),
              url: item.fullUrl!,
              active: index == _index,
              autoplay: AppScope.read(context).settings.autoplayVideos,
            );
    } else {
      child = GestureDetector(
        onTap: () => setState(() => _chrome = !_chrome),
        child: _ImageItem(
          key: ValueKey(item.path),
          file: item,
          gate: _gate,
          loadFull: !_resolving && _visible.containsKey(index),
          onZoom: (zoomed) {
            if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
          },
        ),
      );
    }
    return VisibilityDetector(
      key: ValueKey('viewer/$index'),
      onVisibilityChanged: (info) => _onVisible(index, info),
      child: Padding(padding: const EdgeInsets.only(bottom: 4), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _media[_index.clamp(0, _media.length - 1)];
    final start = widget.initialIndex.clamp(0, _media.length);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            center: _centerKey,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: _topInset)),
              // Above the center: the items before the tapped one, nearest
              // first.
              SliverList.builder(
                itemCount: start,
                itemBuilder: (context, i) => _item(start - 1 - i),
              ),
              SliverList.builder(
                key: _centerKey,
                itemCount: _media.length - start,
                itemBuilder: (context, i) => _item(start + i),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + 24,
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _chrome ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_chrome,
                child: _TopBar(
                  title: _media.length > 1
                      ? '${_index + 1} / ${_media.length}'
                      : '',
                  subtitle: file.name,
                  onOpen: file.fullUrl == null
                      ? null
                      : () => openExternal(file.fullUrl!),
                  onDownload: _resolving
                      ? null
                      : () => downloadFiles(context, widget.post, [file]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hands out full-file loads at most [_concurrent] at a time and
/// [_spacing] apart, so scrolling through a long post keeps to the file
/// host's limits.
class _FullFileGate {
  static const _concurrent = 2;
  static const _spacing = Duration(seconds: 1);

  int _running = 0;
  DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);
  final _waiting = <Completer<void>>[];

  Future<void> acquire() async {
    while (_running >= _concurrent) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    final now = DateTime.now();
    final wait = _next.difference(now);
    _next = (wait.isNegative ? now : _next).add(_spacing);
    if (!wait.isNegative) await Future<void>.delayed(wait);
  }

  void release() {
    _running--;
    if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    this.onOpen,
    this.onDownload,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onOpen;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black87, Colors.transparent],
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty)
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            if (onDownload != null)
              IconButton(
                tooltip: 'Download',
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                onPressed: onDownload,
              ),
            if (onOpen != null)
              IconButton(
                tooltip: 'Open in browser',
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  color: Colors.white,
                ),
                onPressed: onOpen,
              ),
          ],
        ),
      ),
    ),
  );
}

class _Pending extends StatelessWidget {
  const _Pending({required this.resolving, this.error});

  final bool resolving;
  final String? error;

  @override
  Widget build(BuildContext context) => Center(
    child: resolving
        ? const CircularProgressIndicator()
        : Text(
            error ?? 'This file is not available.',
            style: const TextStyle(color: Colors.white70),
          ),
  );
}

/// An image at the screen's width: the thumbnail at once, then the full
/// file over it once [loadFull] allows and the gate gives it a turn.
class _ImageItem extends StatefulWidget {
  const _ImageItem({
    super.key,
    required this.file,
    required this.gate,
    required this.loadFull,
    required this.onZoom,
  });

  final MediaFile file;
  final _FullFileGate gate;
  final bool loadFull;
  final ValueChanged<bool> onZoom;

  @override
  State<_ImageItem> createState() => _ImageItemState();
}

class _ImageItemState extends State<_ImageItem>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _zoomAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => _transform.value = _zoomTween!.evaluate(_zoomAnimation));
  Matrix4Tween? _zoomTween;
  TapDownDetails? _doubleTap;
  bool _zoomed = false;

  /// The full file, once its turn came.
  String? _full;
  bool _requested = false;
  bool _holding = false;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed == _zoomed) return;
      setState(() => _zoomed = zoomed);
      widget.onZoom(zoomed);
    });
    if (widget.loadFull) _request();
  }

  @override
  void didUpdateWidget(_ImageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadFull && !_requested) _request();
  }

  Future<void> _request() async {
    final url = widget.file.fullUrl;
    if (url == null || url == widget.file.thumbnailUrl) return;
    _requested = true;
    await widget.gate.acquire();
    if (!mounted || !widget.loadFull) {
      // Scrolled away while waiting; ask again when it's back.
      widget.gate.release();
      _requested = false;
      return;
    }
    _holding = true;
    _listener = ImageStreamListener(
      (_, _) => _finished(),
      onError: (_, _) => _finished(),
    );
    _stream = netImageProvider(
      url,
    ).resolve(createLocalImageConfiguration(context))..addListener(_listener!);
    setState(() => _full = url);
  }

  void _finished() {
    if (!_holding) return;
    _holding = false;
    widget.gate.release();
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _finished();
    _zoomAnimation.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    final position = _doubleTap?.localPosition ?? Offset.zero;
    final target = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(-position.dx * 1.5, -position.dy * 1.5, 0, 1)
            ..scaleByDouble(2.5, 2.5, 1, 1));
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target);
    _zoomAnimation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final thumb = file.thumbnailUrl;
    final full = _full;
    Widget box(double ratio, [Widget? child]) => AspectRatio(
      aspectRatio: ratio,
      child: ColoredBox(color: Colors.white10, child: child),
    );
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTap = details,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        // Panning at 1x would take vertical drags from the list.
        panEnabled: _zoomed,
        minScale: 1,
        maxScale: 6,
        child: Stack(
          children: [
            // The thumbnail sets the height; the full file has the same
            // shape.
            if (thumb == null)
              box(1)
            else
              Image(
                image: netImageProvider(thumb),
                width: double.infinity,
                fit: BoxFit.fitWidth,
                frameBuilder: (context, child, frame, sync) =>
                    frame == null && !sync ? box(3 / 4) : child,
                errorBuilder: (_, _, _) => box(
                  1,
                  full == null
                      ? const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                          size: 40,
                        )
                      : null,
                ),
              ),
            if (full != null)
              Positioned.fill(
                child: Image(
                  image: netImageProvider(full),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, _) => AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: child,
                  ),
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            child,
                            SizedBox.square(
                              dimension: 36,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                value: progress.expectedTotalBytes == null
                                    ? null
                                    : progress.cumulativeBytesLoaded /
                                          progress.expectedTotalBytes!,
                              ),
                            ),
                          ],
                        ),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A video with Chewie's controls at its own shape. It only loads and plays
/// while [active].
class _VideoItem extends StatefulWidget {
  const _VideoItem({
    super.key,
    required this.url,
    required this.active,
    required this.autoplay,
  });

  final String url;
  final bool active;
  final bool autoplay;

  @override
  State<_VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<_VideoItem> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(_VideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _video == null) _start();
    if (!widget.active) _video?.pause();
  }

  Future<void> _start() async {
    final video = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: mediaHeaders,
    );
    _video = video;
    try {
      await video.initialize();
    } catch (_) {
      if (mounted) setState(() => _error = 'This video could not be played.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _chewie = ChewieController(
        videoPlayerController: video,
        autoPlay: widget.autoplay && widget.active,
        looping: video.value.duration < const Duration(seconds: 30),
        allowFullScreen: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: pawPink,
          handleColor: pawPinkLight,
          bufferedColor: pawMauve,
        ),
      );
    });
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chewie = _chewie;
    if (chewie == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(
          child: _error != null
              ? Text(_error!, style: const TextStyle(color: Colors.white70))
              : _video != null
              ? const CircularProgressIndicator()
              : const Icon(
                  Icons.play_circle_outline_rounded,
                  color: Colors.white70,
                  size: 56,
                ),
        ),
      );
    }
    final ratio = _video!.value.aspectRatio;
    return AspectRatio(
      aspectRatio: ratio > 0 ? ratio : 16 / 9,
      child: Chewie(controller: chewie),
    );
  }
}
