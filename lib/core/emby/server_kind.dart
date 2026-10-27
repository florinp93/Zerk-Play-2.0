enum ServerKind {
  emby('Emby'),
  jellyfin('Jellyfin');

  const ServerKind(this.label);

  final String label;

  static ServerKind parse(String? raw) => values.where((k) => k.name == raw).firstOrNull ?? emby;
}
