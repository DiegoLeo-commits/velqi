import 'package:flutter/material.dart';

/// Velqi mascot poses for different app states.
enum VelqiPose {
  idle,        // P01 - sitting/relaxing → empty states, no results
  headphones,  // P03 - with headphones → loading, searching
  guitar,      // P03 copia - playing guitar → settings, about
  tank,        // P06 - in tank → error, connection failed
  running,     // P0s - running → downloading, progress
  splash,      // ICON_Velqi1 - splash screen variant
}

/// Reusable Velqi mascot widget.
/// Displays the appropriate Velqi character based on app state.
class VelqiMascot extends StatelessWidget {
  final VelqiPose pose;
  final double size;
  final String? customText;
  final bool showText;

  const VelqiMascot({
    super.key,
    required this.pose,
    this.size = 160,
    this.customText,
    this.showText = true,
  });

  String get _assetPath {
    switch (pose) {
      case VelqiPose.idle:
        return 'assets/images/velqi_idle.png';
      case VelqiPose.headphones:
        return 'assets/images/velqi_headphones.png';
      case VelqiPose.guitar:
        return 'assets/images/velqi_guitar.png';
      case VelqiPose.tank:
        return 'assets/images/velqi_tank.png';
      case VelqiPose.running:
        return 'assets/images/velqi_running.png';
      case VelqiPose.splash:
        return 'assets/images/velqi_splash.png';
    }
  }

  String get _defaultText {
    switch (pose) {
      case VelqiPose.idle:
        return 'Nada por aquí...';
      case VelqiPose.headphones:
        return 'Buscando música...';
      case VelqiPose.guitar:
        return '¡Rock and roll!';
      case VelqiPose.tank:
        return 'Sin conexión';
      case VelqiPose.running:
        return 'Descargando...';
      case VelqiPose.splash:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = customText ?? _defaultText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mascot image with subtle shadow
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.2),
            boxShadow: [
              BoxShadow(
                color: theme.primaryColor.withOpacity(0.15),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.2),
            child: Image.asset(
              _assetPath,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              color: theme.brightness == Brightness.light
                  ? Colors.black
                  : null,
              colorBlendMode: theme.brightness == Brightness.light
                  ? BlendMode.srcIn
                  : null,
              errorBuilder: (_, __, ___) => Container(
                color: theme.colorScheme.surface,
                child: Icon(
                  Icons.music_note,
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                  size: size * 0.4,
                ),
              ),
            ),
          ),
        ),
        // Optional text below mascot
        if (showText && text.isNotEmpty) ...[
          SizedBox(height: size * 0.12),
          Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Pre-built empty state with Velqi mascot.
/// Use when a list/search has no results.
class VelqiEmptyState extends StatelessWidget {
  final String? message;
  final double mascotSize;

  const VelqiEmptyState({
    super.key,
    this.message,
    this.mascotSize = 140,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: VelqiMascot(
          pose: VelqiPose.idle,
          size: mascotSize,
          customText: message,
        ),
      ),
    );
  }
}

/// Pre-built error state with Velqi mascot.
/// Use when connection fails or an error occurs.
class VelqiErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  final double mascotSize;

  const VelqiErrorState({
    super.key,
    this.message,
    this.onRetry,
    this.mascotSize = 140,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VelqiMascot(
              pose: VelqiPose.tank,
              size: mascotSize,
              customText: message ?? 'Sin conexión',
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pre-built loading state with Velqi mascot.
/// Use when content is loading or searching.
class VelqiLoadingState extends StatelessWidget {
  final String? message;
  final double mascotSize;

  const VelqiLoadingState({
    super.key,
    this.message,
    this.mascotSize = 120,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: VelqiMascot(
          pose: VelqiPose.headphones,
          size: mascotSize,
          customText: message,
        ),
      ),
    );
  }
}
