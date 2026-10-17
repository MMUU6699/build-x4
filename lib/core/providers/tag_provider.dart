import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class AssistantTag {
  const AssistantTag({required this.id, required this.name});
  final String id;
  final String name;
}

class TagProvider extends ChangeNotifier {
  TagProvider({dynamic preferences});

  final List<AssistantTag> _tags = [];
  final Map<String, String> _assistantTagMap = {};
  final Set<String> _collapsedTags = {};

  List<AssistantTag> get tags => List.unmodifiable(_tags);

  String? tagOfAssistant(String assistantId) => _assistantTagMap[assistantId];

  bool isCollapsed(String tagId) => _collapsedTags.contains(tagId);

  void toggleCollapsed(String tagId) {
    if (_collapsedTags.contains(tagId)) {
      _collapsedTags.remove(tagId);
    } else {
      _collapsedTags.add(tagId);
    }
    notifyListeners();
  }

  Future<void> reorderTags(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final item = _tags.removeAt(oldIndex);
    _tags.insert(newIndex, item);
    notifyListeners();
  }

  Future<void> assignAssistantToTag(String assistantId, String tagId) async {
    _assistantTagMap[assistantId] = tagId;
    notifyListeners();
  }

  Future<void> unassignAssistant(String assistantId) async {
    _assistantTagMap.remove(assistantId);
    notifyListeners();
  }

  Future<void> createTag(String name) async {
    _tags.add(AssistantTag(id: const Uuid().v4(), name: name));
    notifyListeners();
  }

  Future<void> renameTag(String tagId, String name) async {
    final idx = _tags.indexWhere((t) => t.id == tagId);
    if (idx != -1) {
      _tags[idx] = AssistantTag(id: tagId, name: name);
      notifyListeners();
    }
  }

  Future<void> deleteTag(String tagId) async {
    _tags.removeWhere((t) => t.id == tagId);
    _assistantTagMap.removeWhere((_, tid) => tid == tagId);
    _collapsedTags.remove(tagId);
    notifyListeners();
  }
}
