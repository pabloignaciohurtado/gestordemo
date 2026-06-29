import 'models.dart';

/// Criterios de filtrado combinables. Conjuntos vacíos = "sin filtro" en esa
/// dimensión. Se traduce a una cláusula WHERE dinámica en DatabaseHelper.
class DocumentFilter {
  final Set<String> types; // 'pdf','image','text','csv' (prefijo/categoría lógica)
  final Set<int> categoryIds;
  final Set<int> tagIds;
  final Set<String> sources; // 'Descargas','WhatsApp','Manual', etc.
  final Set<OcrStatus> ocrStatuses;
  final DateRange? dateRange;
  final bool favoritesOnly;

  const DocumentFilter({
    this.types = const {},
    this.categoryIds = const {},
    this.tagIds = const {},
    this.sources = const {},
    this.ocrStatuses = const {},
    this.dateRange,
    this.favoritesOnly = false,
  });

  bool get isEmpty =>
      types.isEmpty &&
      categoryIds.isEmpty &&
      tagIds.isEmpty &&
      sources.isEmpty &&
      ocrStatuses.isEmpty &&
      dateRange == null &&
      !favoritesOnly;

  DocumentFilter copyWith({
    Set<String>? types,
    Set<int>? categoryIds,
    Set<int>? tagIds,
    Set<String>? sources,
    Set<OcrStatus>? ocrStatuses,
    DateRange? dateRange,
    bool clearDate = false,
    bool? favoritesOnly,
  }) =>
      DocumentFilter(
        types: types ?? this.types,
        categoryIds: categoryIds ?? this.categoryIds,
        tagIds: tagIds ?? this.tagIds,
        sources: sources ?? this.sources,
        ocrStatuses: ocrStatuses ?? this.ocrStatuses,
        dateRange: clearDate ? null : (dateRange ?? this.dateRange),
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      );
}

class DateRange {
  final int fromMillis;
  final int toMillis;
  const DateRange(this.fromMillis, this.toMillis);

  /// Atajos relativos a "ahora".
  factory DateRange.lastDays(int days) {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days));
    return DateRange(from.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
  }
}

enum DocSort {
  recent('modified_at DESC'),
  oldest('modified_at ASC'),
  nameAsc('display_name COLLATE NOCASE ASC'),
  nameDesc('display_name COLLATE NOCASE DESC'),
  sizeBig('size_bytes DESC'),
  sizeSmall('size_bytes ASC');

  final String orderBy;
  const DocSort(this.orderBy);
}
