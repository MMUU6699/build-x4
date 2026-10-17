import 'package:flutter/foundation.dart';
import 'catalog_entry.dart';

class ModelCatalogService with ChangeNotifier {
  static final instance = ModelCatalogService();
  int get version => 0;
  CatalogMatch? match(String providerKey, String modelId) => null;
  CatalogMatch? lookup(dynamic provider, String model) => null;
}
