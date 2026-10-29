import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/breeder.dart';
import '../models/animal.dart';
import '../models/review.dart';
import '../utils/location_utils.dart';

class BreederProvider with ChangeNotifier {
  final List<Breeder> _breeders = [];
  final List<String> _favoriteIds = [];
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;

  StreamSubscription? _breederStream;
  StreamSubscription? _traderStream;

  List<Breeder> get breeders => [..._breeders];
  List<String> get favoriteIds => [..._favoriteIds];
  bool get isLoading => _isLoading;

  BreederProvider() {
    _loadFromCache();
    _initAuthListener();
    _initRealtimeListeners();
    fetchBreeders();
  }

  Future<Map<String, dynamic>?> getSubscriptionDetails(String userId) async {
    try {
      final now = DateTime.now().toIso8601String();
      final response = await _supabase
          .from('subscriptions')
          .select('plan_name, created_at, expires_at')
          .eq('user_id', userId)
          .gt('expires_at', now)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error checking subscription details: $e');
      return null;
    }
  }

  Future<String?> getUserPlan(String userId) async {
    final sub = await getSubscriptionDetails(userId);
    return sub?['plan_name'] as String?;
  }

  Future<int> getSoloPlanPostCount(String userId) async {
    final sub = await getSubscriptionDetails(userId);
    if (sub == null || sub['plan_name'] != 'Solo Plan') return 0;
    
    final subCreatedAt = DateTime.tryParse(sub['created_at']?.toString() ?? '');
    if (subCreatedAt == null) return _breeders.where((b) => b.userId == userId).length;

    final effectiveStart = subCreatedAt.subtract(const Duration(seconds: 5));

    return _breeders.where((b) {
      if (b.userId != userId) return false;
      if (b.createdAt == null) return false;
      return b.createdAt!.isAfter(effectiveStart);
    }).length;
  }

  Future<bool> hasReachedListingLimit(String userId) async {
    final sub = await getSubscriptionDetails(userId);
    final plan = sub?['plan_name'] as String?;
    
    // Free tier: 3 posts
    if (plan == null) {
      final postCount = _breeders.where((b) => b.userId == userId).length;
      return postCount >= 3;
    }
    
    // Solo Plan: 10 posts created under active Solo Plan
    if (plan == 'Solo Plan') {
      final postCount = await getSoloPlanPostCount(userId);
      return postCount >= 10;
    }
    
    // Organization Plan: Unlimited
    if (plan == 'Organization Plan') return false;
    
    // Default: No limit for unknown plans
    return false;
  }

  List<Breeder> getBreedersByType(String type) {
    return _breeders.where((b) => b.type == type).toList();
  }

  List<Breeder> getBreedersByCategory(String category) {
    if (category == 'All') return breeders;
    return _breeders.where((b) => b.category == category).toList();
  }

  void _initRealtimeListeners() {
    _breederStream?.cancel();
    _traderStream?.cancel();
    _breederStream = _supabase.from('breeder_postings').stream(primaryKey: ['id']).listen((data) => _updateRealtimeLocations(data));
    _traderStream = _supabase.from('trader_postings').stream(primaryKey: ['id']).listen((data) => _updateRealtimeLocations(data));
  }

  void _updateRealtimeLocations(List<Map<String, dynamic>> data) {
    bool changed = false;
    for (var item in data) {
      final String id = item['id'].toString();
      final double lat = (item['latitude'] as num?)?.toDouble() ?? 0.0;
      final double lng = (item['longitude'] as num?)?.toDouble() ?? 0.0;
      final index = _breeders.indexWhere((b) => b.id == id);
      if (index != -1 && (_breeders[index].location.latitude != lat || _breeders[index].location.longitude != lng)) {
        _breeders[index] = _breeders[index].copyWith(location: LatLng(lat, lng));
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> updateUserLocation({required String userId, required LatLng location, required String role}) async {
    try {
      await Future.wait([
        _supabase.from('breeder_postings').update({'latitude': location.latitude, 'longitude': location.longitude}).eq('user_id', userId),
        _supabase.from('trader_postings').update({'latitude': location.latitude, 'longitude': location.longitude}).eq('user_id', userId),
      ]);
    } catch (e) {
      debugPrint('Sync Error: $e');
    }
  }

  @override
  void dispose() {
    _breederStream?.cancel();
    _traderStream?.cancel();
    super.dispose();
  }

  void _initAuthListener() {
    _supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.initialSession) {
        _loadFavorites();
      } else if (data.event == AuthChangeEvent.signedOut) {
        _favoriteIds.clear();
        notifyListeners();
      }
    });
  }

  Future<void> _loadFavorites() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final response = await _supabase.from('favorites').select('listing_id').eq('user_id', user.id);
      final List<String> remoteIds = (response as List).map((item) => item['listing_id'].toString()).toList();
      _favoriteIds.clear();
      _favoriteIds.addAll(remoteIds);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favs_${user.id}', _favoriteIds);
      notifyListeners();
    } catch (e) {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        final List<String>? cached = prefs.getStringList('favs_${user.id}');
        if (cached != null) {
          _favoriteIds.clear();
          _favoriteIds.addAll(cached);
          notifyListeners();
        }
      }
    }
  }

  Future<void> toggleFavorite(String id) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    bool isAdding = !_favoriteIds.contains(id);
    if (isAdding) {
      _favoriteIds.add(id);
    } else {
      _favoriteIds.remove(id);
    }
    notifyListeners();
    try {
      if (isAdding) {
        await _supabase.from('favorites').insert({'user_id': user.id, 'listing_id': id});
      } else {
        await _supabase.from('favorites').delete().eq('user_id', user.id).eq('listing_id', id);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favs_${user.id}', _favoriteIds);
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
    }
  }

  bool isFavorite(String id) => _favoriteIds.contains(id);
  List<Breeder> get favoriteBreeders => _breeders.where((b) => _favoriteIds.contains(b.id)).toList();

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedData = prefs.getString('cached_breeders');
      if (cachedData != null) {
        final List<dynamic> decoded = jsonDecode(cachedData);
        _breeders.clear();
        _breeders.addAll(decoded.map((m) => Breeder.fromMap(m)).toList());
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Cache error: $e');
    }
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_breeders', jsonEncode(_breeders.map((b) => b.toMap()).toList()));
    } catch (e) {
      debugPrint('Cache save error: $e');
    }
  }

  Future<void> fetchBreeders({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final breederResponse = await _supabase.from('breeder_postings').select('*').eq('is_registered', true);
      final traderResponse = await _supabase.from('trader_postings').select('*').eq('is_registered', true);
      List<dynamic> accountResponse = [];
      try {
        accountResponse = await _supabase.from('create_account').select('id, full_name, avatar_url, role, last_seen, address, city_municipality, barangay, privacy_mode');
      } catch (e) {
        accountResponse = await _supabase.from('create_account').select('id, full_name, avatar_url, role, city_municipality, barangay, privacy_mode');
      }
      final reviewResponse = await _supabase.from('reviews').select('*').order('created_at', ascending: false);

      final Map<String, String> nameMap = {};
      final Map<String, String> avatarMap = {};
      final Map<String, String> roleMap = {};
      final Map<String, String> addressMap = {};
      final Map<String, DateTime?> lastSeenMap = {};
      final Map<String, String> privacyMap = {};

      for (var acc in accountResponse) {
        if (acc['id'] != null) {
          final String idStr = acc['id'].toString();
          final name = acc['full_name'] ?? acc['fullname'] ?? acc['name'] ?? acc['display_name'];
          if (name != null && name.toString().trim().isNotEmpty) {
            nameMap[idStr] = name.toString();
          }
          if (acc['avatar_url'] != null) avatarMap[idStr] = acc['avatar_url'].toString();
          if (acc['role'] != null) roleMap[idStr] = acc['role'].toString();
          if (acc['address'] != null) {
            addressMap[idStr] = LocationUtils.sanitizeAddress(acc['address'].toString());
          } else if (acc['barangay'] != null && acc['city_municipality'] != null) {
            addressMap[idStr] = LocationUtils.sanitizeAddress('${acc['barangay']}, ${acc['city_municipality']}');
          }
          if (acc['last_seen'] != null) lastSeenMap[idStr] = DateTime.tryParse(acc['last_seen'].toString());
          privacyMap[idStr] = acc['privacy_mode'] ?? 'Exact';
        }
      }

      final Map<String, List<Review>> reviewMapByListing = {};
      for (var rev in reviewResponse) {
        final String listingId = rev['listing_id']?.toString() ?? '';
        if (listingId.isNotEmpty) {
          if (!reviewMapByListing.containsKey(listingId)) reviewMapByListing[listingId] = [];
          reviewMapByListing[listingId]!.add(Review.fromMap(rev));
        }
      }

      final allData = [...breederResponse, ...traderResponse];
      allData.sort((a, b) => (DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(2000)).compareTo(DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(2000)));

      final newBreeders = allData.map((data) {
        List<String> parseArray(dynamic value) {
          if (value == null) return [];
          List<dynamic> list = [];
          if (value is List) {
            list = value;
          } else if (value is String) {
            try { list = jsonDecode(value); } catch (e) { list = value.split(','); }
          }
          return list.map((e) => e.toString().trim().replaceAll('"', '').replaceAll("'", '')).where((s) => s.startsWith('http')).toList();
        }

        final List<String> additionalImages = parseArray(data['additional_images']);
        final List<String> credentialUrls = parseArray(data['credential_urls']);
        final String entryId = data['id']?.toString() ?? '';
        final String userId = data['user_id']?.toString() ?? '';
        String userProfileUrl = data['avatar_url']?.toString() ?? avatarMap[userId] ?? '';
        if (userProfileUrl.isNotEmpty && !userProfileUrl.startsWith('http')) userProfileUrl = _supabase.storage.from('avatars').getPublicUrl(userProfileUrl);

        String userRole = roleMap[userId] ?? 'Member';
        if (userRole.toLowerCase().contains('breeder')) {
          userRole = 'Breeder';
        } else if (userRole.toLowerCase().contains('trader')) {
          userRole = 'Trader';
        }

        final List<Animal> animals = additionalImages.asMap().entries.map((entry) {
          String url = entry.value;
          String breed = data['breed'] ?? '';
          double price = double.tryParse(data['price']?.toString() ?? '0') ?? 0.0;
          if (url.contains('|')) {
            final parts = url.split('|');
            url = parts[0];
            if (parts.length > 1) breed = parts[1];
            if (parts.length > 2) price = double.tryParse(parts[2]) ?? price;
          }
          return Animal(id: '${data['id']}_animal_${entry.key}', name: '${data['category'] ?? 'Animal'}', breed: breed, price: price, imageUrl: url, description: data['description'] ?? '');
        }).toList();

        return Breeder(
          id: entryId, userId: userId.isNotEmpty ? userId : '', name: data['full_name'] ?? nameMap[userId] ?? 'User', category: data['category'] ?? '', breed: data['breed'] ?? '', gender: data['gender'] ?? '', age: data['age'] ?? '',
          type: data['type'] ?? (breederResponse.any((b) => b['id'] == data['id']) ? 'Breeder' : 'Trader'), role: userRole,
          location: LatLng(double.tryParse(data['latitude']?.toString() ?? '0') ?? 0.0, double.tryParse(data['longitude']?.toString() ?? '0') ?? 0.0),
          address: LocationUtils.sanitizeAddress(data['address'] ?? addressMap[userId] ?? ''), description: data['description'] ?? '', imageUrl: userProfileUrl, contactNumber: data['phone_number'] ?? '',
          price: data['price']?.toString() ?? '0', credentialsUrl: data['credentials_url'] ?? '', credentialUrls: credentialUrls, animals: animals, reviews: reviewMapByListing[entryId] ?? [],
          mapPrivacy: data['privacy_mode'] ?? privacyMap[userId] ?? 'Exact',
          lastSeen: lastSeenMap[userId], createdAt: DateTime.tryParse(data['created_at']?.toString() ?? ''),
        );
      }).toList();

      _breeders.clear();
      _breeders.addAll({for (var b in newBreeders) b.id: b}.values);
      _saveToCache();
    } catch (e) {
      debugPrint('Fetch Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addBreeder(Breeder breeder, List<String> animalImagePaths, {List<String>? credentialImagePaths, List<String>? existingAnimalUrls, List<Map<String, String>>? animalMetadata}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');
      if (breeder.id.isEmpty) {
        final hasReachedLimit = await hasReachedListingLimit(userId);
        if (hasReachedLimit) {
          throw Exception('LIMIT_REACHED');
        }
      }

      String finalAvatarUrl = breeder.imageUrl;
      if (finalAvatarUrl.isEmpty) {
        final profile = await _supabase.from('create_account').select('avatar_url').eq('id', userId).maybeSingle();
        if (profile != null) finalAvatarUrl = profile['avatar_url']?.toString() ?? '';
      }

      final isTrader = breeder.type == 'Trader';
      final bucketName = isTrader ? 'trader-images' : 'breeder-images';
      final tableName = isTrader ? 'trader_postings' : 'breeder_postings';

      final List<String> newAnimalUrls = await Future.wait(animalImagePaths.asMap().entries.map((entry) async {
        final path = entry.value;
        final fileName = 'animal_${userId}_${DateTime.now().millisecondsSinceEpoch}_${path.split('/').last}';
        await _supabase.storage.from(bucketName).upload(fileName, File(path));
        String publicUrl = _supabase.storage.from(bucketName).getPublicUrl(fileName);
        if (animalMetadata != null && entry.key < animalMetadata.length) {
          final meta = animalMetadata[entry.key];
          if (meta['breed'] != null || meta['price'] != null) publicUrl = '$publicUrl|${meta['breed'] ?? ''}|${meta['price'] ?? ''}';
        }
        return publicUrl;
      }));

      final List<String> finalAnimalUrls = [...(existingAnimalUrls ?? []), ...newAnimalUrls];
      List<String> credentialUrls = [];
      if (credentialImagePaths != null) {
        credentialUrls = await Future.wait(credentialImagePaths.map((path) async {
          final fileName = 'credential_${userId}_${DateTime.now().millisecondsSinceEpoch}_${path.split('/').last}';
          await _supabase.storage.from(bucketName).upload(fileName, File(path));
          return _supabase.storage.from(bucketName).getPublicUrl(fileName);
        }));
      }

      final Map<String, dynamic> dataMap = {
        'user_id': userId, 'full_name': breeder.name, 'category': breeder.category, 'breed': breeder.breed, 'price': double.tryParse(breeder.price) ?? 0,
        'phone_number': breeder.contactNumber, 'type': breeder.type, 'additional_images': finalAnimalUrls, 'is_registered': true, 'avatar_url': finalAvatarUrl,
        'age': breeder.age,
        'gender': breeder.gender,
      };
      if (breeder.id.isNotEmpty) dataMap['id'] = breeder.id;
      if (breeder.location.latitude != 0) { dataMap['latitude'] = breeder.location.latitude; dataMap['longitude'] = breeder.location.longitude; }
      if (!isTrader) dataMap['description'] = breeder.description;
      if (isTrader) { dataMap['address'] = breeder.address; dataMap['credentials_url'] = credentialUrls.isNotEmpty ? credentialUrls.first : ''; dataMap['credential_urls'] = credentialUrls; }

      await _supabase.from(tableName).upsert(dataMap);
      await fetchBreeders(silent: true);
    } catch (e) {
      debugPrint('Add Error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteListing(String breederId, String type) async {
    _isLoading = true;
    notifyListeners();
    try {
      final tableName = type == 'Breeder' ? 'breeder_postings' : 'trader_postings';
      await _supabase.from(tableName).delete().eq('id', breederId);
      _breeders.removeWhere((b) => b.id == breederId);
      await _saveToCache();
      await fetchBreeders(silent: true);
    } catch (e) {
      debugPrint('Delete Error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateBusinessLocation(LatLng location) async {
    _isLoading = true;
    notifyListeners();
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await Future.wait([
        _supabase.from('breeder_postings').update({'latitude': location.latitude, 'longitude': location.longitude}).eq('user_id', userId),
        _supabase.from('trader_postings').update({'latitude': location.latitude, 'longitude': location.longitude}).eq('user_id', userId),
      ]);
      await fetchBreeders(silent: true);
    } catch (e) {
      debugPrint('Location Update Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addReview({required String listingId, required double rating, required String comment, List<String>? photoPaths}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Must be logged in');
      final profile = await _supabase.from('create_account').select('full_name, avatar_url').eq('id', user.id).single();
      List<String> photoUrls = [];
      if (photoPaths != null) {
        photoUrls = await Future.wait(photoPaths.map((path) async {
          final fileName = 'review_${user.id}_${DateTime.now().millisecondsSinceEpoch}_${path.split('/').last}';
          await _supabase.storage.from('review-photos').upload(fileName, File(path));
          return _supabase.storage.from('review-photos').getPublicUrl(fileName);
        }));
      }
      await _supabase.from('reviews').insert({'listing_id': listingId, 'user_id': user.id, 'user_name': profile['full_name'] ?? 'User', 'user_avatar_url': profile['avatar_url'] ?? '', 'rating': rating, 'comment': comment, 'review_photos': photoUrls, 'created_at': DateTime.now().toIso8601String()});
      await fetchBreeders(silent: true);
    } catch (e) {
      debugPrint('Review Error: $e');
      rethrow;
    }
  }

  Future<void> replyToReview({required String reviewId, required String replyComment}) async {
    try {
      await _supabase.from('reviews').update({'reply_comment': replyComment, 'reply_created_at': DateTime.now().toIso8601String()}).eq('id', reviewId);
      await fetchBreeders(silent: true);
    } catch (e) {
      debugPrint('Reply Error: $e');
      rethrow;
    }
  }

  Future<void> deleteReview({required String reviewId}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Must be logged in');
      await _supabase.from('reviews').delete().eq('id', reviewId).eq('user_id', user.id);
      await fetchBreeders(silent: true);
    } catch (e) {
      debugPrint('Delete Review Error: $e');
      rethrow;
    }
  }

  Future<bool> isUserSubscribed(String userId) async {
    final plan = await getUserPlan(userId);
    return plan != null;
  }
}
