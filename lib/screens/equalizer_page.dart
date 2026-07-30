import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/constants/app_constants.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/models/equalizer_models.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/widgets/mini_player_bottom_space.dart';

class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key});

  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
  EqualizerParametersInfo? _params;
  List<double> _gains = [];
  bool _enabled = equalizerEnabled.value;
  bool _isLoading = true;
  String? _activePreset;

  // Preset IDs
  static const List<String> _presetIds = [
    'balanced',
    'bassBoost',
    'trebleBoost',
    'vocal',
    'rock',
    'pop',
    'electronic',
  ];

  // Get localized name for a preset
  String _getPresetLocalizedName(BuildContext context, String presetId) {
    switch (presetId) {
      case 'balanced':
        return context.l10n!.equalizerPresetBalanced;
      case 'bassBoost':
        return context.l10n!.equalizerPresetBassBoost;
      case 'trebleBoost':
        return context.l10n!.equalizerPresetTrebleBoost;
      case 'vocal':
        return context.l10n!.equalizerPresetVocal;
      case 'rock':
        return context.l10n!.equalizerPresetRock;
      case 'pop':
        return context.l10n!.equalizerPresetPop;
      case 'electronic':
        return context.l10n!.equalizerPresetElectronic;
      default:
        return presetId;
    }
  }

  // Get preset gains for the current number of bands
  List<double> _getPresetGains(String preset) {
    final bandCount = _params?.bands.length ?? 0;
    if (bandCount == 0) return [];

    // Normalize band index to 0-1 range for frequency distribution
    final normalizedGains = List<double>.generate(bandCount, (i) {
      final position = bandCount > 1 ? i / (bandCount - 1) : 0.0;

      switch (preset) {
        case 'balanced':
          // Neutral, flat response
          return 0.0;

        case 'bassBoost':
          // Strong bass, reduced highs
          if (position < 0.33) return 8.0;
          if (position < 0.66) return 3.0;
          return -2.0;

        case 'trebleBoost':
          // Strong treble, reduced lows
          if (position < 0.33) return -2.0;
          if (position < 0.66) return 2.0;
          return 8.0;

        case 'vocal':
          // Mid-range boost for clear vocals
          if (position < 0.2) return 2.0;
          if (position < 0.5) return 6.0;
          if (position < 0.8) return 4.0;
          return 1.0;

        case 'rock':
          // Powerful bass + presence peak
          if (position < 0.25) return 7.0;
          if (position < 0.5) return 2.0;
          if (position < 0.75) return 4.0;
          return 6.0;

        case 'pop':
          // Balanced with slight mid boost
          if (position < 0.3) return 3.0;
          if (position < 0.6) return 4.0;
          return 2.0;

        case 'electronic':
          // Punchy bass + presence peak
          if (position < 0.2) return 9.0;
          if (position < 0.5) return -1.0;
          if (position < 0.8) return 3.0;
          return 7.0;

        default:
          return 0.0;
      }
    });

    return normalizedGains;
  }

  Future<void> _applyPreset(String preset) async {
    final presetGains = _getPresetGains(preset);
    for (var i = 0; i < presetGains.length; i++) {
      await audioHandler.setEqualizerBandGain(i, presetGains[i]);
    }
    if (!mounted) return;
    setState(() {
      _gains = presetGains;
      _activePreset = preset;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadEqualizer();
  }

  Future<void> _loadEqualizer() async {
    if (!audioHandler.isEqualizerSupported) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final params = await audioHandler.getEqualizerParameters();
      if (!mounted) return;

      if (params != null) {
        setState(() {
          _params = params;
          _gains = params.bands.map((band) => band.gain).toList();
          _enabled = equalizerEnabled.value;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e, stackTrace) {
      logger.log(
        'Failed to load equalizer page',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatFrequency(double hz) {
    if (hz >= 1000) {
      final kHz = hz / 1000;
      return kHz >= 10 || kHz == kHz.roundToDouble()
          ? '${kHz.round()}kHz'
          : '${kHz.toStringAsFixed(1)}kHz';
    }
    return '${hz.round()}Hz';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSupported = audioHandler.isEqualizerSupported;

    return Scaffold(
      appBar: AppBar(
        // title: Text(context.l10n!.equalizer),
        actions: [
          if (isSupported)
            IconButton(
              icon: const Icon(FluentIcons.arrow_clockwise_24_filled),
              tooltip: context.l10n!.equalizerResetBands,
              onPressed: () async {
                await audioHandler.resetEqualizerBands();
                final params = _params;
                if (!mounted || params == null) return;
                setState(() {
                  _gains = List<double>.filled(params.bands.length, 0);
                  _activePreset = null;
                });
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _params == null
          ? Center(
              child: Padding(
                padding: commonSingleChildScrollViewPadding,
                child: Text(
                  isSupported
                      ? context.l10n!.equalizerInitFailed
                      : context.l10n!.equalizerAndroidOnly,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: commonSingleChildScrollViewPadding,
              children: [
                // Enable/Disable — simple label + switch
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n!.equalizer,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      Switch.adaptive(
                        value: _enabled,
                        onChanged: (value) async {
                          await audioHandler.setEqualizerEnabled(value);
                          if (!mounted) return;
                          setState(() => _enabled = value);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Presets Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n!.equalizer,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _presetIds.map((presetId) {
                          final isActive = _activePreset == presetId;
                          return FilledButton(
                            onPressed: () => _applyPreset(presetId),
                            style: FilledButton.styleFrom(
                              backgroundColor: isActive
                                  ? colorScheme.primary
                                  : colorScheme.surfaceContainerHighest,
                              foregroundColor: isActive
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurface,
                              elevation: isActive ? 2 : 0,
                            ),
                            child: Text(
                              _getPresetLocalizedName(context, presetId),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Bands Section — vertical graphic EQ
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        context.l10n!.equalizerBands,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _GraphicEqualizerBands(
                      bands: _params!.bands,
                      gains: _gains,
                      minDecibels: _params!.minDecibels,
                      maxDecibels: _params!.maxDecibels,
                      formatFrequency: _formatFrequency,
                      onChanged: (index, value) {
                        setState(() {
                          _gains[index] = value;
                          _activePreset = null;
                        });
                      },
                      onChangeEnd: (index, value) async {
                        await audioHandler.setEqualizerBandGain(index, value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const MiniPlayerBottomSpace(),
              ],
            ),
    );
  }
}

/// Vertical graphic-EQ layout: dB scale on the left, band sliders across,
/// frequency labels underneath — matching a classic 5-band EQ panel.
class _GraphicEqualizerBands extends StatelessWidget {
  const _GraphicEqualizerBands({
    required this.bands,
    required this.gains,
    required this.minDecibels,
    required this.maxDecibels,
    required this.formatFrequency,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final List<EqualizerBandInfo> bands;
  final List<double> gains;
  final double minDecibels;
  final double maxDecibels;
  final String Function(double hz) formatFrequency;
  final void Function(int index, double value) onChanged;
  final void Function(int index, double value) onChangeEnd;

  static const double _sliderHeight = 220;
  static const double _labelColumnWidth = 44;
  static const double _freqLabelHeight = 28;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.85),
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    );

    // Map 0 dB to Alignment.y (-1 top … 1 bottom).
    final zeroY =
        -1.0 + 2.0 * ((maxDecibels - 0) / (maxDecibels - minDecibels));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // dB scale
          SizedBox(
            width: _labelColumnWidth,
            height: _sliderHeight,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Text('+${maxDecibels.round()}db', style: labelStyle),
                ),
                Align(
                  alignment: Alignment(-1, zeroY.clamp(-1.0, 1.0)),
                  child: Text('0db', style: labelStyle),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Text('${minDecibels.round()}db', style: labelStyle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Band sliders
          Expanded(
            child: SizedBox(
              height: _sliderHeight + _freqLabelHeight,
              child: Row(
                children: List.generate(bands.length, (index) {
                  return Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: _sliderHeight,
                          child: _VerticalEqSlider(
                            value: gains[index].clamp(minDecibels, maxDecibels),
                            min: minDecibels,
                            max: maxDecibels,
                            onChanged: (v) => onChanged(index, v),
                            onChangeEnd: (v) => onChangeEnd(index, v),
                          ),
                        ),
                        SizedBox(
                          height: _freqLabelHeight,
                          child: Center(
                            child: Text(
                              formatFrequency(bands[index].centerFrequency),
                              style: labelStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalEqSlider extends StatefulWidget {
  const _VerticalEqSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_VerticalEqSlider> createState() => _VerticalEqSliderState();
}

class _VerticalEqSliderState extends State<_VerticalEqSlider> {
  static const double _thumbHeight = 28;
  static const double _thumbWidth = 14;
  static const double _trackWidth = 3;

  double? _dragValue;

  double _valueToY(double value, double height) {
    final t = ((widget.max - value) / (widget.max - widget.min)).clamp(
      0.0,
      1.0,
    );
    final usable = height - _thumbHeight;
    return t * usable;
  }

  double _yToValue(double localY, double height) {
    final usable = height - _thumbHeight;
    final t = ((localY - _thumbHeight / 2) / usable).clamp(0.0, 1.0);
    return widget.max - t * (widget.max - widget.min);
  }

  void _handleDrag(Offset localPosition, double height) {
    final next = _yToValue(localPosition.dy, height);
    _dragValue = next;
    widget.onChanged(next);
  }

  void _commitAt(Offset localPosition, double height) {
    final next = _yToValue(localPosition.dy, height);
    _dragValue = null;
    widget.onChanged(next);
    widget.onChangeEnd(next);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final thumbColor = colorScheme.primary;
    final deepColor = Color.lerp(
      colorScheme.primary,
      const Color(0xFF312E81),
      0.65,
    )!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        final thumbTop = _valueToY(widget.value, height);
        final trackBottom = height - _thumbHeight / 2;
        final activeTop = thumbTop + _thumbHeight / 2;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) => _handleDrag(d.localPosition, height),
          onVerticalDragUpdate: (d) => _handleDrag(d.localPosition, height),
          onVerticalDragEnd: (_) {
            widget.onChangeEnd(_dragValue ?? widget.value);
            _dragValue = null;
          },
          onTapDown: (d) => _commitAt(d.localPosition, height),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Inactive track (full height, thin)
                Positioned(
                  top: _thumbHeight / 2,
                  bottom: _thumbHeight / 2,
                  child: Container(
                    width: _trackWidth,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(_trackWidth),
                    ),
                  ),
                ),
                // Active track (bottom → thumb) with neon gradient
                Positioned(
                  top: activeTop,
                  bottom: height - trackBottom,
                  child: Container(
                    width: _trackWidth,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_trackWidth),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [thumbColor, deepColor],
                      ),
                    ),
                  ),
                ),
                // Pill thumb
                Positioned(
                  top: thumbTop,
                  child: Container(
                    width: _thumbWidth,
                    height: _thumbHeight,
                    decoration: BoxDecoration(
                      color: thumbColor,
                      borderRadius: BorderRadius.circular(_thumbWidth),
                      boxShadow: [
                        BoxShadow(
                          color: thumbColor.withValues(alpha: 0.45),
                          blurRadius: 10,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
