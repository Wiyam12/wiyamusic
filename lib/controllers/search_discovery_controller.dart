import 'package:flutter/foundation.dart';
import 'package:wiyamusic/models/search_discovery_models.dart';
import 'package:wiyamusic/services/search_discovery/search_discovery_repository.dart';

/// ViewModel / controller for Search discovery sections.
class SearchDiscoveryController extends ChangeNotifier {
  SearchDiscoveryController({SearchDiscoveryRepository? repository})
    : _repository = repository ?? SearchDiscoveryRepository();

  final SearchDiscoveryRepository _repository;

  SearchDiscoveryState _state = const SearchDiscoveryState();
  SearchDiscoveryState get state => _state;

  bool _disposed = false;

  Future<void> load({bool forceRefresh = false}) async {
    final cached = await _repository.getCached();
    final cacheFresh = await _repository.isCacheFresh();

    if (cached != null && !cached.isEmpty) {
      _setState(
        _state.copyWith(
          status: SearchDiscoveryStatus.success,
          snapshot: cached,
          clearError: true,
        ),
      );
      if (!forceRefresh && cacheFresh) return;
    } else {
      _setState(
        _state.copyWith(
          status: SearchDiscoveryStatus.loading,
          clearError: true,
        ),
      );
    }

    try {
      final remote = await _repository.refreshFromApi();
      if (remote.isEmpty) {
        if (cached != null && !cached.isEmpty) {
          _setState(
            _state.copyWith(
              status: SearchDiscoveryStatus.success,
              snapshot: cached,
              clearError: true,
            ),
          );
        } else {
          _setState(
            _state.copyWith(
              status: SearchDiscoveryStatus.empty,
              snapshot: remote,
              errorMessage: 'No discovery data available',
            ),
          );
        }
        return;
      }

      _setState(
        _state.copyWith(
          status: SearchDiscoveryStatus.success,
          snapshot: remote,
          clearError: true,
        ),
      );
    } catch (e) {
      if (cached != null && !cached.isEmpty) {
        _setState(
          _state.copyWith(
            status: SearchDiscoveryStatus.success,
            snapshot: cached,
            errorMessage: e.toString(),
          ),
        );
      } else {
        _setState(
          _state.copyWith(
            status: SearchDiscoveryStatus.error,
            errorMessage: e.toString(),
          ),
        );
      }
    }
  }

  Future<void> retry() => load(forceRefresh: true);

  void _setState(SearchDiscoveryState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
