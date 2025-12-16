import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product_model.dart';
import '../models/reward_request_model.dart';
import '../services/rewards_repository.dart';

final rewardsRepositoryProvider = Provider<RewardsRepository>((ref) {
  return RewardsRepository();
});

/// Provides the complete rewards catalog with all products
final rewardsCatalogProvider = FutureProvider<List<ProductModel>>((ref) async {
  print('🎁 rewardsCatalogProvider: Starting catalog fetch...');
  try {
    final repository = ref.watch(rewardsRepositoryProvider);
    final catalog = await repository.getCatalog();
    print('✅ rewardsCatalogProvider: Successfully loaded ${catalog.length} products');
    return catalog;
  } catch (e) {
    print('❌ rewardsCatalogProvider: Error loading catalog: $e');
    rethrow;
  }
});

/// Provides search results for products by query string
final productsSearchProvider =
    FutureProvider.family<List<ProductModel>, String>((ref, query) async {
      print('🔍 productsSearchProvider: Searching for "$query"...');
      try {
        final repository = ref.watch(rewardsRepositoryProvider);
        final results = await repository.searchProducts(query);
        print('✅ productsSearchProvider: Found ${results.length} results for "$query"');
        return results;
      } catch (e) {
        print('❌ productsSearchProvider: Error searching products: $e');
        rethrow;
      }
    });

/// Provides current user's available points (real-time)
final studentPointsProvider = StreamProvider.family<double, String>((
  ref,
  studentId,
) {
  print('💰 studentPointsProvider: Starting stream for student: $studentId');
  try {
    final repository = ref.watch(rewardsRepositoryProvider);
    final pointsStream = repository.streamStudentPoints(studentId);
    
    return pointsStream.map((points) {
      print('💰 studentPointsProvider: Updated points for $studentId: $points');
      return points;
    });
  } catch (e) {
    print('❌ studentPointsProvider: Error creating stream: $e');
    rethrow;
  }
});

/// Provides list of reward requests for a student (real-time)
final studentRequestsProvider =
    StreamProvider.family<List<RewardRequestModel>, String>((ref, studentId) {
      print('📋 studentRequestsProvider: Starting stream for student: $studentId');
      try {
        final repository = ref.watch(rewardsRepositoryProvider);
        final requestsStream = repository.streamStudentRequests(studentId);
        
        return requestsStream.map((requests) {
          print('📋 studentRequestsProvider: Updated requests for $studentId: ${requests.length} items');
          return requests;
        });
      } catch (e) {
        print('❌ studentRequestsProvider: Error creating stream: $e');
        rethrow;
      }
    });

/// Provides list of reward requests for a parent to review (real-time)
final parentRequestsProvider =
    StreamProvider.family<List<RewardRequestModel>, String>((ref, parentId) {
      print('👨‍👩‍👧 parentRequestsProvider: Starting stream for parent: $parentId');
      try {
        final repository = ref.watch(rewardsRepositoryProvider);
        final requestsStream = repository.streamParentRequests(parentId);
        
        return requestsStream.map((requests) {
          print('👨‍👩‍👧 parentRequestsProvider: Updated requests for $parentId: ${requests.length} items');
          return requests;
        });
      } catch (e) {
        print('❌ parentRequestsProvider: Error creating stream: $e');
        rethrow;
      }
    });

/// Provides a single reward request by ID
final currentRequestProvider =
    FutureProvider.family<RewardRequestModel?, String>((ref, requestId) async {
      final repository = ref.watch(rewardsRepositoryProvider);
      return repository.getRequest(requestId);
    });

/// Provides a single product by ID
final productDetailProvider = FutureProvider.family<ProductModel?, String>((
  ref,
  productId,
) async {
  final repository = ref.watch(rewardsRepositoryProvider);
  return repository.getProductById(productId);
});

/// State notifier for managing UI state during request creation
class CreateRequestNotifier extends StateNotifier<AsyncValue<String>> {
  final RewardsRepository _repository;

  CreateRequestNotifier(this._repository) : super(const AsyncValue.data(''));

  Future<void> createRequest({
    required ProductModel product,
    required String studentId,
    required String parentId,
  }) async {
    state = const AsyncValue.loading();
    try {
      final pointsRequired = product.pointsRule
          .calculatePoints(product.price.estimatedPrice)
          .toInt();
      final lockExpiresAt = DateTime.now().add(const Duration(days: 21));

      final request = await _repository.createRequest(
        studentId: studentId,
        parentId: parentId,
        product: product,
        pointsRequired: pointsRequired,
        lockExpiresAt: lockExpiresAt,
      );
      state = AsyncValue.data(request.requestId);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final createRequestProvider =
    StateNotifierProvider<CreateRequestNotifier, AsyncValue<String>>((ref) {
      final repository = ref.watch(rewardsRepositoryProvider);
      return CreateRequestNotifier(repository);
    });

/// State notifier for managing UI state during status updates
class UpdateRequestStatusNotifier extends StateNotifier<AsyncValue<void>> {
  final RewardsRepository _repository;

  UpdateRequestStatusNotifier(this._repository)
    : super(const AsyncValue.data(null));

  Future<void> updateStatus({
    required String requestId,
    required RewardRequestStatus newStatus,
    required String userId,
    Map<String, dynamic>? metadata,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _repository.updateRequestStatus(
        requestId: requestId,
        newStatus: newStatus,
        userId: userId,
        metadata: metadata,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final updateRequestStatusProvider =
    StateNotifierProvider<UpdateRequestStatusNotifier, AsyncValue<void>>((ref) {
      final repository = ref.watch(rewardsRepositoryProvider);
      return UpdateRequestStatusNotifier(repository);
    });

/// Provides filter/sorting options for the catalog view
class FilterNotifier
    extends StateNotifier<({String? category, String? sortBy})> {
  FilterNotifier() : super((category: null, sortBy: null));

  void setCategory(String? category) {
    state = (category: category, sortBy: state.sortBy);
  }

  void setSortBy(String? sortBy) {
    state = (category: state.category, sortBy: sortBy);
  }

  void reset() {
    state = (category: null, sortBy: null);
  }
}

final filterProvider =
    StateNotifierProvider<FilterNotifier, ({String? category, String? sortBy})>(
      (ref) => FilterNotifier(),
    );

/// Provides filtered catalog based on current filter settings
final filteredCatalogProvider = FutureProvider<List<ProductModel>>((ref) async {
  final catalog = await ref.watch(rewardsCatalogProvider.future);
  final filter = ref.watch(filterProvider);

  var filtered = List<ProductModel>.from(catalog);

  if (filter.sortBy != null) {
    switch (filter.sortBy) {
      case 'price_asc':
        filtered.sort(
          (a, b) => a.price.estimatedPrice.compareTo(b.price.estimatedPrice),
        );
      case 'price_desc':
        filtered.sort(
          (a, b) => b.price.estimatedPrice.compareTo(a.price.estimatedPrice),
        );
      case 'rating':
        filtered.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      case 'points':
        filtered.sort(
          (a, b) => a.pointsRule.maxPoints.compareTo(b.pointsRule.maxPoints),
        );
    }
  }

  return filtered;
});
