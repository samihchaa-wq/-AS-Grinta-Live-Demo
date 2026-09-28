/// Stub local de la démo : aucune photo n'est résolue depuis Supabase.
/// Les avatars utilisent donc exactement le fallback à initiales du vrai widget.
class ProfilePhotoUrlCache {
  ProfilePhotoUrlCache._();

  static final ProfilePhotoUrlCache instance = ProfilePhotoUrlCache._();

  String? cached(String? value) => null;

  Future<String?> resolve(String? value) async => null;

  void invalidate(String? value) {}
}
