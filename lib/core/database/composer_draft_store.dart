import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../utils/app_directories.dart';
import '../models/chat_input_data.dart';
import '../models/composer_draft.dart';

class DraftEntry {
  final String? editMessageId;
  final dynamic pending;
  final ComposerDraftInput active;
  final ComposerDraftInput compose;
  final ComposerDraftInput? edit;
  final int revision;
  final bool hasRecoveryConflict;
  final String? submissionId;

  const DraftEntry({
    this.editMessageId,
    this.pending,
    this.active = const ComposerDraftInput(),
    this.compose = const ComposerDraftInput(),
    this.edit,
    this.revision = 0,
    this.hasRecoveryConflict = false,
    this.submissionId,
  });
}

class ComposerDraftStore with ChangeNotifier {
  final Map<String, String> _drafts = {};
  final Map<String, DraftEntry> _entries = {};
  final Map<String, dynamic> errors = {};
  bool suspended = false;
  int resetRevision = 0;
  int externalRevision = 0;
  String? externalOwner;

  bool hasDraft(String conversationId) =>
      _drafts.containsKey(conversationId) &&
      (_drafts[conversationId]?.isNotEmpty ?? false);

  String? getDraft(String conversationId) => _drafts[conversationId];

  void setDraft(String conversationId, String text) {
    if (text.isEmpty) {
      _drafts.remove(conversationId);
    } else {
      _drafts[conversationId] = text;
    }
    notifyListeners();
  }

  void removeDraft(String conversationId) {
    _drafts.remove(conversationId);
    notifyListeners();
  }

  final Set<String> submitting = <String>{};

  void discardPending(String conversationId) => removeDraft(conversationId);
  Future<void> flush() async {}
  Future<DraftSubmission?> beginSubmission(
    String conversationId, [
    dynamic snapshot,
  ]) async {
    submitting.add(conversationId);
    return DraftSubmission(
      id: const Uuid().v4(),
      conversationId: conversationId,
    );
  }

  void submissionIdle(String conversationId) {
    submitting.remove(conversationId);
  }

  Future<bool> wasSubmitted(String id) async => false;
  Future<void> finishSubmission(
    dynamic submission, {
    bool? preserveEdit,
  }) async {}
  dynamic newEntry([String? assistantId]) => null;
  bool hasShareReceipt(dynamic id) => false;
  Future<void> acknowledgeShares(dynamic shares) async {}
  Future<Directory> directoryFor(String name) async =>
      AppDirectories.getUploadDirectory();

  DraftEntry? peek(String conversationId) =>
      _entries[conversationId] ?? const DraftEntry();

  bool isInputCurrent(
    String conversationId,
    int epoch, {
    String? editMessageId,
  }) => true;
  int inputEpoch(String conversationId, {String? editMessageId}) => 0;
  void mutateCaptured(
    String conversationId,
    int epoch,
    String? editMessageId,
    Function change,
  ) {}
  bool sameOwnedFile(String owner, String file1, String file2) =>
      file1 == file2;
  void invalidateInputOperations(String owner, {String? editMessageId}) {}

  void restorePending(String conversationId, {bool? append, bool? replace}) {}
  void setInput(String conversationId, dynamic input) {}
  Future<DraftEntry> load(String conversationId, {String? assistantId}) async =>
      _entries[conversationId] ?? const DraftEntry();
  Future<ChatInputData> prepareSubmissionInput(ChatInputData input) async =>
      input;
  void beginEdit(
    String conversationId,
    String messageId,
    ComposerDraftInput input,
  ) {}
  void endEdit(String conversationId) {}
  int epoch(String conversationId) => 0;
  bool isCurrent(String conversationId, int epoch) => true;
  static ComposerDraftInput merge(ComposerDraftInput a, ComposerDraftInput b) =>
      b;
  Future<void> acceptShare(
    String owner,
    ComposerDraftInput value,
    dynamic shareIds,
  ) async {}
  Future<void> transfer(
    String sourceId,
    String targetId, {
    bool? append,
  }) async {}
}
