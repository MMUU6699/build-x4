import '../../models/model_spec.dart';

class CatalogReasoningOption {
  final String? id;
  final String? label;
  final String type;
  final List<String> values;
  final int? max;
  final int? min;

  const CatalogReasoningOption({
    this.id,
    this.label,
    this.type = '',
    this.values = const [],
    this.max,
    this.min,
  });
}

class CatalogModel {
  final String? id;
  final String? name;
  final String? description;
  final List<CatalogReasoningOption> reasoningOptions;
  final List<String> inputModalities;
  final List<String> outputModalities;
  final int? contextWindow;
  final int? maxTokens;

  const CatalogModel({
    this.id,
    this.name,
    this.description,
    this.reasoningOptions = const [],
    this.inputModalities = const [],
    this.outputModalities = const [],
    this.contextWindow,
    this.maxTokens,
  });

  int? get contextLimit => contextWindow;
  int? get outputLimit => maxTokens;
  bool? get toolCall => null;
  bool? get reasoning => null;
  bool? get structuredOutput => null;
  String? get interleavedField => null;
  double? get temperature => null;
  double? get costInput => null;
  double? get costOutput => null;
  double? get costCacheRead => null;
  double? get costCacheWrite => null;
}

class CatalogMatch {
  final ModelSpec? spec;
  final CatalogModel model;

  const CatalogMatch({this.spec, this.model = const CatalogModel()});
}
