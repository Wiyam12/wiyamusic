/// Cross-platform equalizer band description used by the EQ UI.
class EqualizerBandInfo {
  const EqualizerBandInfo({
    required this.index,
    required this.centerFrequency,
    required this.gain,
  });

  final int index;
  final double centerFrequency;
  final double gain;
}

/// Cross-platform equalizer parameters used by the EQ UI.
class EqualizerParametersInfo {
  const EqualizerParametersInfo({
    required this.minDecibels,
    required this.maxDecibels,
    required this.bands,
  });

  final double minDecibels;
  final double maxDecibels;
  final List<EqualizerBandInfo> bands;
}
