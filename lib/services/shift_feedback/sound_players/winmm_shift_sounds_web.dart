import 'package:bike_control/services/shift_feedback/shift_feedback_service.dart';
import 'package:bike_control/services/shift_feedback/sound_players/shift_sound_assets.dart';

/// Stub per Web: winmm non disponibile.
class WinmmShiftSounds implements ShiftSoundPlayer {
  @override
  Future<void> preload() async {}

  @override
  Future<void> play(ShiftCue cue) async {}

  @override
  Future<void> dispose() async {}
}
