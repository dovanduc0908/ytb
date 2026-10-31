import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'adjustment_indicator.dart';

class PlayerOverlay extends StatefulWidget {
  const PlayerOverlay({
    super.key,
    required this.video,
    required this.visible,
    required this.fullscreen,
    required this.state,
    required this.loading,
    required this.onToggle,
    required this.onPlay,
    required this.onSeek,
    required this.onFullscreen,
    required this.onSettings,
    required this.formatTime,
    this.onMinimize,
    this.onPrevious,
    this.onNext,
    this.onSpeed,
    this.onAdjust,
    this.onLock,
    this.onRotate,
    this.locked,
  });
  final Widget video;
  final bool visible, fullscreen, loading;
  final Map<String, dynamic> state;
  final VoidCallback onToggle, onPlay, onFullscreen, onSettings;
  final ValueChanged<int> onSeek;
  final String Function(num) formatTime;

  final VoidCallback? onMinimize;
  final VoidCallback? onPrevious, onNext;
  final ValueChanged<double>? onSpeed;
  final Future<double> Function(String, double)? onAdjust;
  final ValueChanged<bool>? onLock;
  final VoidCallback? onRotate;
  final bool? locked;
  @override
  State<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends State<PlayerOverlay> {
  Widget get video => widget.video;
  bool get visible => widget.visible;
  bool get fullscreen => widget.fullscreen;
  bool get loading => widget.loading;
  Map<String, dynamic> get state => widget.state;
  VoidCallback get onToggle => widget.onToggle;
  VoidCallback get onPlay => widget.onPlay;
  ValueChanged<int> get onSeek => widget.onSeek;
  VoidCallback get onFullscreen => widget.onFullscreen;
  VoidCallback get onSettings => widget.onSettings;
  String Function(num) get formatTime => widget.formatTime;
  bool localLocked = false;
  bool get locked => widget.locked ?? localLocked;
  bool lockButtonVisible = false, pinching = false;
  double zoom = 1, startZoom = 1, rate = 1, dragDown = 0;
  Offset pan = Offset.zero, startPan = Offset.zero, origin = Offset.zero;
  String? mode, feedback;
  int? seekTarget;
  double? sliderPreview;
  Timer? feedbackTimer, lockTimer, meterTimer;
  String? meterKind;
  double meterValue = 0;
  double? heldSpeed;
  int meterGeneration = 0;
  final Set<int> activePointers = {};
  bool systemEdgeGesture = false;

  Widget trackGestureStart(BuildContext context, Widget child) => Listener(
    onPointerDown: (event) {
      if (activePointers.isEmpty) {
        final media = MediaQuery.of(context);
        // Capture the original touch before ScaleGestureRecognizer crosses its
        // slop threshold. Keep this decision until every finger is released.
        final topEdge = math.max(
          48.0,
          math.max(media.viewPadding.top, media.systemGestureInsets.top),
        );
        systemEdgeGesture = fullscreen && event.position.dy < topEdge;
      }
      activePointers.add(event.pointer);
    },
    onPointerUp: (event) => activePointers.remove(event.pointer),
    onPointerCancel: (event) => activePointers.remove(event.pointer),
    child: child,
  );
  void showMeter(String kind, double value) {
    meterTimer?.cancel();
    setState(() {
      meterKind = kind;
      meterValue = value;
      feedback = null;
    });
  }

  void hideMeterSoon() {
    meterTimer?.cancel();
    meterTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          meterKind = null;
          meterGeneration++;
        });
      }
    });
  }

  void toggleLockButton() {
    lockTimer?.cancel();
    setState(() => lockButtonVisible = !lockButtonVisible);
    if (lockButtonVisible) {
      lockTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => lockButtonVisible = false);
      });
    }
  }

  void hint(String value) {
    feedbackTimer?.cancel();
    setState(() => feedback = value);
    feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => feedback = null);
    });
  }

  @override
  void dispose() {
    feedbackTimer?.cancel();
    lockTimer?.cancel();
    meterTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      trackGestureStart(context, buildOverlay(context));

  Widget buildOverlay(BuildContext context) {
    final duration = (state['duration'] as num? ?? 0).toDouble();
    final position = (state['position'] as num? ?? 0).toDouble().clamp(
      0,
      duration > 0 ? duration : 1,
    );
    final show =
        !locked &&
        (visible ||
            loading ||
            state['playing'] != true ||
            sliderPreview != null);
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: locked
            ? null
            : (event) {
                meterTimer?.cancel();
                meterGeneration++;
                if (meterKind != null) setState(() => meterKind = null);
                origin = event.localFocalPoint;
                startZoom = zoom;
                startPan = pan;
                pinching = event.pointerCount > 1;
                mode = null;
                seekTarget = null;
                dragDown = 0;
                rate = (state['speed'] as num? ?? 1).toDouble();
              },
        onScaleUpdate: locked
            ? null
            : (event) {
                if (systemEdgeGesture) return;
                if (event.pointerCount > 1 || pinching) {
                  if (!fullscreen) return;
                  pinching = true;
                  setState(() {
                    zoom = (startZoom * event.scale).clamp(1.0, 4.0);
                    final offset = startPan + event.localFocalPoint - origin;
                    pan = Offset(
                      offset.dx.clamp(
                        -box.maxWidth * (zoom - 1) / 2,
                        box.maxWidth * (zoom - 1) / 2,
                      ),
                      offset.dy.clamp(
                        -box.maxHeight * (zoom - 1) / 2,
                        box.maxHeight * (zoom - 1) / 2,
                      ),
                    );
                  });
                  hint('Thu phóng ${zoom.toStringAsFixed(1)}×');
                  return;
                }
                final delta = event.localFocalPoint - origin;
                if (delta.distance < 12) return;
                if (!fullscreen) {
                  mode = 'minimize';
                  dragDown = delta.dy;
                  return;
                }
                mode ??= zoom > 1.01
                    ? 'pan'
                    : delta.dx.abs() > delta.dy.abs()
                    ? 'seek'
                    : origin.dy > box.maxHeight * .60 &&
                          origin.dx > box.maxWidth * .32 &&
                          origin.dx < box.maxWidth * .68
                    ? 'speed'
                    : origin.dx < box.maxWidth / 2
                    ? 'brightness'
                    : 'volume';
                if (mode == 'pan') {
                  setState(
                    () => pan = Offset(
                      (startPan.dx + delta.dx).clamp(
                        -box.maxWidth * (zoom - 1) / 2,
                        box.maxWidth * (zoom - 1) / 2,
                      ),
                      (startPan.dy + delta.dy).clamp(
                        -box.maxHeight * (zoom - 1) / 2,
                        box.maxHeight * (zoom - 1) / 2,
                      ),
                    ),
                  );
                } else if (mode == 'seek' && !loading && duration > 0) {
                  feedbackTimer?.cancel();
                  setState(() {
                    feedback = null;
                    seekTarget = (position + delta.dx / box.maxWidth * 120000)
                        .clamp(0, duration)
                        .toInt();
                  });
                } else if (mode == 'speed') {
                  final next =
                      ((rate - delta.dy / box.maxHeight * 3.25) * 4).round() /
                      4;
                  final value = next.clamp(.25, 4.0).toDouble();
                  widget.onSpeed?.call(value);
                  showMeter('speed', value);
                } else if (mode == 'volume' || mode == 'brightness') {
                  final kind = mode!;
                  final change = -event.focalPointDelta.dy / box.maxHeight;
                  if (change != 0) {
                    final generation = meterGeneration;
                    widget.onAdjust
                        ?.call(kind, change)
                        .then((value) {
                          if (mounted &&
                              !locked &&
                              generation == meterGeneration) {
                            showMeter(kind, value);
                            if (mode == null) hideMeterSoon();
                          }
                        })
                        .catchError((Object error) {
                          if (mounted) {
                            hint('Chưa thể điều chỉnh. Hãy thử lại.');
                          }
                        });
                  }
                }
              },
        onScaleEnd: locked
            ? null
            : (event) {
                if (systemEdgeGesture) return;
                if (seekTarget != null) {
                  onSeek(seekTarget!);
                  setState(() => seekTarget = null);
                }
                if (mode == 'volume' ||
                    mode == 'brightness' ||
                    mode == 'speed') {
                  mode = null;
                  hideMeterSoon();
                }
                if (mode == 'minimize' && dragDown > 80) {
                  widget.onMinimize?.call();
                }
              },
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.translate(
                offset: pan,
                child: Transform.scale(scale: zoom, child: video),
              ),
              Positioned.fill(
                child: AbsorbPointer(
                  absorbing: locked,
                  child: SeekGestureSurface(
                    position: position.toInt(),
                    duration: duration.toInt(),
                    enabled: !locked && !loading && duration > 0,
                    onToggle: onToggle,
                    onSeek: onSeek,
                    onHoldStart: () {
                      heldSpeed = (state['speed'] as num? ?? 1).toDouble();
                      widget.onSpeed?.call(2.0);
                      hint('Giữ để phát 2×');
                    },
                    onHoldEnd: () {
                      if (heldSpeed != null) widget.onSpeed?.call(heldSpeed!);
                      heldSpeed = null;
                    },
                  ),
                ),
              ),
              if ((state['captionText'] as String? ?? '').isNotEmpty)
                Positioned(
                  left: box.maxWidth * .1,
                  right: box.maxWidth * .1,
                  bottom: show ? (fullscreen ? 84 : 50) : 24,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          state['captionText'] as String,
                          key: const Key('subtitle-text'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: fullscreen ? 19 : 15,
                            fontWeight: FontWeight.w600,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 3),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (!locked && (loading || state['buffering'] == true))
                const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              IgnorePointer(
                ignoring: !show,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: show ? 1 : 0,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black54,
                                Colors.transparent,
                                Colors.black87,
                              ],
                              stops: [0, .45, 1],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: fullscreen ? 12 : 0,
                        left: 8,
                        right: 8,
                        child: Row(
                          children: [
                            if (fullscreen)
                              IconButton(
                                tooltip: 'Thoát toàn màn hình',
                                onPressed: onFullscreen,
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: Colors.white,
                                ),
                              ),
                            const Spacer(),
                            if (fullscreen && widget.onRotate != null)
                              IconButton(
                                tooltip: 'Xoay ngang/dọc',
                                onPressed: widget.onRotate,
                                icon: const Icon(
                                  Icons.screen_rotation,
                                  color: Colors.white,
                                ),
                              ),
                            if (fullscreen)
                              IconButton(
                                tooltip: 'Khóa màn hình',
                                onPressed: () {
                                  feedbackTimer?.cancel();
                                  lockTimer?.cancel();
                                  meterTimer?.cancel();
                                  meterGeneration++;
                                  setState(() {
                                    lockButtonVisible = false;
                                    feedback = null;
                                    meterKind = null;
                                    seekTarget = null;
                                    sliderPreview = null;
                                  });
                                  localLocked = true;
                                  widget.onLock?.call(true);
                                },
                                icon: const Icon(
                                  Icons.lock_open,
                                  color: Colors.white,
                                ),
                              ),
                            if (fullscreen && zoom > 1)
                              IconButton(
                                tooltip: 'Đặt lại thu phóng',
                                onPressed: () => setState(() {
                                  zoom = 1;
                                  pan = Offset.zero;
                                }),
                                icon: const Icon(
                                  Icons.fit_screen,
                                  color: Colors.white,
                                ),
                              ),
                            IconButton(
                              tooltip: 'Tùy chọn phát',
                              onPressed: onSettings,
                              icon: const Icon(
                                Icons.settings_outlined,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!loading && state['buffering'] != true)
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Video trước',
                                onPressed: widget.onPrevious,
                                icon: const Icon(
                                  Icons.skip_previous,
                                  size: 30,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 24),
                              IconButton(
                                tooltip: state['playing'] == true
                                    ? 'Tạm dừng'
                                    : 'Phát video',
                                onPressed: onPlay,
                                icon: Icon(
                                  state['playing'] == true
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  size: 48,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 24),
                              IconButton(
                                tooltip: 'Video tiếp theo',
                                onPressed: widget.onNext,
                                icon: const Icon(
                                  Icons.skip_next,
                                  size: 30,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Positioned(
                        bottom: fullscreen ? 12 : 0,
                        left: 4,
                        right: 4,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: SizedBox(
                                height: 40,
                                child: Row(
                                  children: [
                                    Text(
                                      '${formatTime(sliderPreview ?? seekTarget ?? position)} / ${formatTime(duration)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: fullscreen
                                          ? 'Thu nhỏ'
                                          : 'Toàn màn hình',
                                      onPressed: onFullscreen,
                                      icon: Icon(
                                        fullscreen
                                            ? Icons.fullscreen_exit
                                            : Icons.fullscreen,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 24,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  activeTrackColor: const Color(0xffff315a),
                                  inactiveTrackColor: Colors.white60,
                                  thumbColor: Colors.white,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 16,
                                  ),
                                ),
                                child: SeekSlider(
                                  position: (seekTarget ?? position).toDouble(),
                                  duration: duration,
                                  onSeek: onSeek,
                                  onPreview: (value) =>
                                      setState(() => sliderPreview = value),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!locked &&
                  feedback != null &&
                  sliderPreview == null &&
                  seekTarget == null)
                Positioned(
                  top: fullscreen ? 65 : 12,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.black87,
                        child: Text(
                          feedback!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (!locked && meterKind != null)
                if (meterKind == 'speed')
                  Positioned(
                    bottom: fullscreen ? 64 : 36,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: AdjustmentIndicator(
                          kind: meterKind!,
                          value: meterValue,
                        ),
                      ),
                    ),
                  )
                else
                  Positioned(
                    left: meterKind == 'brightness'
                        ? (box.maxWidth / 2 - 180).clamp(12.0, double.infinity)
                        : null,
                    right: meterKind == 'volume'
                        ? (box.maxWidth / 2 - 180).clamp(12.0, double.infinity)
                        : null,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: AdjustmentIndicator(
                          kind: meterKind!,
                          value: meterValue,
                        ),
                      ),
                    ),
                  ),
              if (!locked && !show && seekTarget != null && duration > 0)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: fullscreen ? 20 : 8,
                  child: IgnorePointer(
                    child: LinearProgressIndicator(
                      key: const Key('seek-gesture-progress'),
                      value: (seekTarget! / duration).clamp(0.0, 1.0),
                      minHeight: 2,
                      color: Colors.red,
                      backgroundColor: Colors.white38,
                    ),
                  ),
                ),
              if (!locked && (sliderPreview != null || seekTarget != null))
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: sliderPreview != null
                      ? (fullscreen ? 58 : 44)
                      : (fullscreen ? 45 : 32),
                  child: IgnorePointer(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final target = sliderPreview ?? seekTarget!.toDouble();
                        const labelWidth = 140.0;
                        final available = constraints.maxWidth;
                        final ratio = duration > 0
                            ? (target / duration).clamp(0.0, 1.0)
                            : 0.0;
                        final center =
                            20 +
                            ratio *
                                (available - 40).clamp(0.0, double.infinity);
                        final left = (center - labelWidth / 2).clamp(
                          0.0,
                          (available - labelWidth).clamp(0.0, double.infinity),
                        );
                        return SizedBox(
                          height: 38,
                          child: Stack(
                            children: [
                              Positioned(
                                left: left,
                                width: labelWidth.clamp(0.0, available),
                                child: Center(
                                  child: Container(
                                    key: const Key('seek-time-preview'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${formatTime(target)}  ${target >= position ? '+' : '-'}${formatTime((target - position).abs())}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (locked)
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('locked-video-surface'),
                    behavior: HitTestBehavior.opaque,
                    onTap: toggleLockButton,
                    child: Semantics(
                      label: 'Hiện hoặc ẩn nút mở khóa',
                      button: true,
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                ),
              if (locked && lockButtonVisible)
                Positioned(
                  right: 16,
                  top: 16,
                  child: IconButton.filled(
                    tooltip: 'Mở khóa màn hình',
                    onPressed: () {
                      lockTimer?.cancel();
                      setState(() {
                        lockButtonVisible = false;
                      });
                      localLocked = false;
                      widget.onLock?.call(false);
                    },
                    icon: const Icon(Icons.lock),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Preview the thumb locally while dragging, then issue one native seek.
class SeekSlider extends StatefulWidget {
  const SeekSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.onPreview,
  });
  final ValueChanged<double?>? onPreview;
  final double position, duration;
  final ValueChanged<int> onSeek;
  @override
  State<SeekSlider> createState() => _SeekSliderState();
}

class _SeekSliderState extends State<SeekSlider> {
  double? dragging;
  @override
  Widget build(BuildContext context) => Slider(
    value: (dragging ?? widget.position).clamp(
      0,
      widget.duration > 0 ? widget.duration : 1,
    ),
    max: widget.duration > 0 ? widget.duration : 1,
    onChangeStart: widget.duration > 0
        ? (value) {
            setState(() => dragging = value);
            widget.onPreview?.call(value);
          }
        : null,
    onChanged: widget.duration > 0
        ? (value) {
            setState(() => dragging = value);
            widget.onPreview?.call(value);
          }
        : null,
    onChangeEnd: widget.duration > 0
        ? (value) {
            setState(() => dragging = null);
            widget.onPreview?.call(null);
            widget.onSeek(value.toInt());
          }
        : null,
  );
}

class SeekGestureSurface extends StatefulWidget {
  const SeekGestureSurface({
    super.key,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onToggle,
    required this.onSeek,
    this.onHoldStart,
    this.onHoldEnd,
  });
  final VoidCallback? onHoldStart, onHoldEnd;
  final int position, duration;
  final bool enabled;
  final VoidCallback onToggle;
  final ValueChanged<int> onSeek;
  @override
  State<SeekGestureSurface> createState() => _SeekGestureSurfaceState();
}

class _SeekGestureSurfaceState extends State<SeekGestureSurface> {
  Timer? commit, feedback;
  int? target;
  int seconds = 0;
  double x = 0;
  void seek(double width) {
    if (!widget.enabled || width <= 0 || (x > width * .42 && x < width * .58)) {
      return;
    }
    final delta = x < width / 2 ? -10 : 10;
    final next = ((target ?? widget.position) + delta * 1000).clamp(
      0,
      widget.duration,
    );
    setState(() {
      target = next;
      seconds = seconds.sign == delta.sign ? seconds + delta : delta;
    });
    commit?.cancel();
    feedback?.cancel();
    commit = Timer(const Duration(milliseconds: 100), () {
      if (mounted && widget.enabled) widget.onSeek(target!);
    });
    feedback = Timer(const Duration(milliseconds: 750), () {
      if (mounted) {
        setState(() {
          target = null;
          seconds = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    commit?.cancel();
    feedback?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onToggle,
      onDoubleTapDown: (event) => x = event.localPosition.dx,
      onDoubleTap: () => seek(box.maxWidth),
      onLongPressStart: widget.enabled
          ? (_) => widget.onHoldStart?.call()
          : null,
      onLongPressEnd: widget.enabled ? (_) => widget.onHoldEnd?.call() : null,
      child: Semantics(
        label: 'Hiện điều khiển video',
        button: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.transparent),
            if (seconds != 0)
              Align(
                alignment: seconds < 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Text(
                      '${seconds > 0 ? '+' : ''}${seconds}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
