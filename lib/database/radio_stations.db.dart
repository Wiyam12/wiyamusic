import 'package:wiyamusic/models/radio_model.dart';

List<RadioStation> radioStationsDB = [
  const RadioStation(
    id: 'r_cap_london',
    name: 'Capital London',
    image:
        'https://www.radio.net/300/capitalfmuk.png?version=5949ecef911a9e5232d0dba9643c8ba5b7da9363',
    streamUrl: 'https://media-ssl.musicradio.com/CapitalMP3',
    genre: 'Pop',
  ),
  const RadioStation(
    id: 'r_top_hits',
    name: 'Top Hits',
    image:
        'https://static2.mytuner.mobi/media/tvos_radios/407/hot106.c2263eb2.png',
    streamUrl: 'https://cdn.onlyhitsradio.net/tophits',
    genre: 'Pop',
  ),
  const RadioStation(
    id: 'r_bigfm',
    name: 'bigFM',
    image:
        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSrP01loD-Ip9YGCPJg11UekrqSwGIfOvIxBexLvKJ1BBQQcKe-HM3kNpep&s=10',
    streamUrl: 'https://stream.bigfm.de/deutschland/mp3-128/',
    genre: 'Pop',
  ),
  const RadioStation(
    id: 'r_kissfm',
    name: 'KissFM 104,5',
    image:
        'https://static2.mytuner.mobi/media/tvos_radios/192/kissfm-1045.9092a318.png',
    streamUrl: 'https://ice-11.spilarinn.is/kissfm',
    genre: 'Pop',
  ),
  const RadioStation(
    id: 'r_rockfm',
    name: 'RockFM',
    image:
        'https://static.wikia.nocookie.net/logopedia/images/3/31/Let%C3%B6lt%C3%A9s_%281%29.jpg/revision/latest',
    streamUrl: 'https://rockfm-cope-rrcast.flumotion.com/cope/rockfm-low.mp3',
    genre: 'Rock',
  ),
  const RadioStation(
    id: 'r_radio1rock',
    name: 'Radio 1 Rock',
    image:
        'https://store-images.s-microsoft.com/image/apps.12530.13510798887910876.18d0136c-d60d-4ba6-8188-4b6b2c74c26a.59760b1b-858a-4207-8103-f9a26b79ae8a',
    streamUrl: 'https://live.radio.si/Radio1Rock',
    genre: 'Rock',
  ),
  const RadioStation(
    id: 'r_global_rnb',
    name: 'Global RnB',
    image: 'https://cdn-profiles.tunein.com/s199317/images/logog.jpg?t=1',
    streamUrl: 'https://s5.radio.co/sf02cf450a/listen',
    genre: 'R&B',
  ),
  const RadioStation(
    id: 'r_love_music_radio',
    name: 'Love Music Radio',
    image: 'https://static2.mytuner.mobi/media/tvos_radios/f4tz8QjdyU.png',
    streamUrl: 'https://radio2.reans.net/radio/8050/radio.mp3',
    genre: 'R&B',
  ),
  const RadioStation(
    id: 'r_powerhitz_lit',
    name: 'Powerhitz - Lit Hip Hop',
    image: 'https://powerhitz.com/images/menu/Lithhlogo.png',
    streamUrl: 'https://live.powerhitz.com/lit',
    genre: 'Hip Hop',
  ),
];
