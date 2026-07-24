/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     WiyaMusic is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     WiyaMusic is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about WiyaMusic, including how to contribute,
 *     please visit: https://github.com/Wiyam12/wiyamusic
 */

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
