import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../core/services/incoming_share_service.dart';
import 'composer_attachment_card.dart';
import 'dart:collection';
import 'dart:ui' as ui;
import '../../../theme/design_tokens.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import '../../../utils/file_import_helper.dart';
import '../../../utils/image_compressor.dart';
import '../../../utils/upload_dedupe.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../shared/responsive/breakpoints.dart';
import 'dart:async';
import 'dart:io';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/reasoning_request.dart';
import '../../../utils/clipboard_images.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/utils/multimodal_input_utils.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../shared/widgets/interactive_drawer.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../utils/app_directories.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:re_editor/re_editor.dart' show CodeEditorTapRegion;
import '../../../shared/widgets/long_message_editor.dart';
import '../services/context_usage_service.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import '../../../core/models/composer_draft.dart';
import '../../../core/database/composer_draft_store.dart';

class ChatInputBarController {
  ChatInputBarController();
  ChatInputBarController._captured(
    this._origin,
    this._owner,
    this._edit,
    this._inputEpoch,
  );
  ChatInputBarController? _origin;
  String? _owner;
  String? _edit;
  int? _inputEpoch;
  ChatInputBarController get _root => _origin ?? this;
  bool get isValid =>
      _origin == null ||
      _root.draftStore == null ||
      _root.draftStore!.isInputCurrent(
        _owner!,
        _inputEpoch!,
        editMessageId: _edit,
      );
  bool get _currentTarget =>
      (_origin == null && !_root.restoringDraft) ||
      (!_root.restoringDraft &&
          _root.isAttached &&
          _root.draftOwnerId == _owner &&
          _root.draftStore?.peek(_owner ?? '')?.editMessageId == _edit &&
          (_root.draftStore == null ||
              _root.draftStore!.isInputCurrent(
                _owner!,
                _inputEpoch!,
                editMessageId: _edit,
              )));
  ChatInputBarController capture() {
    final owner = _root.draftOwnerId;
    if (owner == null) return this;
    final edit = _root.draftStore?.peek(owner)?.editMessageId;
    return ChatInputBarController._captured(
      _root,
      owner,
      edit,
      _root.draftStore?.inputEpoch(owner, editMessageId: edit) ?? 0,
    );
  }

  void _mutate(ComposerDraftInput Function(ComposerDraftInput) change) {
    final owner = _owner ?? draftOwnerId;
    if (owner != null) {
      final edit = _origin == null
          ? _root.draftStore?.peek(owner)?.editMessageId
          : _edit;
      _root.draftStore?.mutateCaptured(
        owner,
        _inputEpoch ?? _root.draftStore!.inputEpoch(owner, editMessageId: edit),
        edit,
        change,
      );
    }
  }

  ComposerDraftStore? draftStore;
  String? draftOwnerId;
  bool _restoringDraft = false;
  // An overwrite pauses editing independently of an in-progress/failed load.
  // Releasing that pause must not change the draft restoration state.
  bool get restoringDraft => _restoringDraft || draftStore?.suspended == true;
  set restoringDraft(bool value) => _restoringDraft = value;
  VoidCallback? onDraftChanged;
  VoidCallback? onRecoverDraft;
  VoidCallback? onDiscardRecoveredDraft;
  VoidCallback? onRetrySave;
  Future<DraftSubmission?> Function(ComposerDraftInput)? onBeginSubmission;
  ComposerDraftInput snapshotDraft(String text) =>
      _state?._snapshotDraft(text) ??
      _pendingDraft?.copyWith(text: text) ??
      ComposerDraftInput(text: text);
  ComposerDraftInput? _pendingDraft;
  void restoreDraft(ComposerDraftInput input, {bool resetHistory = true}) {
    if (_state == null) {
      _pendingDraft = input;
    } else {
      _state!._restoreDraft(input, resetHistory: resetHistory);
    }
  }

  Future<Directory> uploadDirectory() =>
      _root.draftStore != null && (_owner ?? _root.draftOwnerId) != null
      ? _root.draftStore!.directoryFor((_owner ?? _root.draftOwnerId)!)
      : AppDirectories.getUploadDirectory();
  final shareImport = ValueNotifier<ShareImportProgress?>(null);
  final sharedDraftAction = ValueNotifier<VoidCallback?>(null);
  VoidCallback? cancelShareImport;

  _ChatInputBarState? _state;
  void _bind(_ChatInputBarState s) {
    _state = s;
    final pending = _pendingDraft;
    _pendingDraft = null;
    if (pending != null) s._restoreDraft(pending);
  }

  void _unbind(_ChatInputBarState s) {
    if (!identical(_state, s)) return;
    _pendingDraft = s._snapshotDraft(s._controller.text);
    _state = null;
  }

  bool get allowImagesApiRouting =>
      _state?._allowImagesApiRouting ??
      _pendingDraft?.allowImagesApiRouting ??
      true;
  bool get isAttached => _state != null;
  bool get hasDraftMedia =>
      _state?._hasDraftMedia ??
      ((_pendingDraft?.images.isNotEmpty ?? false) ||
          (_pendingDraft?.documents.isNotEmpty ?? false));
  bool get hasUnreadyImages =>
      _state?._hasUnreadyImages ??
      (_pendingDraft?.images.any((image) => image.processing || image.failed) ??
          false);

  /// Snapshot for comparing media across an asynchronous draft handoff.
  /// Unlike snapshotInput, this includes unready images and pending pastes.
  /// Image identities stay stable when compression updates their paths.
  List<Object> get draftMediaIdentity {
    final state = _state;
    if (state == null) return const [];
    return [
      state,
      ...state._images,
      ...state._docs,
      for (final id in state._pendingImagePasteIds) ('imagePaste', id),
      for (final id in state._pendingTextPasteIds) ('textPaste', id),
    ];
  }

  void addImages(List<String> paths) {
    if (_currentTarget) {
      _root._state?._addImages(paths);
    } else {
      _mutate(
        (input) => input.copyWith(
          images: [
            ...input.images,
            for (final path in paths) DraftImage(path: path),
          ],
        ),
      );
    }
  }

  void enqueueImages(
    List<String> paths,
    ImageCompressConfig config, {
    bool deleteSourcesAfterProcessing = false,
  }) {
    if (_currentTarget) {
      _root._state?._enqueueImages(
        paths,
        config,
        deleteSourcesAfterProcessing: deleteSourcesAfterProcessing,
      );
    } else {
      _mutate(
        (input) => input.copyWith(
          images: [
            ...input.images,
            for (final path in paths) DraftImage(path: path, processing: true),
          ],
        ),
      );
      unawaited(
        _processCapturedImages(paths, config, deleteSourcesAfterProcessing),
      );
    }
  }

  Future<void> _processCapturedImages(
    List<String> paths,
    ImageCompressConfig config,
    bool deleteSources,
  ) async {
    for (final path in paths) {
      UploadWrite? saved;
      try {
        saved = await ImageCompressor.compressToUploadDir(
          path,
          await uploadDirectory(),
          config,
        );
      } catch (_) {}
      replaceProcessedImage(path, saved?.path);
      // Private source copies are reclaimed after a later durable snapshot.
      if (deleteSources &&
          _root.draftStore == null &&
          saved?.path != path &&
          saved != null) {
        await UploadDedupe.deleteIfUnshared(path);
      }
    }
  }

  void replaceProcessedImage(String source, String? result) {
    _mutate(
      (input) => input.copyWith(
        images: [
          for (final image in input.images)
            if ((image.path == source ||
                    (_owner != null &&
                        (_root.draftStore?.sameOwnedFile(
                              _owner!,
                              image.path,
                              source,
                            ) ??
                            false))) &&
                image.processing)
              DraftImage(path: result ?? source, failed: result == null)
            else
              image,
        ],
      ),
    );
  }

  void clearImages() => _state?._clearImages();
  void addFiles(List<DocumentAttachment> docs) {
    if (_currentTarget) {
      _root._state?._addFiles(docs);
    } else {
      _mutate(
        (input) => input.copyWith(documents: [...input.documents, ...docs]),
      );
    }
  }

  void insertText(String text) {
    if (_currentTarget) {
      _root._state?._insertPastedText(text);
    } else {
      _mutate(
        (input) => input.copyWith(
          text: input.text + text,
          selectionBase: input.text.length + text.length,
          selectionExtent: input.text.length + text.length,
        ),
      );
    }
  }

  void clearFiles() => _state?._clearFiles();
  void restoreInput(ChatInputData input) => _state?._restoreInput(input);
  ChatInputData snapshotInput(String text) {
    if (_state != null) return _state!._snapshotInput(text);
    final draft = snapshotDraft(text);
    return ChatInputData(
      text: text.trim(),
      imagePaths: [
        for (final image in draft.images)
          if (!image.processing && !image.failed) image.path,
      ],
      documents: draft.documents,
      allowImagesApiRouting: draft.allowImagesApiRouting,
    );
  }

  void clearDraft() {
    final owner = draftOwnerId;
    if (owner != null) {
      draftStore?.invalidateInputOperations(
        owner,
        editMessageId: draftStore?.peek(owner)?.editMessageId,
      );
    }
    _state?._clearDraft();
  }
}

class _DraftImage {
  _DraftImage({required this.id, required this.path});

  final int id;
  String path;
}

class _ImageProcessingTask {
  const _ImageProcessingTask({
    required this.id,
    required this.sourcePath,
    required this.config,
    required this.deleteSourceAfterProcessing,
    this.target,
  });

  final int id;
  final String sourcePath;
  final ImageCompressConfig config;
  final ChatInputBarController? target;

  /// Only ever true for app-owned temp sources (clipboard paste temps);
  /// user-picked files must never be flagged for deletion.
  final bool deleteSourceAfterProcessing;
}

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    this.chatModelProviderKey,
    this.chatModelId,
    this.onSend,
    this.onStop,
    this.onSelectModel,
    this.onLongPressSelectModel,
    this.onOpenTools,
    this.onLongPressTools,
    this.onOpenWorkspace,
    this.showWorkspaceButton = false,
    this.workspaceActive = false,
    this.onOpenSkills,
    this.skillsActive = false,
    this.onOpenSearch,
    this.onMore,
    this.onConfigureReasoning,
    this.onOpenContextUsage,
    this.moreOpen = false,
    this.focusNode,
    this.modelIcon,
    this.controller,
    this.mediaController,
    this.asrProvider,
    this.loading = false,
    this.hasQueuedInput = false,
    this.queuedPreviewText,
    this.onCancelQueuedInput,
    this.onExpandedChanged,
    this.reasoningActive = false,
    this.reasoning,
    this.reasoningCustomBudget = false,
    this.supportsReasoning = true,
    this.showToolsButton = false,
    this.toolsActive = false,
    this.showMiniMapButton = false,
    this.onOpenMiniMap,
    this.onPickCamera,
    this.onPickPhotos,
    this.onUploadFiles,
    this.onToggleLearningMode,
    this.onOpenWorldBook,
    this.onClearContext,
    this.onCompressContext,
    this.onLongPressLearning,
    this.learningModeActive = false,
    this.worldBookActive = false,
    this.showMoreButton = true,
    this.showQuickPhraseButton = false,
    this.onQuickPhrase,
    this.onLongPressQuickPhrase,
    this.showOcrButton = false,
    this.ocrActive = false,
    this.onToggleOcr,
    this.conversationId,
    this.sendButtonTooltip,
    this.backgroundImageActive = false,
    this.inputBackgroundOpacityLight =
        SettingsProvider.defaultChatInputBackgroundOpacityLight,
    this.inputBackgroundOpacityDark =
        SettingsProvider.defaultChatInputBackgroundOpacityDark,
  });

  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;
  final VoidCallback? onStop;
  final VoidCallback? onSelectModel;
  final VoidCallback? onLongPressSelectModel;
  final VoidCallback? onOpenTools;
  final VoidCallback? onLongPressTools;
  final VoidCallback? onOpenWorkspace;
  final bool showWorkspaceButton;
  final bool workspaceActive;
  final VoidCallback? onOpenSkills;
  final bool skillsActive;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onMore;
  final VoidCallback? onConfigureReasoning;
  final VoidCallback? onOpenContextUsage;
  final bool moreOpen;
  final FocusNode? focusNode;
  final Widget? modelIcon;
  final TextEditingController? controller;
  final ChatInputBarController? mediaController;
  final dynamic asrProvider;
  final bool loading;
  final bool hasQueuedInput;
  final String? queuedPreviewText;
  final VoidCallback? onCancelQueuedInput;

  /// Reports when the composer starts filling the chat area and when it has
  /// finished shrinking back, so the host can ignore its transient heights.
  final ValueChanged<bool>? onExpandedChanged;
  final bool reasoningActive;
  final ReasoningRequest? reasoning;
  final bool reasoningCustomBudget;
  final bool supportsReasoning;
  final bool showToolsButton;
  final bool toolsActive;
  final bool showMiniMapButton;
  final VoidCallback? onOpenMiniMap;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickPhotos;
  final VoidCallback? onUploadFiles;
  final VoidCallback? onToggleLearningMode;
  final VoidCallback? onOpenWorldBook;
  final VoidCallback? onClearContext;
  final VoidCallback? onCompressContext;
  final VoidCallback? onLongPressLearning;
  final bool learningModeActive;
  final bool worldBookActive;
  final bool showMoreButton;
  final bool showQuickPhraseButton;
  final VoidCallback? onQuickPhrase;
  final VoidCallback? onLongPressQuickPhrase;
  final bool showOcrButton;
  final bool ocrActive;
  final VoidCallback? onToggleOcr;
  final String? conversationId;

  /// The model this conversation sends with, already resolved through
  /// conversation override -> assistant -> global default.
  final String? chatModelProviderKey;
  final String? chatModelId;
  final String? sendButtonTooltip;
  final bool backgroundImageActive;
  final double inputBackgroundOpacityLight;
  final double inputBackgroundOpacityDark;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.mediaController?.onDraftChanged?.call();
  }

  late TextEditingController _controller;

  // Expanding grows the whole composer to fill the height its host allows,
  // so attachments, tools and send stay in reach while editing long text.
  static const int _collapsedMaxLines = 6;
  static const double _expandButtonExtent = 28; // 16 glyph + 2 × 6 padding
  bool _isExpanded = false;
  bool _canExpand = false;
  bool _expandCheckScheduled = false;
  double _expandFromHeight = 0;
  // Text area height around the editable line box (padding + decoration),
  // measured while collapsed so the collapse can aim at an exact height.
  double _textAreaChrome = 0;
  InteractiveDrawerController? _hostDrawer;
  final GlobalKey _composerKey = GlobalKey();
  final GlobalKey _textAreaKey = GlobalKey();
  var _longEditorKey = GlobalKey<LongMessageEditorState>();
  late final AnimationController _expandController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addStatusListener(_handleExpandStatus);
  late final CurvedAnimation _expandProgress = CurvedAnimation(
    parent: _expandController,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  // The ASR provider owns microphone capture. This widget only owns the
  // composer presentation and an exact snapshot used by Cancel.
  final List<double> _voiceLevels = <double>[];
  final ValueNotifier<int> _voiceLevelsVersion = ValueNotifier<int>(0);
  TextEditingValue? _voiceBaseValue;
  bool _ownsVoiceSession = false;
  bool _finishingVoice = false;
  // Fixed when a recording starts: whether it runs a recognizer (otherwise it
  // only records), and whether it can end as an audio attachment.
  // Bumped when a recording starts or is cancelled, so a finish that resolves
  // late can tell its recording is gone and must not touch the draft.
  final List<_DraftImage> _images = <_DraftImage>[];
  final Queue<_ImageProcessingTask> _imageProcessingQueue =
      Queue<_ImageProcessingTask>();
  final Set<int> _processingImageIds = <int>{};
  final Set<int> _failedImageIds = <int>{};
  final Set<int> _pendingImagePasteIds = <int>{};
  final Set<int> _pendingTextPasteIds = <int>{};
  static const int _maxConcurrentImageTasks = 2;
  int _activeImageTasks = 0;
  int _nextImageId = 0;
  int _nextImagePasteId = 0;
  int _nextTextPasteId = 0;
  int _draftReplacementRevision = 0;
  Future<void> _textPasteWriteTail = Future<void>.value();
  final List<DocumentAttachment> _docs =
      <DocumentAttachment>[]; // files to upload
  final Map<LogicalKeyboardKey, Timer?> _repeatTimers = {};
  static const Duration _repeatInitialDelay = Duration(milliseconds: 300);
  static const Duration _repeatPeriod = Duration(milliseconds: 35);
  static const double _imageRemoveButtonSize = 18;
  // Suppress context menu briefly after app resume to avoid flickering
  bool _suppressContextMenu = false;
  bool _isSubmitting = false;
  int _submitSerial = 0;
  String? _imageModeModelKey;
  String? _lastImageModeModelKey;
  String? _dismissedImageModeModelKey;
  bool? _restoredRoutingChoice;
  final Set<String> _missingDocumentPaths = {};

  bool get _composerLocked =>
      widget.hasQueuedInput ||
      (widget.mediaController?.restoringDraft ?? false);

  bool _supportsImagesApiRouting(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final providerKey = widget.chatModelProviderKey;
    final modelId = widget.chatModelId;
    if (providerKey == null || modelId == null) {
      _imageModeModelKey = null;
      return false;
    }
    final cfg = settings.getProviderConfig(providerKey);
    final supported = ChatApiService.supportsOpenAIImagesApiRouting(
      cfg,
      modelId,
    );
    final nextKey = supported
        ? '${widget.conversationId ?? ''}::$providerKey::$modelId'
        : null;
    if (nextKey != _lastImageModeModelKey) {
      _dismissedImageModeModelKey = null;
      _lastImageModeModelKey = nextKey;
    }
    _imageModeModelKey = nextKey;
    if (_restoredRoutingChoice != null) {
      _dismissedImageModeModelKey = _restoredRoutingChoice! ? null : nextKey;
      _restoredRoutingChoice = null;
    }
    return supported;
  }

  bool get _imageModeActive {
    final key = _imageModeModelKey;
    return key != null && key != _dismissedImageModeModelKey;
  }

  bool get _allowImagesApiRouting {
    if (_restoredRoutingChoice != null) return _restoredRoutingChoice!;
    final key = _imageModeModelKey;
    return key == null || key != _dismissedImageModeModelKey;
  }

  bool get _hasDraftMedia => _images.isNotEmpty || _docs.isNotEmpty;
  bool get _hasUnreadyImages =>
      _processingImageIds.isNotEmpty ||
      _failedImageIds.isNotEmpty ||
      _pendingImagePasteIds.isNotEmpty ||
      _pendingTextPasteIds.isNotEmpty;

  // Instance method for onChanged to avoid recreating the callback on every build
  void _onTextChanged(String _) => setState(() {});

  String? _usageDraftConversationId;
  String? _usageDraftText;

  void _handleAsrChanged() {}
  void _abandonVoiceSession() {}
  void _stopVoiceLevelSampling() {}

  void _syncUsageDraft() {
    if (!mounted) return;
    final id = widget.conversationId;
    if (id == null || id.isEmpty) return;
    final text = _controller.text;
    if (_usageDraftConversationId == id && _usageDraftText == text) return;
    _usageDraftConversationId = id;
    _usageDraftText = text;
    context.read<ContextUsageService?>()?.updateDraft(id, text);
  }

  void _addImages(List<String> paths) {
    if (paths.isEmpty) return;
    setState(() {
      _images.addAll(
        paths.map((path) => _DraftImage(id: _nextImageId++, path: path)),
      );
    });
  }

  void _enqueueImages(
    List<String> paths,
    ImageCompressConfig config, {
    required bool deleteSourcesAfterProcessing,
  }) {
    if (paths.isEmpty) return;
    setState(() {
      for (final path in paths) {
        final image = _DraftImage(id: _nextImageId++, path: path);
        _images.add(image);
        _processingImageIds.add(image.id);
        _imageProcessingQueue.add(
          _ImageProcessingTask(
            id: image.id,
            sourcePath: path,
            config: config,
            deleteSourceAfterProcessing: deleteSourcesAfterProcessing,
            target: widget.mediaController?.capture(),
          ),
        );
      }
    });
    _pumpImageProcessingQueue();
  }

  void _pumpImageProcessingQueue() {
    while (mounted &&
        _activeImageTasks < _maxConcurrentImageTasks &&
        _imageProcessingQueue.isNotEmpty) {
      final task = _imageProcessingQueue.removeFirst();
      if (!_processingImageIds.contains(task.id)) continue;
      _activeImageTasks++;
      unawaited(_processImage(task));
    }
  }

  Future<void> _processImage(_ImageProcessingTask task) async {
    UploadWrite? saved;
    try {
      final dir =
          await (task.target?.uploadDirectory() ??
              AppDirectories.getUploadDirectory());
      saved = await ImageCompressor.compressToUploadDir(
        task.sourcePath,
        dir,
        task.config,
      );
    } catch (_) {
      saved = null;
    } finally {
      if (task.deleteSourceAfterProcessing &&
          widget.mediaController?.draftStore == null &&
          (saved == null ||
              !p.equals(
                p.normalize(p.absolute(task.sourcePath)),
                p.normalize(p.absolute(saved.path)),
              ))) {
        await _deleteTemporaryImageSource(task.sourcePath);
      }
      _activeImageTasks--;
    }
    final savedPath = saved?.path;

    if (task.target != null && !task.target!._currentTarget) {
      task.target!.replaceProcessedImage(task.sourcePath, savedPath);
      if (mounted) _pumpImageProcessingQueue();
      return;
    }

    final index = mounted
        ? _images.indexWhere((image) => image.id == task.id)
        : -1;
    final taskIsActive = index >= 0 && _processingImageIds.contains(task.id);
    // Only a copy this task created, that no other import has resolved to in
    // the meantime, may be cleaned up.
    if (!taskIsActive && task.target?._root.draftStore != null) {
      task.target!.replaceProcessedImage(task.sourcePath, savedPath);
      if (mounted) _pumpImageProcessingQueue();
      return;
    }
    if (!taskIsActive &&
        savedPath != null &&
        !saved!.reused &&
        !UploadDedupe.isShared(savedPath) &&
        !p.equals(
          p.normalize(p.absolute(task.sourcePath)),
          p.normalize(p.absolute(savedPath)),
        )) {
      try {
        await File(savedPath).delete();
      } catch (error) {
        debugPrint(
          '[ChatInputBar] Failed to delete discarded compressed image $savedPath: $error',
        );
      }
    }

    if (!mounted) return;
    if (taskIsActive) {
      setState(() {
        _processingImageIds.remove(task.id);
        if (savedPath == null) {
          _failedImageIds.add(task.id);
        } else {
          _images[index].path = savedPath;
        }
      });
    }
    _pumpImageProcessingQueue();
  }

  void _discardImageState(Iterable<int> ids) {
    final discarded = ids.toSet();
    final discardedQueuedTasks = _imageProcessingQueue
        .where((task) => discarded.contains(task.id))
        .toList(growable: false);
    _processingImageIds.removeAll(discarded);
    _failedImageIds.removeAll(discarded);
    _imageProcessingQueue.removeWhere((task) => discarded.contains(task.id));
    for (final task in discardedQueuedTasks) {
      if (task.deleteSourceAfterProcessing &&
          widget.mediaController?.draftStore == null) {
        unawaited(_deleteTemporaryImageSource(task.sourcePath));
      }
    }
  }

  void _clearImages() {
    setState(() {
      _pendingImagePasteIds.clear();
      _discardImageState(_images.map((image) => image.id));
      _images.clear();
    });
  }

  void _addFiles(List<DocumentAttachment> docs) {
    if (docs.isEmpty) return;
    setState(() => _docs.addAll(docs));
  }

  void _clearFiles() {
    setState(() {
      _pendingTextPasteIds.clear();
      _docs.clear();
    });
  }

  void _restoreInput(ChatInputData input) {
    setState(() {
      _draftReplacementRevision++;
      _abandonVoiceSession();
      _pendingImagePasteIds.clear();
      _pendingTextPasteIds.clear();
      _discardImageState(_images.map((image) => image.id));
      _images
        ..clear()
        ..addAll(
          input.imagePaths.map(
            (path) => _DraftImage(
              id: _nextImageId++,
              path: isRemoteOrDataUri(path)
                  ? path
                  : SandboxPathResolver.fix(path),
            ),
          ),
        );
      _docs
        ..clear()
        ..addAll(input.documents);
    });
  }

  ChatInputData _snapshotInput(String text) {
    return ChatInputData(
      text: text.trim(),
      imagePaths: [
        for (final image in _images)
          if (!_processingImageIds.contains(image.id) &&
              !_failedImageIds.contains(image.id))
            image.path,
      ],
      documents: List<DocumentAttachment>.of(_docs),
      allowImagesApiRouting: _allowImagesApiRouting,
    );
  }

  ComposerDraftInput _snapshotDraft(String text) => ComposerDraftInput(
    text: text,
    selectionBase: _controller.selection.baseOffset,
    selectionExtent: _controller.selection.extentOffset,
    images: [
      for (final image in _images)
        DraftImage(
          path: image.path,
          processing: _processingImageIds.contains(image.id),
          failed: _failedImageIds.contains(image.id),
        ),
    ],
    documents: List.of(_docs),
    allowImagesApiRouting: _allowImagesApiRouting,
  );

  void _restoreDraft(ComposerDraftInput input, {bool resetHistory = true}) {
    if (resetHistory) _longEditorKey = GlobalKey<LongMessageEditorState>();
    final config = context
        .read<SettingsProvider>()
        .resolveImageCompressConfig();
    _missingDocumentPaths
      ..clear()
      ..addAll(
        input.documents
            .where(
              (doc) =>
                  !isRemoteOrDataUri(doc.path) &&
                  !File(SandboxPathResolver.fix(doc.path)).existsSync(),
            )
            .map((doc) => SandboxPathResolver.fix(doc.path)),
      );
    setState(() {
      _draftReplacementRevision++;
      if (resetHistory) {
        _abandonVoiceSession();
        _pendingImagePasteIds.clear();
        _pendingTextPasteIds.clear();
      }
      _discardImageState(_images.map((image) => image.id));
      _images.clear();
      for (final saved in input.images) {
        final path = SandboxPathResolver.fix(saved.path);
        final image = _DraftImage(id: _nextImageId++, path: path);
        _images.add(image);
        if (saved.failed ||
            (!isRemoteOrDataUri(path) && !File(path).existsSync())) {
          _failedImageIds.add(image.id);
        } else if (saved.processing) {
          _processingImageIds.add(image.id);
          _imageProcessingQueue.add(
            _ImageProcessingTask(
              id: image.id,
              sourcePath: path,
              config: config,
              deleteSourceAfterProcessing: false,
              target: widget.mediaController?.capture(),
            ),
          );
        }
      }
      _docs
        ..clear()
        ..addAll(
          input.documents.map(
            (doc) => DocumentAttachment(
              path: SandboxPathResolver.fix(doc.path),
              fileName: doc.fileName,
              mime: doc.mime,
            ),
          ),
        );
      _restoredRoutingChoice = input.allowImagesApiRouting;
    });
    _pumpImageProcessingQueue();
  }

  void _clearDraft() {
    widget.mediaController?.sharedDraftAction.value = null;
    setState(() {
      _draftReplacementRevision++;
      _abandonVoiceSession();
      _controller.clear();
      _pendingImagePasteIds.clear();
      _pendingTextPasteIds.clear();
      _discardImageState(_images.map((image) => image.id));
      _images.clear();
      _docs.clear();
    });
  }

  void _removeImageAt(int index) {
    setState(() {
      final image = _images.removeAt(index);
      _discardImageState([image.id]);
    });
  }

  void _removeDocumentAt(int index) {
    setState(() => _docs.removeAt(index));
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_syncUsageDraft);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncUsageDraft());
    widget.mediaController?._bind(this);
    widget.asrProvider?.addListener(_handleAsrChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app resumes from background, suppress context menu briefly to avoid flickering
    if (state == AppLifecycleState.resumed) {
      _suppressContextMenu = true;
      // Also unfocus to reset any stuck toolbar state
      widget.focusNode?.unfocus();
      // Re-enable context menu after a short delay
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _suppressContextMenu = false);
        }
      });
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // When going to background, hide any open toolbar
      _suppressContextMenu = true;
      widget.focusNode?.unfocus();
      if (_ownsVoiceSession) _abandonVoiceSession();
    }
  }

  @override
  void dispose() {
    // Multi-selection temporarily removes the widget. Retain its complete
    // draft before clearing processing/failure state for disposed image tasks.
    widget.mediaController?._unbind(this);
    _controller.removeListener(_syncUsageDraft);
    WidgetsBinding.instance.removeObserver(this);
    _stopVoiceLevelSampling();
    final asr = widget.asrProvider;
    asr?.removeListener(_handleAsrChanged);
    if (_ownsVoiceSession && asr != null) unawaited(asr.cancel());
    for (final timer in _repeatTimers.values) {
      try {
        timer?.cancel();
      } catch (_) {}
    }
    _repeatTimers.clear();
    _pendingImagePasteIds.clear();
    _pendingTextPasteIds.clear();
    _discardImageState(_images.map((image) => image.id));
    _imageProcessingQueue.clear();
    _processingImageIds.clear();
    _failedImageIds.clear();
    // A host told the composer is expanded must hear it ended, or it keeps
    // ignoring the input bar's height after this one is replaced.
    if (!_expandController.isDismissed) widget.onExpandedChanged?.call(false);
    _expandProgress.dispose();
    _expandController.dispose();
    if (widget.controller == null) {
      _controller.dispose();
    }
    _voiceLevelsVersion.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousConversationId = oldWidget.conversationId;
    final nextConversationId = widget.conversationId;
    if (previousConversationId != nextConversationId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncUsageDraft());
    }
    if (previousConversationId != null &&
        nextConversationId != null &&
        previousConversationId != nextConversationId) {
      // The composer is reused across conversations (stable GlobalKey). A
      // submit that is still awaiting onSend must not lock the next chat.
      _submitSerial++;
      _isSubmitting = false;
      _draftReplacementRevision++;
      _abandonVoiceSession();
    }
    if (!identical(oldWidget.asrProvider, widget.asrProvider)) {
      _stopVoiceLevelSampling();
      oldWidget.asrProvider?.removeListener(_handleAsrChanged);
      if (_ownsVoiceSession && oldWidget.asrProvider != null) {
        unawaited(oldWidget.asrProvider!.cancel());
        final original = _voiceBaseValue;
        if (original != null) _controller.value = original;
        _voiceBaseValue = null;
        _ownsVoiceSession = false;
        _finishingVoice = false;
        _voiceLevels.clear();
      }
      widget.asrProvider?.addListener(_handleAsrChanged);
    }
  }

  String _hint(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return isArabic ? 'اكتب رسالتك إلى Build X...' : 'Reply to Build X...';
  }

  // ---------------------------------------------------------------------------
  // Expanded editing
  // ---------------------------------------------------------------------------

  /// True from the moment expansion starts until the collapse animation ends.
  bool get _expandedLayout => _isExpanded || !_expandController.isDismissed;

  RenderEditable? _findRenderEditable() {
    RenderEditable? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderEditable) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    final root = _textAreaKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  /// Offers expansion once the collapsed field wraps onto a third line.
  void _scheduleExpandCheck() {
    if (_expandCheckScheduled) return;
    _expandCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _expandCheckScheduled = false;
      if (!mounted || _expandedLayout) return;
      if (_longEditorKey.currentState?.usesLineEditor ?? false) {
        if (!_canExpand) setState(() => _canExpand = true);
        return;
      }
      final editable = _findRenderEditable();
      if (editable == null || !editable.hasSize) return;
      // Judge the text at the width it has while the button is shown. The
      // button narrows the field, and a long unbreakable word can then wrap
      // onto fewer lines, so measuring the current width would let the
      // button toggle itself on and off every frame.
      final buttonWidth = _canExpand
          ? editable.size.width
          : editable.size.width -
                (_expandButtonExtent + AppSpacing.xs - AppSpacing.md);
      // With the button already present, the field has exactly buttonWidth.
      // Reuse its completed layout instead of shaping the whole draft again.
      // Only the initial probe needs to measure the hypothetical narrower field.
      final height = _canExpand
          ? editable.size.height + editable.maxScrollExtent
          : editable.getMaxIntrinsicHeight(buttonWidth);
      final canExpand = height > editable.preferredLineHeight * 2.5;
      if (canExpand != _canExpand) setState(() => _canExpand = canExpand);
    });
  }

  void _setExpanded(bool expanded) {
    if (expanded == _isExpanded) return;
    // The field keeps focus across the toggle, so a context menu would stay
    // open while the text under it jumps.
    ContextMenuController.removeAny();
    _longEditorKey.currentState?.hideToolbar();
    final composer = _composerKey.currentContext?.findRenderObject();
    final textArea = _textAreaKey.currentContext?.findRenderObject();
    final editable = _findRenderEditable();
    if (composer is RenderBox &&
        composer.hasSize &&
        textArea is RenderBox &&
        textArea.hasSize &&
        editable != null &&
        editable.hasSize) {
      if (!expanded) {
        // Animate back to exactly the height the collapsed field will take
        // for the current text, which may differ from where expansion began.
        final line = editable.preferredLineHeight;
        final collapsedText = editable
            .getMaxIntrinsicHeight(editable.size.width)
            .clamp(line, line * _collapsedMaxLines);
        _expandFromHeight =
            composer.size.height -
            textArea.size.height +
            _textAreaChrome +
            collapsedText;
      } else if (_expandController.isDismissed) {
        _expandFromHeight = composer.size.height;
        _textAreaChrome = textArea.size.height - editable.size.height;
      }
    } else if (composer is RenderBox &&
        composer.hasSize &&
        textArea is RenderBox &&
        textArea.hasSize &&
        (_longEditorKey.currentState?.usesLineEditor ?? false)) {
      final collapsedText =
          _longEditorKey.currentState!.preferredLineHeight * _collapsedMaxLines;
      if (!expanded) {
        _expandFromHeight =
            composer.size.height -
            textArea.size.height +
            _textAreaChrome +
            collapsedText;
      } else if (_expandController.isDismissed) {
        _expandFromHeight = composer.size.height;
        _textAreaChrome = textArea.size.height - collapsedText;
      }
    }
    if (expanded && _expandController.isDismissed) {
      widget.onExpandedChanged?.call(true);
    }
    setState(() => _isExpanded = expanded);
    if (expanded) {
      _expandController.forward();
      widget.focusNode?.requestFocus();
    } else {
      _expandController.reverse();
    }
  }

  void _handleExpandStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed) {
      _ensureCaretVisible();
    } else if (status == AnimationStatus.dismissed) {
      setState(() {});
      widget.onExpandedChanged?.call(false);
    }
  }

  void _handleExpandedPop(bool didPop, Object? _) {
    // An open drawer's own PopScope takes this back press; Flutter notifies
    // every PopScope, so collapsing too would spend one press on two things.
    if (didPop || !(_hostDrawer?.isClosed ?? true)) return;
    _setExpanded(false);
  }

  // ---------------------------------------------------------------------------
  // Voice input
  // ---------------------------------------------------------------------------

  Future<void> _handleSend() async {
    if (_composerLocked ||
        _isSubmitting ||
        _hasUnreadyImages ||
        _ownsVoiceSession ||
        _finishingVoice) {
      return;
    }
    if (widget.mediaController?.draftStore != null &&
        _docs.any(
          (doc) =>
              !isRemoteOrDataUri(doc.path) &&
              !File(SandboxPathResolver.fix(doc.path)).existsSync(),
        )) {
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context)!.composerDraftMissingFile,
        type: NotificationType.warning,
      );
      return;
    }
    final submittedValue = _controller.value;
    final submittedText = submittedValue.text;
    final text = submittedText.trim();
    if (text.isEmpty && _images.isEmpty && _docs.isEmpty) return;
    final submittedImages = List<_DraftImage>.of(_images);
    final submittedImageIds = submittedImages.map((image) => image.id).toSet();
    final submittedDocuments = List<DocumentAttachment>.of(_docs);
    final submittedDraft = _snapshotDraft(submittedText);
    final submittedDraftRevision = _draftReplacementRevision;
    final submitSerial = ++_submitSerial;
    _isSubmitting = true;
    final beginSubmission = widget.mediaController?.onBeginSubmission;
    Future<DraftSubmission?>? pendingSubmission;
    var persistentSubmission = false;
    try {
      pendingSubmission = beginSubmission?.call(submittedDraft);
      persistentSubmission =
          widget.mediaController?.draftStore
              ?.peek(widget.mediaController?.draftOwnerId ?? '')
              ?.pending !=
          null;
    } catch (_) {
      _isSubmitting = false;
      return;
    }
    // Attachments leave the composer with the text, not when the send future
    // completes: that future now resolves at send time, but the draft must not
    // depend on it at all. A rejected send puts everything back below.
    setState(() {
      _longEditorKey = GlobalKey<LongMessageEditorState>();
      _controller.clear();
      _images.removeWhere((image) => submittedImageIds.contains(image.id));
      for (final document in submittedDocuments) {
        _docs.remove(document);
      }
    });
    try {
      final draftSubmission = await pendingSubmission;
      final result =
          await widget.onSend?.call(
            ChatInputData(
              text: text,
              imagePaths: submittedImages.map((image) => image.path).toList(),
              documents: List<DocumentAttachment>.of(submittedDocuments),
              allowImagesApiRouting: submittedDraft.allowImagesApiRouting,
              draftSubmission: draftSubmission,
            ),
          ) ??
          ChatInputSubmissionResult.rejected;
      if (!mounted || submitSerial != _submitSerial) return;
      if (result == ChatInputSubmissionResult.sent ||
          result == ChatInputSubmissionResult.queued) {
        if (_draftReplacementRevision != submittedDraftRevision) return;
        widget.mediaController?.sharedDraftAction.value = null;
        _discardImageState(submittedImageIds);
        setState(() {});
        // Collapse once the cleared text is laid out, so the animation lands
        // on the empty field's height. A rejected send keeps the editor open
        // for the restored draft.
        if (_isExpanded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _setExpanded(false);
          });
        }
        // Keep focus on desktop so user can continue typing
        try {
          if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
            widget.focusNode?.requestFocus();
          }
        } catch (_) {}
      } else if (!persistentSubmission &&
          _draftReplacementRevision == submittedDraftRevision) {
        setState(
          () => _restoreSubmittedDraft(
            submittedValue,
            submittedImages,
            submittedDocuments,
          ),
        );
      }
    } catch (_) {
      if (!persistentSubmission &&
          mounted &&
          submitSerial == _submitSerial &&
          _draftReplacementRevision == submittedDraftRevision) {
        setState(
          () => _restoreSubmittedDraft(
            submittedValue,
            submittedImages,
            submittedDocuments,
          ),
        );
      }
      // Persistent submissions report storage errors next to the editor.
      if (!persistentSubmission) rethrow;
    } finally {
      if (submitSerial == _submitSerial) {
        _isSubmitting = false;
      }
    }
  }

  /// Puts a rejected submission back into the composer: text first, then the
  /// attachments ahead of anything added while the send was in flight.
  void _restoreSubmittedDraft(
    TextEditingValue submittedValue,
    List<_DraftImage> submittedImages,
    List<DocumentAttachment> submittedDocuments,
  ) {
    _restoreSubmittedText(submittedValue);
    final existingImageIds = _images.map((image) => image.id).toSet();
    _images.insertAll(
      0,
      submittedImages.where((image) => !existingImageIds.contains(image.id)),
    );
    _docs.insertAll(
      0,
      submittedDocuments.where((document) => !_docs.contains(document)),
    );
  }

  void _restoreSubmittedText(TextEditingValue submittedValue) {
    final currentValue = _controller.value;
    if (currentValue.text.isEmpty) {
      _controller.value = submittedValue;
      return;
    }
    final offset = submittedValue.text.length;
    final selection = currentValue.selection.isValid
        ? currentValue.selection.copyWith(
            baseOffset: currentValue.selection.baseOffset + offset,
            extentOffset: currentValue.selection.extentOffset + offset,
          )
        : currentValue.selection;
    final composing = currentValue.composing.isValid
        ? TextRange(
            start: currentValue.composing.start + offset,
            end: currentValue.composing.end + offset,
          )
        : currentValue.composing;
    _controller.value = currentValue.copyWith(
      text: submittedValue.text + currentValue.text,
      selection: selection,
      composing: composing,
    );
  }

  void _insertNewlineAtCursor() {
    final value = _controller.value;
    final selection = value.selection;
    final text = value.text;
    if (!selection.isValid) {
      _controller.text = '$text\n';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    } else {
      final start = selection.start;
      final end = selection.end;
      final newText = text.replaceRange(start, end, '\n');
      _controller.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + 1),
        composing: TextRange.empty,
      );
    }
    setState(() {});
    _ensureCaretVisible();
  }

  // Keep the caret visible after programmatic edits (e.g., Shift+Enter insert)
  void _ensureCaretVisible() {
    if (_longEditorKey.currentState?.usesLineEditor ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _longEditorKey.currentState?.ensureCaretVisible();
      });
      return;
    }
    try {
      final selection = _controller.selection;
      if (!selection.isValid) return;
      final focusNode = widget.focusNode ?? Focus.maybeOf(context);
      final focusContext = focusNode?.context;
      if (focusContext == null) return;
      final editable = focusContext
          .findAncestorStateOfType<EditableTextState>();
      if (editable == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          editable.bringIntoView(selection.extent);
        } catch (_) {}
      });
    } catch (_) {}
  }

  // Instance method for contextMenuBuilder to avoid flickering caused by recreating
  // the callback on every build. See: https://github.com/flutter/flutter/issues/150551
  Widget _buildMessageContextMenu(
    BuildContext context,
    TextSelectionToolbarAnchors anchors,
    List<ContextMenuButtonItem> defaultItems,
    VoidCallback hideToolbar,
  ) {
    // Suppress context menu during app lifecycle transitions to avoid flickering
    if (_suppressContextMenu) {
      return const SizedBox.shrink();
    }
    if (Platform.isIOS) {
      final items = <ContextMenuButtonItem>[];
      try {
        final appL10n = AppLocalizations.of(context)!;
        final materialL10n = MaterialLocalizations.of(context);
        final value = _controller.value;
        final selection = value.selection;
        final hasSelection = selection.isValid && !selection.isCollapsed;
        final hasText = value.text.isNotEmpty;

        // Cut
        if (hasSelection) {
          items.add(
            ContextMenuButtonItem(
              onPressed: () async {
                try {
                  final start = selection.start;
                  final end = selection.end;
                  final text = value.text.substring(start, end);
                  await Clipboard.setData(ClipboardData(text: text));
                  final newText = value.text.replaceRange(start, end, '');
                  _controller.value = value.copyWith(
                    text: newText,
                    selection: TextSelection.collapsed(offset: start),
                  );
                } catch (_) {}
                hideToolbar();
              },
              label: materialL10n.cutButtonLabel,
            ),
          );
        }

        // Copy
        if (hasSelection) {
          items.add(
            ContextMenuButtonItem(
              onPressed: () async {
                try {
                  final start = selection.start;
                  final end = selection.end;
                  final text = value.text.substring(start, end);
                  await Clipboard.setData(ClipboardData(text: text));
                } catch (_) {}
                hideToolbar();
              },
              label: materialL10n.copyButtonLabel,
            ),
          );
        }

        // Paste (text or image via _handlePasteFromClipboard)
        items.add(
          ContextMenuButtonItem(
            onPressed: () {
              _handlePasteFromClipboard();
              hideToolbar();
            },
            label: materialL10n.pasteButtonLabel,
          ),
        );

        // Insert newline
        items.add(
          ContextMenuButtonItem(
            onPressed: () {
              _insertNewlineAtCursor();
              hideToolbar();
            },
            label: appL10n.chatInputBarInsertNewline,
          ),
        );

        // Select all
        if (hasText) {
          items.add(
            ContextMenuButtonItem(
              onPressed: () {
                try {
                  _controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: value.text.length,
                  );
                } catch (_) {}
                hideToolbar();
              },
              label: materialL10n.selectAllButtonLabel,
            ),
          );
        }
      } catch (_) {}
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: anchors,
        buttonItems: items,
      );
    }

    final items = defaultItems
        .map((item) {
          if (item.type != ContextMenuButtonType.paste) return item;
          return item.copyWith(
            onPressed: () {
              unawaited(_handlePasteFromClipboard());
              hideToolbar();
            },
          );
        })
        .toList(growable: false);
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: items,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Enhance hardware keyboard behavior
    final w = MediaQuery.sizeOf(node.context!).width;
    final isTabletOrDesktop = w >= AppBreakpoints.tablet;
    final isIosTablet = Platform.isIOS && isTabletOrDesktop;

    final isDown = event is KeyDownEvent;
    final key = event.logicalKey;
    final isEnter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    final isArrow =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    final isPasteV = key == LogicalKeyboardKey.keyV;

    final imeComposing =
        _controller.value.composing.isValid &&
        !_controller.value.composing.isCollapsed;
    if (key == LogicalKeyboardKey.escape && _isExpanded && !imeComposing) {
      if (isDown) _setExpanded(false);
      return KeyEventResult.handled;
    }

    // Enter handling on tablet/desktop: configurable shortcut
    if (isEnter && isTabletOrDesktop) {
      if (!isDown) return KeyEventResult.handled; // ignore key up
      // Respect IME composition (e.g., Chinese Pinyin). If composing, let IME handle Enter.
      final composing = _controller.value.composing;
      final composingActive = composing.isValid && !composing.isCollapsed;
      if (composingActive) return KeyEventResult.ignored;
      final keys = HardwareKeyboard.instance.logicalKeysPressed;
      final shift =
          keys.contains(LogicalKeyboardKey.shiftLeft) ||
          keys.contains(LogicalKeyboardKey.shiftRight);
      final ctrl =
          keys.contains(LogicalKeyboardKey.controlLeft) ||
          keys.contains(LogicalKeyboardKey.controlRight);
      final meta =
          keys.contains(LogicalKeyboardKey.metaLeft) ||
          keys.contains(LogicalKeyboardKey.metaRight);
      final ctrlOrMeta = ctrl || meta;
      // Get send shortcut setting
      final sendShortcut = Provider.of<SettingsProvider>(
        node.context!,
        listen: false,
      ).desktopSendShortcut;
      if (sendShortcut == DesktopSendShortcut.ctrlEnter) {
        // Ctrl/Cmd+Enter to send, Enter to newline
        if (ctrlOrMeta) {
          unawaited(_handleSend());
        } else if (!shift) {
          _insertNewlineAtCursor();
        } else {
          // Shift+Enter also newline
          _insertNewlineAtCursor();
        }
      } else {
        // Enter to send, Shift+Enter or Ctrl/Cmd+Enter to newline (default)
        if (shift || ctrlOrMeta) {
          _insertNewlineAtCursor();
        } else {
          unawaited(_handleSend());
        }
      }
      return KeyEventResult.handled;
    }

    // Paste handling for images on iOS/macOS (tablet/desktop)
    if (isDown && isPasteV) {
      final keys = HardwareKeyboard.instance.logicalKeysPressed;
      final meta =
          keys.contains(LogicalKeyboardKey.metaLeft) ||
          keys.contains(LogicalKeyboardKey.metaRight);
      final ctrl =
          keys.contains(LogicalKeyboardKey.controlLeft) ||
          keys.contains(LogicalKeyboardKey.controlRight);
      if (meta || ctrl) {
        _handlePasteFromClipboard();
        return KeyEventResult.handled;
      }
    }

    // Arrow repeat fix only needed on iOS tablets
    if (!isIosTablet || !isArrow) return KeyEventResult.ignored;

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final shift =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final alt =
        keys.contains(LogicalKeyboardKey.altLeft) ||
        keys.contains(LogicalKeyboardKey.altRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);

    void moveOnce() {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _moveCaret(-1, extend: shift, byWord: alt);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _moveCaret(1, extend: shift, byWord: alt);
      }
    }

    if (event is KeyDownEvent) {
      // Initial move
      moveOnce();
      // Start repeat timer if not already
      if (!_repeatTimers.containsKey(key)) {
        Timer? periodic;
        final starter = Timer(_repeatInitialDelay, () {
          periodic = Timer.periodic(_repeatPeriod, (_) => moveOnce());
          _repeatTimers[key] = periodic!;
        });
        // Store starter temporarily; replace when periodic begins
        _repeatTimers[key] = starter;
      }
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      // Key up -> cancel repeat
      final t = _repeatTimers.remove(key);
      try {
        t?.cancel();
      } catch (_) {}
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  Future<String?> _savePastedImageBytes(
    String format,
    Uint8List bytes, {
    ChatInputBarController? target,
  }) async {
    File? reserved;
    try {
      final dir = await (target?._root.draftStore != null
          ? target!.uploadDirectory()
          : AppDirectories.getSystemCacheDirectory());
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final ext = format.toLowerCase();
      final fileExt = ext == 'jpeg' ? 'jpg' : ext;
      final baseName = 'paste_${DateTime.now().millisecondsSinceEpoch}';
      var counter = 0;
      while (true) {
        final suffix = counter == 0 ? '' : '_$counter';
        final file = File(p.join(dir.path, '$baseName$suffix.$fileExt'));
        try {
          await file.create(exclusive: true);
          reserved = file;
          break;
        } on FileSystemException {
          if (!await file.exists()) rethrow;
          counter++;
        }
      }
      await reserved.writeAsBytes(bytes, flush: true);
      return reserved.path;
    } catch (_) {
      if (reserved != null) await _deleteTemporaryImageSource(reserved.path);
      return null;
    }
  }

  Future<void> _deleteTemporaryImageSource(String path) async {
    try {
      await File(path).delete();
    } catch (error) {
      debugPrint(
        '[ChatInputBar] Failed to delete temporary image $path: $error',
      );
    }
  }

  void _handleInsertedContent(KeyboardInsertedContent content) {
    if (widget.mediaController?.restoringDraft ?? false) return;
    final format = switch (content.mimeType.toLowerCase()) {
      'image/png' => 'png',
      'image/jpeg' || 'image/jpg' => 'jpeg',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      _ => null,
    };
    final bytes = content.data;
    if (!mounted || format == null || bytes == null || bytes.isEmpty) return;
    final pasteId = _nextImagePasteId++;
    setState(() => _pendingImagePasteIds.add(pasteId));
    unawaited(
      _enqueueInsertedImage(
        pasteId,
        format,
        bytes,
        widget.mediaController?.capture(),
        context.read<SettingsProvider>().resolveImageCompressConfig(),
      ),
    );
  }

  Future<void> _enqueueInsertedImage(
    int pasteId,
    String format,
    Uint8List bytes,
    ChatInputBarController? target,
    ImageCompressConfig compressConfig,
  ) async {
    final savedPath = await _savePastedImageBytes(
      format,
      bytes,
      target: target,
    );
    if (savedPath == null) {
      if (mounted && _pendingImagePasteIds.contains(pasteId)) {
        setState(() => _pendingImagePasteIds.remove(pasteId));
      }
      return;
    }
    final retained = target?._root.draftStore != null && target!.isValid;
    if (!retained && (!mounted || !_pendingImagePasteIds.contains(pasteId))) {
      await _deleteTemporaryImageSource(savedPath);
      return;
    }
    _pendingImagePasteIds.remove(pasteId);
    (target?.enqueueImages ?? _enqueueImages)(
      [savedPath],
      compressConfig,
      deleteSourcesAfterProcessing: true,
    );
  }

  Future<void> _handlePasteFromClipboard() async {
    if (widget.mediaController?.restoringDraft ?? false) return;
    final target = widget.mediaController?.capture();
    final compressConfig = context
        .read<SettingsProvider>()
        .resolveImageCompressConfig();

    // 1) Prefer reading via super_clipboard for better Windows support
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final reader = await clipboard.read();

        // Helper: read bytes for a given file format from DataReader (ClipboardReader or item)
        Future<Uint8List?> readFileBytes(
          DataReader dataReader,
          FileFormat format,
        ) async {
          try {
            final completer = Completer<Uint8List?>();
            final progress = dataReader.getFile(
              format,
              (file) async {
                try {
                  final bytes = await file.readAll();
                  if (!completer.isCompleted) completer.complete(bytes);
                } catch (e) {
                  if (!completer.isCompleted) completer.completeError(e);
                }
              },
              onError: (e) {
                if (!completer.isCompleted) completer.completeError(e);
              },
            );
            if (progress == null) {
              if (!completer.isCompleted) completer.complete(null);
            }
            return await completer.future;
          } catch (_) {
            return null;
          }
        }

        // Try aggregated formats in priority: png > jpeg > gif > webp
        Uint8List? bytes;
        String? fmt;
        if (reader.canProvide(Formats.png)) {
          bytes = await readFileBytes(reader, Formats.png);
          fmt = 'png';
        }
        bytes ??= reader.canProvide(Formats.jpeg)
            ? await readFileBytes(reader, Formats.jpeg)
            : null;
        fmt = (bytes != null && fmt == null) ? 'jpeg' : fmt;
        if (bytes == null && reader.canProvide(Formats.gif)) {
          bytes = await readFileBytes(reader, Formats.gif);
          fmt = 'gif';
        }
        if (bytes == null && reader.canProvide(Formats.webp)) {
          bytes = await readFileBytes(reader, Formats.webp);
          fmt = 'webp';
        }

        if (bytes == null) {
          // Try per-item formats
          for (final item in reader.items) {
            if (bytes == null && item.canProvide(Formats.png)) {
              bytes = await readFileBytes(item, Formats.png);
              fmt = 'png';
            }
            if (bytes == null && item.canProvide(Formats.jpeg)) {
              bytes = await readFileBytes(item, Formats.jpeg);
              fmt = 'jpeg';
            }
            if (bytes == null && item.canProvide(Formats.gif)) {
              bytes = await readFileBytes(item, Formats.gif);
              fmt = 'gif';
            }
            if (bytes == null && item.canProvide(Formats.webp)) {
              bytes = await readFileBytes(item, Formats.webp);
              fmt = 'webp';
            }
            if (bytes != null) break;
          }
        }

        if (bytes != null && bytes.isNotEmpty && fmt != null) {
          final savedPath = await _savePastedImageBytes(
            fmt,
            bytes,
            target: target,
          );
          if (!mounted) {
            if (savedPath != null) {
              await _deleteTemporaryImageSource(savedPath);
            }
            return;
          }
          if (savedPath != null) {
            (target?.enqueueImages ?? _enqueueImages)(
              [savedPath],
              compressConfig,
              deleteSourcesAfterProcessing: true,
            );
            return;
          }
        }

        // If clipboard has plain text via super_clipboard, paste it
        if (reader.canProvide(Formats.plainText)) {
          try {
            final String? text = await reader.readValue(Formats.plainText);
            if (text != null && text.isNotEmpty) {
              await _handlePastedText(text, target: target);
              return;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 2) Fallback: legacy platform channel image handling
    final imageTempPaths = await ClipboardImages.getImagePaths();
    if (imageTempPaths.isNotEmpty) {
      if (target != null) {
        target.enqueueImages(
          imageTempPaths,
          compressConfig,
          deleteSourcesAfterProcessing: true,
        );
      } else {
        await _enqueueClipboardImages(imageTempPaths);
      }
      return;
    }

    // 3) Try files via platform channel on desktop (Finder/Explorer copies)
    bool handledFiles = false;
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final filePaths = await ClipboardImages.getFilePaths();
        if (filePaths.isNotEmpty) {
          final imagePaths = <String>[];
          final otherPaths = <String>[];
          for (final raw in filePaths) {
            final src = raw.startsWith('file://') ? raw.substring(7) : raw;
            if (_isImageExtension(p.basename(src))) {
              imagePaths.add(src);
            } else {
              otherPaths.add(src);
            }
          }
          (target?.enqueueImages ?? _enqueueImages)(
            imagePaths,
            compressConfig,
            deleteSourcesAfterProcessing: false,
          );

          final saved = await _copyFilesToUpload(otherPaths, target: target);
          if (saved.images.isNotEmpty) {
            (target?.enqueueImages ?? _enqueueImages)(
              saved.images,
              compressConfig,
              deleteSourcesAfterProcessing: false,
            );
          }
          if (saved.docs.isNotEmpty) {
            if (target != null) {
              target.addFiles(saved.docs);
            } else {
              _addFiles(saved.docs);
            }
          }
          handledFiles =
              imagePaths.isNotEmpty ||
              saved.images.isNotEmpty ||
              saved.docs.isNotEmpty;
        }
      }
    } catch (_) {}
    if (handledFiles) return;

    // 4) Last resort: paste text via Flutter Clipboard API
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isEmpty) return;
      await _handlePastedText(text, target: target);
    } catch (_) {}
  }

  Future<void> _handlePastedText(
    String text, {
    ChatInputBarController? target,
  }) async {
    target ??= widget.mediaController?.capture();
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    final threshold = settings.longPasteAsFileThreshold;
    final isLongPaste =
        settings.longPasteAsFile &&
        text.characters.take(threshold + 1).length > threshold;
    if (!isLongPaste) {
      if (target != null) {
        target.insertText(text);
      } else {
        _insertPastedText(text);
      }
      return;
    }

    if (!mounted) return;
    final pasteId = _nextTextPasteId++;
    setState(() => _pendingTextPasteIds.add(pasteId));
    final previousWrite = _textPasteWriteTail;
    final writeDone = Completer<void>();
    _textPasteWriteTail = writeDone.future;

    try {
      await previousWrite;
      final retained = target?._root.draftStore != null && target!.isValid;
      if (!retained && (!mounted || !_pendingTextPasteIds.contains(pasteId))) {
        return;
      }

      File? file;
      DocumentAttachment? attachment;
      try {
        final dir =
            await (target?.uploadDirectory() ??
                AppDirectories.getUploadDirectory());
        await dir.create(recursive: true);
        file = await _reservePastedTextFile(dir);
        await file.writeAsString(text, flush: true);
        attachment = DocumentAttachment(
          path: file.path,
          fileName: p.basename(file.path),
          mime: 'text/plain',
        );
      } catch (_) {}

      if (attachment != null &&
          ((retained && target.isValid) ||
              (mounted && _pendingTextPasteIds.contains(pasteId)))) {
        if (mounted) setState(() => _pendingTextPasteIds.remove(pasteId));
        if (target != null) {
          target.addFiles([attachment]);
        } else {
          setState(() => _docs.add(attachment!));
        }
        return;
      }

      await _deleteUnclaimedPastedText(file);
      if (retained && target.isValid) {
        if (mounted) setState(() => _pendingTextPasteIds.remove(pasteId));
        target.insertText(text);
        return;
      }
      if (!mounted || !_pendingTextPasteIds.contains(pasteId)) return;
      setState(() => _pendingTextPasteIds.remove(pasteId));
      _insertPastedText(text);
    } finally {
      writeDone.complete();
    }
  }

  void _insertPastedText(String text) {
    if (!mounted) return;
    final value = _controller.value;
    final selection = value.selection;
    if (!selection.isValid) {
      _controller.text = value.text + text;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    } else {
      final start = selection.start;
      final end = selection.end;
      final newText = value.text.replaceRange(start, end, text);
      _controller.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + text.length),
        composing: TextRange.empty,
      );
    }
    setState(() {});
  }

  Future<File> _reservePastedTextFile(Directory dir) async {
    final baseName = 'pasted_${DateTime.now().millisecondsSinceEpoch}';
    var counter = 0;
    while (true) {
      final suffix = counter == 0 ? '' : '($counter)';
      final file = File(p.join(dir.path, '$baseName$suffix.txt'));
      try {
        return await file.create(exclusive: true);
      } on FileSystemException {
        if (!await file.exists()) rethrow;
        counter++;
      }
    }
  }

  Future<void> _deleteUnclaimedPastedText(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint(
        '[ChatInputBar] Failed to delete unclaimed pasted text ${file.path}: $error',
      );
    }
  }

  // Copy arbitrary files to upload directory (without deleting the source),
  // split into images and document attachments.
  Future<({List<String> images, List<DocumentAttachment> docs})>
  _copyFilesToUpload(
    List<String> srcPaths, {
    ChatInputBarController? target,
  }) async {
    final images = <String>[];
    final docs = <DocumentAttachment>[];
    try {
      final dir =
          await (target?.uploadDirectory() ??
              widget.mediaController?.uploadDirectory() ??
              AppDirectories.getUploadDirectory());
      for (final raw in srcPaths) {
        if (!mounted) {
          return (images: images, docs: docs);
        }
        final src = raw.startsWith('file://') ? raw.substring(7) : raw;
        if (_isImageExtension(p.basename(src))) {
          images.add(src);
          continue;
        }
        final savedPath = await FileImportHelper.copyXFile(XFile(src), dir);
        if (savedPath != null) {
          final savedName = p.basename(savedPath);
          if (_isImageExtension(savedName)) {
            images.add(savedPath);
          } else {
            final mime = _inferMimeByExtension(savedName);
            docs.add(
              DocumentAttachment(
                path: savedPath,
                fileName: savedName,
                mime: mime,
              ),
            );
          }
        }
      }
    } catch (_) {}
    return (images: images, docs: docs);
  }

  String _inferMimeByExtension(String name) {
    final mediaMime = inferMediaMimeFromSource(name);
    if (mediaMime.isNotEmpty) return mediaMime;
    final lower = name.toLowerCase();
    // Documents / text
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.js')) return 'application/javascript';
    if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.markdown') ||
        lower.endsWith('.mdx')) {
      return 'text/plain';
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.xml')) return 'application/xml';
    if (lower.endsWith('.yml') || lower.endsWith('.yaml')) {
      return 'application/x-yaml';
    }
    if (lower.endsWith('.py')) return 'text/x-python';
    if (lower.endsWith('.java')) return 'text/x-java-source';
    if (lower.endsWith('.kt') || lower.endsWith('.kts')) return 'text/x-kotlin';
    if (lower.endsWith('.dart')) return 'text/x-dart';
    if (lower.endsWith('.ts')) return 'text/typescript';
    if (lower.endsWith('.tsx')) return 'text/tsx';
    return 'application/octet-stream';
  }

  bool _isImageExtension(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  Future<void> _enqueueClipboardImages(List<String> srcPaths) async {
    try {
      final compressConfig = context
          .read<SettingsProvider>()
          .resolveImageCompressConfig();
      final ready = <String>[];
      final temporary = <String>[];
      for (var raw in srcPaths) {
        try {
          // Normalize path (strip file:// if present)
          final src = raw.startsWith('file://') ? raw.substring(7) : raw;
          // If already under upload directory, just keep it
          if (src.contains('/upload/') || src.contains('\\upload\\')) {
            ready.add(src);
            continue;
          }
          if (await File(src).exists()) temporary.add(src);
        } catch (_) {
          // skip single file errors
        }
      }
      _addImages(ready);
      _enqueueImages(
        temporary,
        compressConfig,
        deleteSourcesAfterProcessing: true,
      );
    } catch (_) {}
  }

  void _moveCaret(int dir, {bool extend = false, bool byWord = false}) {
    final text = _controller.text;
    if (text.isEmpty) return;
    TextSelection sel = _controller.selection;
    if (!sel.isValid) {
      final off = dir < 0 ? text.length : 0;
      _controller.selection = TextSelection.collapsed(offset: off);
      return;
    }

    int nextOffset(int from, int direction) {
      if (!byWord) return (from + direction).clamp(0, text.length);
      // Move by simple word boundary: skip whitespace; then skip non-whitespace
      int i = from;
      if (direction < 0) {
        // Move left
        while (i > 0 && text[i - 1].trim().isEmpty) {
          i--;
        }
        while (i > 0 && text[i - 1].trim().isNotEmpty) {
          i--;
        }
      } else {
        // Move right
        while (i < text.length && text[i].trim().isEmpty) {
          i++;
        }
        while (i < text.length && text[i].trim().isNotEmpty) {
          i++;
        }
      }
      return i.clamp(0, text.length);
    }

    if (extend) {
      final newExtent = nextOffset(sel.extentOffset, dir);
      _controller.selection = sel.copyWith(extentOffset: newExtent);
    } else {
      final base = dir < 0 ? sel.start : sel.end;
      final collapsed = nextOffset(base, dir);
      _controller.selection = TextSelection.collapsed(offset: collapsed);
    }
    setState(() {});
  }

  Widget _buildImageAttachmentPreview(
    BuildContext context,
    int idx,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final previewFill = theme.colorScheme.onSurface.withValues(alpha: 0.045);
    final previewBorder = theme.colorScheme.onSurface.withValues(alpha: 0.07);
    final image = _images[idx];
    final processing = _processingImageIds.contains(image.id);
    final failed = !processing && _failedImageIds.contains(image.id);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: previewBorder, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: processing
                ? ColoredBox(
                    color: theme.colorScheme.scrim,
                    child: const SizedBox(width: 88, height: 88),
                  )
                : Image(
                    image: ResizeImage(
                      FileImage(File(image.path)),
                      width: (88 * MediaQuery.devicePixelRatioOf(context))
                          .ceil(),
                      height: (88 * MediaQuery.devicePixelRatioOf(context))
                          .ceil(),
                      policy: ResizeImagePolicy.fit,
                    ),
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 88,
                      height: 88,
                      color: previewFill,
                      child: Icon(
                        Icons.broken_image,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: processing
                ? IgnorePointer(
                    key: ValueKey('chat-input-image-processing:${image.id}'),
                    child: Tooltip(
                      message: l10n.chatInputBarImageProcessing,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.scrim.withValues(
                            alpha: 0.32,
                          ),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors
                                  .white, // color-gate: ignore (on scrim over photo)
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('image-idle')),
          ),
        ),
        if (failed)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.priority_high,
                size: 12,
                color: theme.colorScheme.onTertiary,
              ),
            ),
          ),
        Positioned(
          right: 4,
          top: 4,
          child: IosCardPress(
            key: ValueKey('chat-input-image-remove:$idx'),
            haptics: false,
            baseColor: theme.colorScheme.scrim.withValues(
              alpha: isDark ? 0.50 : 0.46,
            ),
            pressedScale: 0.94,
            borderRadius: BorderRadius.circular(_imageRemoveButtonSize / 2),
            padding: EdgeInsets.zero,
            duration: const Duration(milliseconds: 140),
            onTap: () => _removeImageAt(idx),
            child: const SizedBox(
              width: _imageRemoveButtonSize,
              height: _imageRemoveButtonSize,
              child: Icon(
                Icons.close,
                size: 11,
                color: Colors.white, // color-gate: ignore (on scrim over photo)
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineAttachmentPreviews(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xxs,
      ),
      child: SizedBox(
        height: ComposerAttachmentCard.heightFor(context),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _images.length + _docs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            if (index < _images.length) {
              return KeyedSubtree(
                key: index == 0
                    ? const ValueKey('chat-input-image-previews')
                    : ValueKey(_images[index].id),
                child: _buildImageAttachmentPreview(context, index, isDark),
              );
            }
            final docIndex = index - _images.length;
            final file = _docs[docIndex];
            return KeyedSubtree(
              key: docIndex == 0
                  ? const ValueKey('chat-input-document-previews')
                  : ValueKey(file.path),
              child: ComposerAttachmentCard(
                key: ValueKey(file.path),
                file: file,
                removeKey: ValueKey('chat-input-document-remove:$docIndex'),
                onRemove: () => _removeDocumentAt(docIndex),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasText = _controller.text.trim().isNotEmpty;
    final hasImages = _images.isNotEmpty;
    final hasDocs = _docs.isNotEmpty;
    final hasInput = hasText || hasImages || hasDocs;
    _supportsImagesApiRouting(context);
    final bool isMobileLayout =
        MediaQuery.sizeOf(context).width < AppBreakpoints.tablet;
    final expandedLayout = _expandedLayout;
    if (!expandedLayout) _scheduleExpandCheck();
    _hostDrawer = InteractiveDrawer.maybeControllerOf(context);

    return PopScope(
      canPop: !_isExpanded,
      onPopInvokedWithResult: _handleExpandedPop,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_docs.any((doc) => _missingDocumentPaths.contains(doc.path)))
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    AppLocalizations.of(context)!.composerDraftMissingFile,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (widget.mediaController?.draftStore?.errors.containsKey(
                    widget.conversationId,
                  ) ??
                  false)
                _QueuedInputBanner(
                  label: AppLocalizations.of(context)!.composerDraftSaveFailed,
                  cancelLabel: AppLocalizations.of(context)!.composerDraftRetry,
                  onCancel: widget.mediaController?.onRetrySave,
                ),
              if (!widget.hasQueuedInput &&
                  !(widget.mediaController?.draftStore?.submitting.contains(
                        widget.mediaController?.draftOwnerId,
                      ) ??
                      false) &&
                  (widget.mediaController?.draftStore
                          ?.peek(widget.mediaController?.draftOwnerId ?? '')
                          ?.pending !=
                      null))
                Row(
                  children: [
                    Expanded(
                      child: _QueuedInputBanner(
                        label: AppLocalizations.of(
                          context,
                        )!.composerDraftRecovered,
                        cancelLabel: AppLocalizations.of(
                          context,
                        )!.composerDraftRestore,
                        onCancel: widget.mediaController?.onRecoverDraft,
                      ),
                    ),
                    IosIconButton(
                      icon: Lucide.Trash2,
                      tooltip: AppLocalizations.of(
                        context,
                      )!.composerDraftDiscard,
                      onTap: widget.mediaController?.onDiscardRecoveredDraft,
                    ),
                  ],
                ),
              if (widget.hasQueuedInput) ...[
                _QueuedInputBanner(
                  label: AppLocalizations.of(
                    context,
                  )!.chatInputBarQueuedPending,
                  previewText: widget.queuedPreviewText,
                  cancelLabel: AppLocalizations.of(
                    context,
                  )!.chatInputBarQueuedCancel,
                  onCancel: widget.onCancelQueuedInput,
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              Flexible(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Main input container with iOS-like frosted glass effect
                    _buildExpandingComposer(
                      expandedLayout,
                      Container(
                        key: _composerKey,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E1D)
                              : const Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF333330)
                                : const Color(0xFFE6E4DD),
                            width: 1.0,
                          ),
                          boxShadow: isDark
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.50),
                                    blurRadius: 28,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 10),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.07),
                                    blurRadius: 24,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 8),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.mediaController != null) ...[
                                  ValueListenableBuilder<ShareImportProgress?>(
                                    valueListenable:
                                        widget.mediaController!.shareImport,
                                    builder: (context, progress, _) =>
                                        progress == null
                                        ? const SizedBox.shrink()
                                        : ComposerImportProgress(
                                            progress: progress,
                                            onCancel: () => widget
                                                .mediaController!
                                                .cancelShareImport
                                                ?.call(),
                                          ),
                                  ),
                                  if (isMobileLayout &&
                                      (hasText || hasDocs || hasImages))
                                    ValueListenableBuilder<VoidCallback?>(
                                      valueListenable: widget
                                          .mediaController!
                                          .sharedDraftAction,
                                      builder: (context, onMove, _) =>
                                          onMove == null
                                          ? const SizedBox.shrink()
                                          : Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    12,
                                                    8,
                                                    8,
                                                    0,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Text(
                                                    AppLocalizations.of(
                                                      context,
                                                    )!.incomingShareTitle,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  IosCardPress(
                                                    onTap: onMove,
                                                    haptics: false,
                                                    baseColor:
                                                        Colors.transparent,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 6,
                                                        ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          AppLocalizations.of(
                                                            context,
                                                          )!.incomingShareMoveTo,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: theme
                                                                .colorScheme
                                                                .primary,
                                                            fontWeight:
                                                                AppFontWeights
                                                                    .medium,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Icon(
                                                          Lucide.ArrowRight,
                                                          size: 14,
                                                          color: theme
                                                              .colorScheme
                                                              .primary,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                    ),
                                ],
                                if (hasDocs || hasImages)
                                  _buildInlineAttachmentPreviews(
                                    context,
                                    isDark,
                                  ),
                                // Input field with expand/collapse button. The
                                // collapsed field may shrink when the host is short;
                                // the expanded one takes every spare pixel.
                                Flexible(
                                  fit: expandedLayout
                                      ? FlexFit.tight
                                      : FlexFit.loose,
                                  child: Stack(
                                    key: _textAreaKey,
                                    fit: expandedLayout
                                        ? StackFit.expand
                                        : StackFit.loose,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          20,
                                          16,
                                          20,
                                          8,
                                        ),
                                        child: Focus(
                                          onKeyEvent: _handleKeyEvent,
                                          child: Builder(
                                            builder: (ctx) {
                                              // Desktop: show a right-click context menu with paste/cut/copy/select all
                                              // Future<void> _showDesktopContextMenu(Offset globalPos) async {
                                              //   bool isDesktop = false;
                                              //   try { isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux; } catch (_) {}
                                              //   if (!isDesktop) return;
                                              //   // Ensure input has focus so operations apply correctly
                                              //   try { widget.focusNode?.requestFocus(); } catch (_) {}
                                              //
                                              //   final sel = _controller.selection;
                                              //   final hasSelection = sel.isValid && !sel.isCollapsed;
                                              //   final hasText = _controller.text.isNotEmpty;
                                              //
                                              //   final l10n = MaterialLocalizations.of(ctx);
                                              //   await showDesktopContextMenuAt(
                                              //     ctx,
                                              //     globalPosition: globalPos,
                                              //     items: [
                                              //       DesktopContextMenuItem(
                                              //         icon: Lucide.Clipboard,
                                              //         label: l10n.pasteButtonLabel,
                                              //         onTap: () async {
                                              //           await _handlePasteFromClipboard();
                                              //         },
                                              //       ),
                                              //       DesktopContextMenuItem(
                                              //         icon: Lucide.Cut,
                                              //         label: l10n.cutButtonLabel,
                                              //         onTap: () async {
                                              //           final s = _controller.selection;
                                              //           if (s.isValid && !s.isCollapsed) {
                                              //             final text = _controller.text.substring(s.start, s.end);
                                              //             try { await Clipboard.setData(ClipboardData(text: text)); } catch (_) {}
                                              //             final newText = _controller.text.replaceRange(s.start, s.end, '');
                                              //             _controller.value = TextEditingValue(
                                              //               text: newText,
                                              //               selection: TextSelection.collapsed(offset: s.start),
                                              //             );
                                              //             setState(() {});
                                              //           }
                                              //         },
                                              //       ),
                                              //       DesktopContextMenuItem(
                                              //         icon: Lucide.Copy,
                                              //         label: l10n.copyButtonLabel,
                                              //         onTap: () async {
                                              //           final s2 = _controller.selection;
                                              //           if (s2.isValid && !s2.isCollapsed) {
                                              //             final text = _controller.text.substring(s2.start, s2.end);
                                              //             try { await Clipboard.setData(ClipboardData(text: text)); } catch (_) {}
                                              //           }
                                              //         },
                                              //       ),
                                              //       // DesktopContextMenuItem(
                                              //       //   // icon: Lucide.TextSelect,
                                              //       //   label: l10n.selectAllButtonLabel,
                                              //       //   onTap: () {
                                              //       //     if (hasText) {
                                              //       //       _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
                                              //       //       setState(() {});
                                              //       //     }
                                              //       //   },
                                              //       // ),
                                              //     ],
                                              //   );
                                              // }

                                              final enterToSend = context
                                                  .watch<SettingsProvider>()
                                                  .enterToSendOnMobile;
                                              return GestureDetector(
                                                behavior: HitTestBehavior
                                                    .deferToChild,
                                                // onSecondaryTapDown: (details) {
                                                //   // _showDesktopContextMenu(details.globalPosition);
                                                // },
                                                child: LongMessageEditor(
                                                  key: _longEditorKey,
                                                  controller: _controller,
                                                  focusNode: widget.focusNode,
                                                  onChanged: _onTextChanged,
                                                  contentInsertionConfiguration:
                                                      ContentInsertionConfiguration(
                                                        onContentInserted:
                                                            _handleInsertedContent,
                                                        allowedMimeTypes:
                                                            const [
                                                              'image/png',
                                                              'image/jpeg',
                                                              'image/jpg',
                                                              'image/gif',
                                                              'image/webp',
                                                            ],
                                                      ),
                                                  readOnly:
                                                      _composerLocked ||
                                                      _ownsVoiceSession,
                                                  minLines: expandedLayout
                                                      ? null
                                                      : 1,
                                                  maxLines: expandedLayout
                                                      ? null
                                                      : _collapsedMaxLines,
                                                  expands: expandedLayout,
                                                  // On mobile, optionally show "Send" on the return key and submit on tap.
                                                  // Still keep multiline so pasted text preserves line breaks.
                                                  textInputAction: enterToSend
                                                      ? TextInputAction.send
                                                      : TextInputAction.newline,
                                                  onSubmitted: enterToSend
                                                      ? (_) => unawaited(
                                                          _handleSend(),
                                                        )
                                                      : null,
                                                  // Custom context menu: use instance method to avoid flickering
                                                  // caused by recreating the callback on every build.
                                                  // See: https://github.com/flutter/flutter/issues/150551
                                                  contextMenuBuilder:
                                                      _buildMessageContextMenu,
                                                  onKeyEvent: _handleKeyEvent,
                                                  autofocus: false,
                                                  decoration: InputDecoration(
                                                    hintText: _hint(context),
                                                    hintFadeDuration:
                                                        Duration.zero,
                                                    hintStyle: TextStyle(
                                                      color: isDark
                                                          ? const Color(
                                                              0xFF888884,
                                                            )
                                                          : const Color(
                                                              0xFF9E9D98,
                                                            ),
                                                      fontSize: 16.5,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                    ),
                                                    border: InputBorder.none,
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 2,
                                                        ),
                                                  ),
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? const Color(
                                                            0xFFEDEDEC,
                                                          )
                                                        : const Color(
                                                            0xFF141413,
                                                          ),
                                                    fontSize: 16.5,
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                  cursorColor: isDark
                                                      ? Colors.white
                                                      : Colors.black,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      if (expandedLayout || _canExpand)
                                        PositionedDirectional(
                                          top: 2,
                                          end: 6,
                                          // Inside both editors' tap regions, so
                                          // a non-touch pointer (mouse,
                                          // trackpad, stylus) or any desktop
                                          // click here is not a "tap outside"
                                          // that drops focus and bounces the
                                          // keyboard.
                                          child: CodeEditorTapRegion(
                                            child: TextFieldTapRegion(
                                              child: IosIconButton(
                                                icon: _isExpanded
                                                    ? Lucide.Minimize2
                                                    : Lucide.Maximize2,
                                                size: 16,
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.45),
                                                tooltip: _isExpanded
                                                    ? AppLocalizations.of(
                                                        context,
                                                      )!.chatInputBarCollapse
                                                    : AppLocalizations.of(
                                                        context,
                                                      )!.chatInputBarExpand,
                                                onTap: () =>
                                                    _setExpanded(!_isExpanded),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // Bottom buttons row: only left circular '+' and right circular Send/Stop
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    4,
                                    12,
                                    12,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Left button: 38x38 circular '+' button
                                      Semantics(
                                        button: true,
                                        label: 'Add attachment or options',
                                        child: InkWell(
                                          onTap: _composerLocked
                                              ? null
                                              : () {
                                                  if (widget.onMore != null) {
                                                    widget.onMore!();
                                                  } else if (widget
                                                              .onUploadFiles !=
                                                          null ||
                                                      widget.onPickPhotos !=
                                                          null) {
                                                    (widget.onUploadFiles ??
                                                        widget.onPickPhotos)!();
                                                  }
                                                },
                                          borderRadius: BorderRadius.circular(
                                            19,
                                          ),
                                          child: Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isDark
                                                  ? const Color(0xFF2C2C2A)
                                                  : const Color(0xFFF0EFEA),
                                            ),
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Lucide.Plus,
                                              size: 20,
                                              color: isDark
                                                  ? const Color(0xFFEDEDEC)
                                                  : const Color(0xFF141413),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Right button: 38x38 circular Send / Stop button
                                      Builder(
                                        builder: (context) {
                                          final bool isLoading = widget.loading;
                                          final bool canSend =
                                              hasInput &&
                                              !_composerLocked &&
                                              !_hasUnreadyImages;

                                          if (isLoading) {
                                            return Semantics(
                                              button: true,
                                              label: 'Stop generation',
                                              child: InkWell(
                                                onTap: widget.onStop,
                                                borderRadius:
                                                    BorderRadius.circular(19),
                                                child: Container(
                                                  width: 38,
                                                  height: 38,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: isDark
                                                        ? const Color(
                                                            0xFFFFFFFF,
                                                          )
                                                        : const Color(
                                                            0xFF0D0D0D,
                                                          ),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Container(
                                                    width: 14,
                                                    height: 14,
                                                    decoration: BoxDecoration(
                                                      color: isDark
                                                          ? const Color(
                                                              0xFF0A0A0A,
                                                            )
                                                          : const Color(
                                                              0xFFFFFFFF,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            2.5,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          } else if (canSend) {
                                            return Semantics(
                                              button: true,
                                              label:
                                                  widget.sendButtonTooltip ??
                                                  'Send message',
                                              child: InkWell(
                                                onTap: () =>
                                                    unawaited(_handleSend()),
                                                borderRadius:
                                                    BorderRadius.circular(19),
                                                child: Container(
                                                  width: 38,
                                                  height: 38,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: isDark
                                                        ? const Color(
                                                            0xFFFFFFFF,
                                                          )
                                                        : const Color(
                                                            0xFF0D0D0D,
                                                          ),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Icon(
                                                    Lucide.ArrowUp,
                                                    size: 20,
                                                    color: isDark
                                                        ? const Color(
                                                            0xFF0A0A0A,
                                                          )
                                                        : const Color(
                                                            0xFFFFFFFF,
                                                          ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          } else {
                                            return Semantics(
                                              button: false,
                                              label: 'Send message (disabled)',
                                              child: Container(
                                                width: 38,
                                                height: 38,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: isDark
                                                      ? const Color(0xFF2C2C2E)
                                                      : const Color(0xFFE5E5E5),
                                                ),
                                                alignment: Alignment.center,
                                                child: Icon(
                                                  Lucide.ArrowUp,
                                                  size: 20,
                                                  color: isDark
                                                      ? const Color(0xFF6E6E73)
                                                      : const Color(0xFF8E8E8E),
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_imageModeActive)
                      PositionedDirectional(
                        top: -12,
                        start: AppSpacing.sm,
                        child: _ImageModePill(
                          label: AppLocalizations.of(
                            context,
                          )!.chatInputBarImageMode,
                          closeTooltip: AppLocalizations.of(
                            context,
                          )!.chatInputBarDisableImageModeTooltip,
                          onClose: _composerLocked
                              ? null
                              : () {
                                  final key = _imageModeModelKey;
                                  if (key == null) return;
                                  setState(() {
                                    _dismissedImageModeModelKey = key;
                                  });
                                },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Keeps the collapsed composer at its natural height; while expanded it
  /// grows from [_expandFromHeight] to all the height its host allows.
  ///
  /// The wrappers stay in the tree either way: the composer holds overlay
  /// portals (tooltips), and moving it under a [LayoutBuilder] on toggle would
  /// re-attach them mid-layout, which the framework rejects.
  Widget _buildExpandingComposer(bool expandedLayout, Widget composer) {
    return LayoutBuilder(
      builder: (context, constraints) {
        assert(
          constraints.hasBoundedHeight,
          'ChatInputBar needs a host that bounds its height.',
        );
        return AnimatedBuilder(
          animation: _expandProgress,
          builder: (context, child) => SizedBox(
            height: expandedLayout
                ? ui.lerpDouble(
                    _expandFromHeight,
                    constraints.maxHeight,
                    _expandProgress.value,
                  )
                : null,
            child: child,
          ),
          child: RepaintBoundary(child: composer),
        );
      },
    );
  }
}

class _QueuedInputBanner extends StatelessWidget {
  const _QueuedInputBanner({
    required this.label,
    required this.cancelLabel,
    this.previewText,
    this.onCancel,
  });

  final String label;
  final String cancelLabel;
  final String? previewText;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final preview = previewText?.trim();
    final hasPreview = preview != null && preview.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.onSurface.withValues(alpha: 0.08)
            : theme.colorScheme.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.16),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.schedule_rounded,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                if (hasPreview) ...[
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.72,
                      ),
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IosCardPress(
            onTap: onCancel,
            borderRadius: BorderRadius.circular(10),
            baseColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              cancelLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: AppFontWeights.semibold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageModePill extends StatelessWidget {
  const _ImageModePill({
    required this.label,
    required this.closeTooltip,
    required this.onClose,
  });

  final String label;
  final String closeTooltip;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = scheme.surface.withValues(alpha: isDark ? 0.34 : 0.58);
    final border = isDark
        ? scheme.onSurface.withValues(alpha: 0.14)
        : scheme.primary.withValues(alpha: 0.36);
    final fg = isDark ? scheme.onSurface : scheme.primary;
    final iconColor = isDark ? scheme.primaryContainer : scheme.primary;
    final radius = BorderRadius.circular(999);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: Border.all(color: border),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 172),
              child: SizedBox(
                height: 24,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 9, end: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Brush, size: 14, color: iconColor),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: fg,
                            fontWeight: AppFontWeights.semibold,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: closeTooltip,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onClose,
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Icon(
                              Lucide.X,
                              size: 13,
                              color: (isDark ? scheme.onSurfaceVariant : fg)
                                  .withValues(
                                    alpha: onClose == null ? 0.38 : 0.78,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
