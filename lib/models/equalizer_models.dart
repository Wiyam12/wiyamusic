/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     WiyaMusic is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 */

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
