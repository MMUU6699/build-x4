import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';

class UserProvider extends ChangeNotifier {
  String _name = '';
  String _email = '';
  String _roleOrBio = '';
  String? _avatarType; // 'emoji', 'url', 'file'
  String? _avatarValue;

  String get name => _name;
  String get email => _email;
  String get roleOrBio => _roleOrBio;
  String? get avatarType => _avatarType;
  String? get avatarValue => _avatarValue;

  UserProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _name = prefs.getString('buildx_user_name') ?? _name;
      _email = prefs.getString('buildx_user_email') ?? _email;
      _roleOrBio = prefs.getString('buildx_user_role') ?? _roleOrBio;
      _avatarType = prefs.getString('buildx_user_avatar_type');
      _avatarValue = prefs.getString('buildx_user_avatar_value');
    } catch (e) {
      debugPrint('Failed to load local user preferences: $e');
    }

    if (SupabaseConfig.isGuestMode) {
      notifyListeners();
      return;
    }

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        if (user.email != null && user.email!.isNotEmpty) {
          _email = user.email!;
        }
        final metaName = user.userMetadata?['name'] as String?;
        if (metaName != null && metaName.isNotEmpty) {
          _name = metaName;
        }
        final profile = await SupabaseConfig.client
            .from('profiles')
            .select('display_name, avatar_url')
            .eq('id', user.id)
            .maybeSingle();
        if (profile != null) {
          final displayName = profile['display_name'] as String?;
          if (displayName != null && displayName.trim().isNotEmpty) {
            _name = displayName;
          }
          if (profile['avatar_url'] != null) {
            _avatarValue = profile['avatar_url'] as String;
            _avatarType = 'url';
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load profile from supabase: $e');
    }
    notifyListeners();
  }

  void setDefaultNameIfUnset(String localizedDefaultName) {
    if (_name.trim().isEmpty && localizedDefaultName.trim().isNotEmpty) {
      _name = localizedDefaultName.trim();
      notifyListeners();
    }
  }

  Future<void> setName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _name) return;
    _name = trimmed;
    notifyListeners();
    await _saveLocal();
    await _syncSupabase();
  }

  Future<void> setEmail(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || trimmed == _email) return;
    _email = trimmed;
    notifyListeners();
    await _saveLocal();
  }

  Future<void> setRoleOrBio(String roleOrBio) async {
    final trimmed = roleOrBio.trim();
    if (trimmed == _roleOrBio) return;
    _roleOrBio = trimmed;
    notifyListeners();
    await _saveLocal();
  }

  Future<void> setAvatarUrl(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    _avatarType = 'url';
    _avatarValue = u;
    notifyListeners();
    await _saveLocal();
    await _syncSupabase();
  }

  Future<void> setAvatarEmoji(String emoji) async {
    final e = emoji.trim();
    if (e.isEmpty) return;
    _avatarType = 'emoji';
    _avatarValue = e;
    notifyListeners();
    await _saveLocal();
  }

  Future<void> setAvatarFilePath(String path) async {
    final p = path.trim();
    if (p.isEmpty) return;
    _avatarType = 'file';
    _avatarValue = p;
    notifyListeners();
    await _saveLocal();
  }

  Future<void> clearAvatar() async {
    _avatarType = null;
    _avatarValue = null;
    notifyListeners();
    await _saveLocal();
    await _syncSupabase();
  }

  Future<void> resetAvatar() => clearAvatar();

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('buildx_user_name', _name);
      await prefs.setString('buildx_user_email', _email);
      await prefs.setString('buildx_user_role', _roleOrBio);
      if (_avatarType != null) {
        await prefs.setString('buildx_user_avatar_type', _avatarType!);
      } else {
        await prefs.remove('buildx_user_avatar_type');
      }
      if (_avatarValue != null) {
        await prefs.setString('buildx_user_avatar_value', _avatarValue!);
      } else {
        await prefs.remove('buildx_user_avatar_value');
      }
    } catch (e) {
      debugPrint('Failed to save local user preferences: $e');
    }
  }

  Future<void> _syncSupabase() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      await SupabaseConfig.client.from('profiles').upsert({
        'id': user.id,
        if (_name.trim().isNotEmpty) 'display_name': _name.trim(),
        'avatar_url': _avatarType == 'url' ? _avatarValue : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('Failed to sync profile with supabase: $e');
    }
  }
}
