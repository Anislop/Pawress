import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'downloads.dart';
import 'theme.dart';
import 'widgets.dart';

/// Full-screen, swipeable viewer for a post's images and videos. Images
/// zoom with pinch and double-tap; videos play inline.
///
/// Full files need the post's signed `temp_url`s, which feed posts lack, so
/// the post is fetched again first when needed. Only the page on screen
/// loads its full file, keeping to Pawchive's download limits.
class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.post, this.initialIndex = 0});

  final Post post;
  final int initialIndex;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late List<MediaFile> _media = widget.post.media;
  late int _index = widget.initialIndex;
  bool _chrome = true;
  bool _zoomed = false;
  String? _error;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    if (_media.any((m) => m.fullUrl == null)) _resolve();
  }

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

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = _media[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            itemCount: _media.length,
            onPageChanged: (index) => setState(() {
              _index = index;
              _zoomed = false;
            }),
            itemBuilder: (context, index) {
              final item = _media[index];
              final active = index == _index;
              if (item.isVideo) {
                if (item.fullUrl == null) {
                  return _Pending(resolving: _resolving, error: _error);
                }
                return _VideoPage(
                  key: ValueKey(item.fullUrl),
                  url: item.fullUrl!,
                  active: active,
                  autoplay: AppScope.read(context).settings.autoplayVideos,
                );
              }
              return GestureDetector(
                onTap: () => setState(() => _chrome = !_chrome),
                child: _ImagePage(
                  file: item,
                  loadFull: active && !_resolving,
                  onZoom: (zoomed) {
                    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                  },
                ),
              );
            },
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

/// The thumbnail at once, then the full file once [loadFull] allows it.
class _ImagePage extends StatefulWidget {
  const _ImagePage({
    required this.file,
    required this.loadFull,
    required this.onZoom,
  });

  final MediaFile file;
  final bool loadFull;
  final ValueChanged<bool> onZoom;

  @override
  State<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<_ImagePage>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _zoomAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => _transform.value = _zoomTween!.evaluate(_zoomAnimation));
  Matrix4Tween? _zoomTween;
  TapDownDetails? _doubleTap;
  bool _fullRequested = false;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed == _zoomed) return;
      setState(() => _zoomed = zoomed);
      widget.onZoom(zoomed);
    });
  }

  @override
  void dispose() {
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
    if (widget.loadFull) _fullRequested = true;
    final full = _fullRequested ? file.fullUrl : null;
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTap = details,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        // Panning at 1x would take horizontal drags from the PageView.
        panEnabled: _zoomed,
        minScale: 1,
        maxScale: 6,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (file.thumbnailUrl != null)
                Image(
                  image: netImageProvider(file.thumbnailUrl!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              if (full != null && full != file.thumbnailUrl)
                Image(
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
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 40,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A video with Chewie's controls. It only plays while [active].
class _VideoPage extends StatefulWidget {
  const _VideoPage({
    super.key,
    required this.url,
    required this.active,
    required this.autoplay,
  });

  final String url;
  final bool active;
  final bool autoplay;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(_VideoPage oldWidget) {
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
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white70)),
      );
    }
    final chewie = _chewie;
    if (chewie == null) return const Center(child: CircularProgressIndicator());
    return SafeArea(child: Chewie(controller: chewie));
  }
}
