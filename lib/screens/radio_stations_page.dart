import 'package:flutter/material.dart';
import 'package:wiyamusic/constants/app_constants.dart';
import 'package:wiyamusic/database/radio_stations.db.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/main.dart';
import 'package:wiyamusic/services/common_services.dart';
import 'package:wiyamusic/utilities/flutter_toast.dart';
import 'package:wiyamusic/widgets/mini_player_bottom_space.dart';
import 'package:wiyamusic/widgets/radio_station_card.dart';

class RadioStationsPage extends StatelessWidget {
  const RadioStationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n!.radioStations)),
      body: ValueListenableBuilder(
        valueListenable: userLikedRadioStations,
        builder: (context, likedStations, _) {
          final stations = _sortWithLikedFirst(
            radioStationsDB,
            likedStations.toSet(),
          );

          if (stations.isEmpty) {
            return Center(child: Text(context.l10n!.noRadioStations));
          }

          return SingleChildScrollView(
            padding: commonSingleChildScrollViewPadding,
            child: Column(
              children: List.generate(stations.length, (index) {
                final station = stations[index];
                return Padding(
                  key: ValueKey(station.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RadioStationCard(
                    station: station,
                    onPressed: () async {
                      final success = await audioHandler.playRadioStream(
                        id: station.id,
                        name: station.name,
                        streamUrl: station.streamUrl,
                        image: station.image,
                        genre: station.genre,
                      );

                      if (!success && context.mounted) {
                        showToast(context, 'Failed to play radio station');
                      }
                    },
                  ),
                );
              }),
            ),
          );
        },
      ),
      bottomNavigationBar: const MiniPlayerBottomSpace(),
    );
  }
}

List<T> _sortWithLikedFirst<T>(List<T> stations, Set<String> likedIds) {
  final liked = <T>[];
  final rest = <T>[];

  for (final station in stations) {
    final id = (station as dynamic).id as String;
    if (likedIds.contains(id)) {
      liked.add(station);
    } else {
      rest.add(station);
    }
  }

  return [...liked, ...rest];
}
