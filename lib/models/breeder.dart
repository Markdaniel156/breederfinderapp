import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'animal.dart';
import 'review.dart';

class Breeder {
  final String id;
  final String userId; 
  final String name;
  final String category;
  final String type; 
  final String role;
  final LatLng location;
  final String address;
  final String description;
  final String imageUrl;
  final String contactNumber;
  final String price;
  final String breed;
  final String gender;
  final String age;
  final String credentialsUrl;
  final List<String> credentialUrls;
  final List<Animal> animals;
  final List<Review> reviews;
  final String mapPrivacy;
  final DateTime? lastSeen;
  final DateTime? createdAt;

  Breeder({
    required this.id,
    this.userId = '',
    required this.name,
    required this.category,
    required this.type,
    this.role = '',
    required this.location,
    this.address = '',
    required this.description,
    required this.imageUrl,
    required this.contactNumber,
    this.price = '0',
    this.breed = '',
    this.gender = '',
    this.age = '',
    this.credentialsUrl = '',
    this.credentialUrls = const [],
    this.animals = const [],
    this.reviews = const [],
    this.mapPrivacy = 'Exact',
    this.lastSeen,
    this.createdAt,
  });

  double get averageRating {
    if (reviews.isEmpty) return 0.0;
    final total = reviews.fold(0.0, (sum, item) => sum + item.rating);
    return total / reviews.length;
  }

  Breeder copyWith({
    String? id,
    String? userId,
    String? name,
    String? category,
    String? type,
    String? role,
    LatLng? location,
    String? address,
    String? description,
    String? imageUrl,
    String? contactNumber,
    String? price,
    String? breed,
    String? gender,
    String? age,
    String? credentialsUrl,
    List<String>? credentialUrls,
    List<Animal>? animals,
    List<Review>? reviews,
    String? mapPrivacy,
    DateTime? lastSeen,
    DateTime? createdAt,
  }) {
    return Breeder(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      category: category ?? this.category,
      type: type ?? this.type,
      role: role ?? this.role,
      location: location ?? this.location,
      address: address ?? this.address,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      contactNumber: contactNumber ?? this.contactNumber,
      price: price ?? this.price,
      breed: breed ?? this.breed,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      credentialsUrl: credentialsUrl ?? this.credentialsUrl,
      credentialUrls: credentialUrls ?? this.credentialUrls,
      animals: animals ?? this.animals,
      reviews: reviews ?? this.reviews,
      mapPrivacy: mapPrivacy ?? this.mapPrivacy,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'category': category,
      'type': type,
      'role': role,
      'lat': location.latitude,
      'lng': location.longitude,
      'address': address,
      'description': description,
      'imageUrl': imageUrl,
      'contactNumber': contactNumber,
      'price': price,
      'breed': breed,
      'gender': gender,
      'age': age,
      'credentialsUrl': credentialsUrl,
      'credentialUrls': credentialUrls,
      'animals': animals.map((a) => a.toMap()).toList(),
      'reviews': reviews.map((r) => r.toMap()).toList(),
      'mapPrivacy': mapPrivacy,
      'lastSeen': lastSeen?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory Breeder.fromMap(Map<String, dynamic> map) {
    return Breeder(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      name: map['name'] ?? '',
      category: map['category'] ?? '',
      type: map['type'] ?? '',
      role: map['role'] ?? '',
      location: LatLng(
        (map['lat'] as num?)?.toDouble() ?? 0.0,
        (map['lng'] as num?)?.toDouble() ?? 0.0,
      ),
      address: map['address'] ?? '',
      description: map['description'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
      contactNumber: map['contactNumber'] ?? '',
      price: map['price']?.toString() ?? '0',
      breed: map['breed'] ?? '',
      gender: map['gender'] ?? '',
      age: map['age'] ?? '',
      credentialsUrl: map['credentialsUrl'] ?? '',
      credentialUrls: List<String>.from(map['credentialUrls'] ?? []),
      animals: (map['animals'] as List? ?? []).map((a) => Animal.fromMap(a)).toList(),
      reviews: (map['reviews'] as List? ?? []).map((r) => Review.fromMap(r)).toList(),
      mapPrivacy: map['mapPrivacy'] ?? 'Exact',
      lastSeen: map['lastSeen'] != null ? DateTime.tryParse(map['lastSeen']) : null,
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt']) : null,
    );
  }
}
