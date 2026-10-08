/// Ripcord `RipLogScaleDbSlider` ka Dart port.
/// Range: 0 dB .. +24 dB, default 0 dB. Slider LOG-scale (neeche fine, upar tez).
/// Formula: gain_linear = 10^(dB/20). +24dB = ~15.85x
library gain;

import 'dart:math' as math;

/// dB (0..24) -> linear amplitude multiplier
double dbToLinear(double db) {
  final clamped = db.clamp(0.0, 24.0);
  return math.pow(10.0, clamped / 20.0).toDouble();
}

/// linear -> dB (0..24)
double linearToDb(double linear) {
  if (linear <= 0) return 0.0;
  final db = 20.0 * (math.log(linear) / math.ln10);
  return db.clamp(0.0, 24.0);
}

/// Slider 0.0..1.0 -> dB 0..24, x^2 curve (Ripcord jaisa feel)
double sliderToDb(double t) {
  final clamped = t.clamp(0.0, 1.0);
  return clamped * clamped * 24.0;
}

/// dB -> slider (inverse)
double dbToSlider(double db) {
  final clamped = db.clamp(0.0, 24.0);
  return math.sqrt(clamped / 24.0);
}

/// PCM float frame par gain + tanh soft-clip (+24dB par phatne se bachao —
/// ye Ripcord se better hai, wahan hard clip hota hai).
List<double> applyMicGain(List<double> frame, double db) {
  final g = dbToLinear(db);
  return frame.map((s) {
    final v = s * g;
    if (v > 1.0 || v < -1.0) {
      final e2x = math.exp(2 * v * 0.8);
      return ((e2x - 1) / (e2x + 1)) * 1.1;
    }
    return v;
  }).toList();
}
