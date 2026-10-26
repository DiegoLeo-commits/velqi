import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:velqi/ui/player/player_controller.dart';

import '../../widgets/loader.dart';

/// A button that animates between a play and pause icon.
///
/// It also shows a loading indicator when the audio is in a loading state.
class AnimatedPlayButton extends StatefulWidget {
  /// size of the icon.
  final double iconSize;

  /// optional icon color (defaults to theme onSurface).
  final Color? color;

  const AnimatedPlayButton({super.key, this.iconSize = 40.0, this.color});

  @override
  State<AnimatedPlayButton> createState() => _AnimatedPlayButtonState();
}

class _AnimatedPlayButtonState extends State<AnimatedPlayButton>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  /// Quick scale "pop" on every tap — the button springs from 82% back to
  /// 100% with a slight overshoot (easeOutBack), giving pause/play a
  /// tactile bounce instead of an instant icon swap.
  late final AnimationController _bump;
  late final Animation<double> _bumpScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bump = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1.0,
    );
    _bumpScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _bump, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(builder: (controller) {
      final buttonState = controller.buttonState.value;
      final isPlaying = buttonState == PlayButtonState.playing;
      final isLoading = buttonState == PlayButtonState.loading;

      if (isPlaying) {
        _controller.forward();
      } else if (!isLoading) {
        _controller.reverse();
      }

      return ScaleTransition(
        scale: _bumpScale,
        child: IconButton(
          iconSize: widget.iconSize,
          color: widget.color,
          onPressed: () {
            // Tactile bounce on desktop only (platform lock): on Android
            // the user prefers a flat, instant button.
            if (!GetPlatform.isAndroid) _bump.forward(from: 0);
            isPlaying ? controller.pause() : controller.play();
          },
          icon: isLoading
              ? const LoadingIndicator(
                  dimension: 20,
                )
              : AnimatedIcon(
                  icon: AnimatedIcons.play_pause,
                  progress: _controller,
                ),
        ),
      );
    });
  }
}
