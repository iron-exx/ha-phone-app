/// A Home Assistant camera the admin shared with the app (GET /api/mobile/cameras,
/// HA-Phone 0.7.141+). Pictures come from the PBX, never straight from HA.
class PreviewCamera {
  const PreviewCamera({required this.entityId, required this.name});

  factory PreviewCamera.fromJson(Map<String, dynamic> j) {
    final id = (j['entity_id'] as String?) ?? '';
    final name = (j['name'] as String?) ?? '';
    return PreviewCamera(entityId: id, name: name.isEmpty ? id : name);
  }

  final String entityId;
  final String name;

  Map<String, String> toJson() => {'entity_id': entityId, 'name': name};

  @override
  bool operator ==(Object other) => other is PreviewCamera && other.entityId == entityId && other.name == name;

  @override
  int get hashCode => Object.hash(entityId, name);
}

List<PreviewCamera> parsePreviewCameras(Object? body) => body is List
    ? body
        .whereType<Map<String, dynamic>>()
        .map(PreviewCamera.fromJson)
        .where((c) => c.entityId.startsWith('camera.'))
        .toList()
    : const [];
