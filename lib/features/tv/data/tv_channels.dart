// lib/features/tv/data/tv_channels.dart
// XameTV — Curated free-to-air HLS channel catalogue

import 'package:flutter/material.dart';

class TvChannel {
  final String id, name, category, streamUrl, logo, description, country, language;
  final bool isHD;
  const TvChannel({
    required this.id, required this.name, required this.category,
    required this.streamUrl, required this.logo, required this.description,
    required this.country, required this.language, this.isHD = false,
  });
}

const kTvCategories = ['News', 'Sports', 'Entertainment', 'Music', 'Science', 'Kids'];

const kTvChannels = <TvChannel>[
  // NEWS
  TvChannel(id:'aljazeera',name:'Al Jazeera English',category:'News',
    streamUrl:'https://live-hls-web-aje.getaj.net/AJE/index.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/en/thumb/f/f2/Al_Jazeera_English_Logo.svg/250px-Al_Jazeera_English_Logo.svg.png',
    description:'Breaking news and world affairs',country:'Qatar',language:'English',isHD:true),
  TvChannel(id:'dw',name:'DW News',category:'News',
    streamUrl:'https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/index.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/7/75/Deutsche_Welle_symbol_2012.svg/250px-Deutsche_Welle_symbol_2012.svg.png',
    description:'International German broadcaster',country:'Germany',language:'English',isHD:true),
  TvChannel(id:'france24',name:'France 24',category:'News',
    streamUrl:'https://stream.france24.com/hls/live/2037163/F24_EN_LO_HLS/master.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b8/France_24_logo.svg/250px-France_24_logo.svg.png',
    description:'International French news channel',country:'France',language:'English',isHD:true),
  TvChannel(id:'trt-world',name:'TRT World',category:'News',
    streamUrl:'https://tv-trtworld.medya.trt.com.tr/master.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/2/28/TRT_World_logo.svg/250px-TRT_World_logo.svg.png',
    description:'Turkish international broadcaster',country:'Turkey',language:'English',isHD:true),
  TvChannel(id:'cgtn',name:'CGTN',category:'News',
    streamUrl:'https://news.cgtn.com/resource/live/english/cgtn-news.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b3/CGTN_logo.svg/250px-CGTN_logo.svg.png',
    description:'China Global Television Network',country:'China',language:'English',isHD:true),
  TvChannel(id:'euronews',name:'Euronews',category:'News',
    streamUrl:'https://euronews-euronews-english-1-eu.rakuten.wurl.tv/playlist.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/3/30/Euronews_logo.svg/250px-Euronews_logo.svg.png',
    description:'Pan-European news network',country:'Europe',language:'English',isHD:true),
  // SPORTS
  TvChannel(id:'nasa-tv',name:'NASA TV',category:'Sports',
    streamUrl:'https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e5/NASA_logo.svg/200px-NASA_logo.svg.png',
    description:'Live space missions',country:'USA',language:'English',isHD:true),
  TvChannel(id:'sports247',name:'Sports 24/7',category:'Sports',
    streamUrl:'https://cbsn-us.cbsnews.com/ar/master.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/Soccerball.svg/200px-Soccerball.svg.png',
    description:'Live sports coverage',country:'International',language:'English',isHD:true),
  TvChannel(id:'fight-sports',name:'Fight Sports',category:'Sports',
    streamUrl:'https://dai.google.com/linear/hls/event/cV9T26SMQ5KMvHsLfFh4AQ/master.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/7/71/MMA_UFC_Fight_Night_logo.svg/200px-MMA_UFC_Fight_Night_logo.svg.png',
    description:'Boxing, MMA and combat sports',country:'International',language:'English',isHD:false),
  // ENTERTAINMENT
  TvChannel(id:'tv5monde',name:'TV5Monde',category:'Entertainment',
    streamUrl:'https://redbee.live.tv5monde.com/hls/tv5monde/index.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f9/TV5Monde_logo_2020.svg/200px-TV5Monde_logo_2020.svg.png',
    description:'French-language entertainment',country:'France',language:'French',isHD:true),
  TvChannel(id:'pluto-movies',name:'Pluto Movies',category:'Entertainment',
    streamUrl:'https://samsunguk.samsung.wurl.com/manifest/playlist.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/3/30/Pluto_TV_logo.svg/200px-Pluto_TV_logo.svg.png',
    description:'Free movies on demand',country:'International',language:'English',isHD:true),
  TvChannel(id:'zee-bollywood',name:'Zee Bollywood',category:'Entertainment',
    streamUrl:'https://z5hls.akamaized.net/hls/live/2017016/ZB-Intl/master.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/0/00/Zee_Bollywood.jpg/200px-Zee_Bollywood.jpg',
    description:'Bollywood movies and shows',country:'India',language:'Hindi',isHD:true),
  // MUSIC
  TvChannel(id:'trace-africa',name:'Trace Africa',category:'Music',
    streamUrl:'https://traceafrica.akamaized.net/hls/live/traceafrica/stream.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/6/6d/Trace_TV_logo.svg/200px-Trace_TV_logo.svg.png',
    description:'African music videos',country:'Africa',language:'Multiple',isHD:true),
  TvChannel(id:'clubbing-tv',name:'Clubbing TV',category:'Music',
    streamUrl:'https://clubbingtv.akamaized.net/hls/live/clubbingtv/stream.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/8/80/Cartoon_Network_2010_logo.svg/200px-Cartoon_Network_2010_logo.svg.png',
    description:'Electronic music and DJ sets',country:'International',language:'Instrumental',isHD:true),
  TvChannel(id:'mezzo',name:'Mezzo Live',category:'Music',
    streamUrl:'https://mezzo.akamaized.net/hls/live/mezzo/stream.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/6/6d/Trace_TV_logo.svg/200px-Trace_TV_logo.svg.png',
    description:'Classical music and jazz',country:'France',language:'Multiple',isHD:true),
  // SCIENCE
  TvChannel(id:'nasa-public',name:'NASA TV Public',category:'Science',
    streamUrl:'https://ntv2.akamaized.net/hls/live/2014076/NASA-NTV2-HLS/master.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e5/NASA_logo.svg/200px-NASA_logo.svg.png',
    description:'NASA educational content',country:'USA',language:'English',isHD:true),
  TvChannel(id:'nhk-world',name:'NHK World',category:'Science',
    streamUrl:'https://nhkwlive-ojp.akamaized.net/hls/live/2003459/nhkwlive-ojp-en/index_1M.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5c/NHK_World_logo.svg/200px-NHK_World_logo.svg.png',
    description:'Japan NHK documentary and science',country:'Japan',language:'English',isHD:true),
  // KIDS
  TvChannel(id:'baby-first',name:'Baby First TV',category:'Kids',
    streamUrl:'https://babyfirsttv.akamaized.net/hls/live/babyfirst/stream.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9e/BabyTV_logo.svg/200px-BabyTV_logo.svg.png',
    description:'Educational content for toddlers',country:'International',language:'Multiple',isHD:true),
  TvChannel(id:'kidoodle',name:'Kidoodle TV',category:'Kids',
    streamUrl:'https://kidoodle.akamaized.net/hls/live/kidoodle/stream.m3u8',
    logo:'https://upload.wikimedia.org/wikipedia/commons/thumb/8/80/Cartoon_Network_2010_logo.svg/200px-Cartoon_Network_2010_logo.svg.png',
    description:'Safe streaming for kids',country:'Canada',language:'English',isHD:true),
];

List<TvChannel> channelsForCategory(String category) =>
    kTvChannels.where((c) => c.category == category).toList();

const kCategoryEmoji = {
  'News': '\u{1F4F0}', 'Sports': '\u26BD', 'Entertainment': '\u{1F3AC}',
  'Music': '\u{1F3B5}', 'Science': '\u{1F52D}', 'Kids': '\u{1F9F8}',
};

const kCategoryColors = {
  'News':          Color(0xFF1565C0),
  'Sports':        Color(0xFF2E7D32),
  'Entertainment': Color(0xFF6A1B9A),
  'Music':         Color(0xFFAD1457),
  'Science':       Color(0xFF00695C),
  'Kids':          Color(0xFFE65100),
};
