class Animal {
  final String id;
  final String name;
  final String breed;
  final double price;
  final String imageUrl;
  final String description;

  Animal({
    required this.id,
    required this.name,
    required this.breed,
    required this.price,
    required this.imageUrl,
    required this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'breed': breed,
      'price': price,
      'imageUrl': imageUrl,
      'description': description,
    };
  }

  factory Animal.fromMap(Map<String, dynamic> map) {
    return Animal(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      breed: map['breed'] ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: map['imageUrl'] ?? '',
      description: map['description'] ?? '',
    );
  }
}
