import 'package:flutter/material.dart';

class PlayerOverlay extends StatelessWidget {
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
  });
  final Widget video;
  final bool visible, fullscreen, loading;
  final Map<String, dynamic> state;
  final VoidCallback onToggle, onPlay, onFullscreen, onSettings;
  final ValueChanged<int> onSeek;
  final String Function(num) formatTime;

  @override
  Widget build(BuildContext context) {
    final duration = (state['duration'] as num? ?? 0).toDouble();
    final position = (state['position'] as num? ?? 0).toDouble().clamp(
      0,
      duration > 0 ? duration : 1,
    );
    final show = visible || loading || state['playing'] != true;
    return Stack(
      fit: StackFit.expand,
      children: [
        video,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Semantics(
              label: 'Hiện điều khiển video',
              button: true,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
        ),
        if (loading || state['buffering'] == true)
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
                          tooltip: 'Lùi 10 giây',
                          onPressed: () => onSeek(
                            (position - 10000).clamp(0, duration).toInt(),
                          ),
                          icon: const Icon(
                            Icons.replay_10,
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
                          tooltip: 'Tới 10 giây',
                          onPressed: () => onSeek(
                            (position + 10000).clamp(0, duration).toInt(),
                          ),
                          icon: const Icon(
                            Icons.forward_10,
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
                        child: Row(
                          children: [
                            Text(
                              '${formatTime(position)} / ${formatTime(duration)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: fullscreen ? 'Thu nhỏ' : 'Toàn màn hình',
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
                      SizedBox(
                        height: 18,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                          ),
                          child: SeekSlider(
                            position: position.toDouble(),
                            duration: duration,
                            onSeek: onSeek,
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
      ],
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
  });
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
        ? (value) => setState(() => dragging = value)
        : null,
    onChanged: widget.duration > 0
        ? (value) => setState(() => dragging = value)
        : null,
    onChangeEnd: widget.duration > 0
        ? (value) {
            setState(() => dragging = null);
            widget.onSeek(value.toInt());
          }
        : null,
  );
}
