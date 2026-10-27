/// Resume only long, finite videos. Duration is expressed in milliseconds.
int resumePosition({
  required int duration,
  required int position,
  bool isLive = false,
  bool isShort = false,
}) {
  if (isLive ||
      isShort ||
      duration <= 30 * 60 * 1000 ||
      position <= 0 ||
      position >= duration - 10000) {
    return 0;
  }
  return position;
}
