/// Bookshelf group entity corresponding to the `book_groups` table.
class BookGroup {
  final String id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BookGroup({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  BookGroup copyWith({
    String? id,
    String? name,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BookGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookGroup &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          sortOrder == other.sortOrder &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(id, name, sortOrder, createdAt, updatedAt);
}
