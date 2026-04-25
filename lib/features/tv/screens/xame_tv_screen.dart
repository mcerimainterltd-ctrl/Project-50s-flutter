// lib/features/tv/screens/xame_tv_screen.dart
// XameTV 2.1 — 11,000+ live channels, dynamic fetch, search, swipe

import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../data/tv_channels.dart';
import 'package:xamepage/core/theme/app_theme.dart';

class XameTvScreen extends StatefulWidget {
  const XameTvScreen({Key? key}) : super(key: key);
  @override
  State<XameTvScreen> createState() => _XameTvScreenState();
}

class _XameTvScreenState extends State<XameTvScreen>
    with TickerProviderStateMixin {

  List<TvChannel> _all=[], _filtered=[];
  bool    _loading=true;
  String? _loadError;
  String  _category='All';
  int     _index=0;
  bool    _showOverlay=true, _showList=false, _showSearch=false;
  bool    _isMuted=false, _isFullscreen=false;
  String  _searchQuery='';
  Timer?  _overlayTimer;
  final   _searchCtrl=TextEditingController();
  final   _listCtrl=ScrollController();

  VideoPlayerController? _ctrl;
  bool _ready=false, _error=false, _buffering=true;
  int  _retries=0;

  late AnimationController _oAnim, _sAnim;
  late Animation<double>   _oFade;
  late Animation<Offset>   _sSlide;

  TvChannel? get _cur =>
      _filtered.isNotEmpty && _index < _filtered.length
          ? _filtered[_index] : null;

  @override
  void initState() {
    super.initState();
    _oAnim = AnimationController(vsync:this, duration:const Duration(milliseconds:300));
    _oFade = CurvedAnimation(parent:_oAnim, curve:Curves.easeInOut);
    _sAnim = AnimationController(vsync:this, duration:const Duration(milliseconds:200));
    _sSlide = Tween<Offset>(begin:const Offset(0,0.04), end:Offset.zero)
        .animate(CurvedAnimation(parent:_sAnim, curve:Curves.easeOut));
    _oAnim.forward();
    _fetch();
    _startTimer();
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _oAnim.dispose(); _sAnim.dispose();
    _ctrl?.dispose();
    _searchCtrl.dispose(); _listCtrl.dispose();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────
  Future<void> _fetch({bool force=false}) async {
    setState(() { _loading=true; _loadError=null; });
    try {
      final ch = await TvChannelService.fetchChannels(force:force);
      if (!mounted) return;
      setState(() { _all=ch; _loading=false; });
      _applyFilter();
      if (_filtered.isNotEmpty) _initPlayer(_filtered.first.streamUrl);
    } catch(e) {
      if (!mounted) return;
      setState(() { _loading=false; _loadError=e.toString(); });
    }
  }

  void _applyFilter() {
    var list = TvChannelService.filterByCategory(_all, _category);
    if (_searchQuery.isNotEmpty) list = TvChannelService.search(list, _searchQuery);
    setState(() { _filtered=list; _index=0; });
  }

  // ── Player ────────────────────────────────────────────────────────────
  Future<void> _initPlayer(String url) async {
    await _ctrl?.dispose();
    if (!mounted) return;
    setState(() { _ready=false; _error=false; _buffering=true; });
    if (url.isEmpty) { setState(() { _error=true; _buffering=false; }); return; }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _ctrl = c;
    try {
      await c.initialize();
      if (!mounted || _ctrl!=c) return;
      c.setLooping(true);
      c.setVolume(_isMuted ? 0 : 1);
      c.play();
      _sAnim.forward(from:0);
      setState(() { _ready=true; _buffering=false; _retries=0; });
    } catch(_) {
      if (!mounted || _ctrl!=c) return;
      setState(() { _error=true; _buffering=false; });
    }
  }

  void _switchTo(int i) {
    if (i==_index || i>=_filtered.length) return;
    setState(() => _index=i);
    _initPlayer(_filtered[i].streamUrl);
    _showBriefly();
    Future.delayed(const Duration(milliseconds:100), () {
      if (_listCtrl.hasClients)
        _listCtrl.animateTo((i*68.0).clamp(0,_listCtrl.position.maxScrollExtent),
            duration:const Duration(milliseconds:300), curve:Curves.easeOut);
    });
  }

  void _next() { if (_filtered.isEmpty) return; _switchTo((_index+1)%_filtered.length); }
  void _prev() { if (_filtered.isEmpty) return; _switchTo((_index-1+_filtered.length)%_filtered.length); }
  void _retry() { if (_retries>=3){_next();return;} _retries++; if(_cur!=null) _initPlayer(_cur!.streamUrl); }

  // ── Overlay ───────────────────────────────────────────────────────────
  void _startTimer() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds:5), () {
      if (mounted && !_showList && !_showSearch) {
        _oAnim.reverse(); setState(() => _showOverlay=false);
      }
    });
  }

  void _showBriefly() { setState(() => _showOverlay=true); _oAnim.forward(); _startTimer(); }

  void _toggleOverlay() {
    if (_showList || _showSearch) return;
    if (_showOverlay) { _overlayTimer?.cancel(); _oAnim.reverse(); setState(() => _showOverlay=false); }
    else _showBriefly();
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen=!_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft,DeviceOrientation.landscapeRight]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading && _all.isEmpty) return _splashScreen();
    if (_loadError!=null && _all.isEmpty) return _errorScreen();
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (_showSearch) { setState(() { _showSearch=false; _searchQuery=''; }); _applyFilter(); }
          else if (_showList) setState(() => _showList=false);
          else _toggleOverlay();
        },
        onVerticalDragEnd: (d) {
          if (_showList || _showSearch) return;
          if ((d.primaryVelocity??0) < -400) _next();
          if ((d.primaryVelocity??0) >  400) _prev();
        },
        onHorizontalDragEnd: (d) {
          if ((d.primaryVelocity??0) > 400) { setState(() => _showList=true); _showBriefly(); }
        },
        onLongPress: () { setState(() => _showList=true); _showBriefly(); },
        child: Stack(fit:StackFit.expand, children: [
          _videoLayer(),
          if (_buffering && !_error) _bufferingOverlay(),
          if (_error)                _errorOverlay(),
          _gradientLayer(),
          FadeTransition(opacity:_oFade, child:Column(children:[
            _topBar(), _catStrip(), Spacer(), _bottomBar(),
          ])),
          if (_showOverlay && !_showList) _swipeHint(),
          if (_showList)   _listPanel(),
          if (_showSearch) _searchPanel(),
        ]),
      ),
    );
  }

  // ── Screens ───────────────────────────────────────────────────────────
  Widget _splashScreen() => Scaffold(backgroundColor:Colors.black,
    body:Center(child:Column(mainAxisSize:MainAxisSize.min, children:[
      Icon(Icons.live_tv_rounded, color:XameColors.darkSurface.withValues(alpha: 0.5), size:64),
      SizedBox(height:20),
      CircularProgressIndicator(color:XameColors.darkBg.withValues(alpha: 0.54), strokeWidth:1.5),
      SizedBox(height:14),
      Text('Loading XameTV', style:TextStyle(color:XameColors.darkBg.withValues(alpha: 0.54),fontSize:14,fontWeight:FontWeight.w600)),
      SizedBox(height:6),
      Text('Fetching 11,000+ live channels', style:TextStyle(color:XameColors.darkSurface.withValues(alpha: 0.5),fontSize:11)),
    ])),
  );

  Widget _errorScreen() => Scaffold(backgroundColor:Colors.black,
    body:Center(child:Column(mainAxisSize:MainAxisSize.min, children:[
      Icon(Icons.wifi_off_rounded, color:XameColors.darkSurface.withValues(alpha: 0.5), size:56),
      SizedBox(height:14),
      Text('No connection', style:TextStyle(color:XameColors.darkBg.withValues(alpha: 0.6),fontSize:16,fontWeight:FontWeight.w600)),
      SizedBox(height:6),
      Text('Check your internet and retry', style:TextStyle(color:XameColors.darkSurface,fontSize:12)),
      SizedBox(height:22),
      _pill('Retry', ()=>_fetch(force:true), XameColors.darkSurface),
    ])),
  );

  // ── Video layer ───────────────────────────────────────────────────────
  Widget _videoLayer() {
    if (!_ready || _ctrl==null) {
      return _cur?.logo.isNotEmpty==true
          ? CachedNetworkImage(imageUrl:_cur!.logo, fit:BoxFit.contain,
              color:Colors.black54, colorBlendMode:BlendMode.darken,
              errorWidget:(_,__,___)=>ColoredBox(color:XameColors.darkBg))
          : ColoredBox(color:XameColors.darkBg);
    }
    return SlideTransition(position:_sSlide,
      child:Center(child:AspectRatio(
        aspectRatio: _ctrl!.value.aspectRatio>0 ? _ctrl!.value.aspectRatio : 16/9,
        child:VideoPlayer(_ctrl!),
      )),
    );
  }

  Widget _bufferingOverlay() => Center(child:Column(mainAxisSize:MainAxisSize.min, children:[
    SizedBox(width:40,height:40,
      child:CircularProgressIndicator(
          color:kCategoryColors[_category]??XameColors.darkBg.withValues(alpha: 0.54), strokeWidth:2)),
    SizedBox(height:10),
    if (_cur!=null) Text('Loading ${_cur!.name}...',
        style:TextStyle(color:XameColors.darkBg.withValues(alpha: 0.54),fontSize:11)),
  ]));

  Widget _errorOverlay() => Center(child:Column(mainAxisSize:MainAxisSize.min, children:[
    Icon(Icons.signal_cellular_connected_no_internet_4_bar_rounded,
        color:XameColors.darkSurface.withValues(alpha: 0.5), size:44),
    SizedBox(height:8),
    Text('Stream unavailable',
        style:TextStyle(color:XameColors.darkBg.withValues(alpha: 0.54),fontSize:13,fontWeight:FontWeight.w600)),
    if (_cur!=null) Text(_cur!.name, style:TextStyle(color:XameColors.darkSurface.withValues(alpha: 0.3),fontSize:10)),
    SizedBox(height:14),
    Row(mainAxisSize:MainAxisSize.min, children:[
      _pill(_retries>=3?'Next':'Retry', _retry, XameColors.darkSurface),
      SizedBox(width:8),
      _pill('Skip', _next, (kCategoryColors[_category]??Colors.blue).withOpacity(0.3)),
    ]),
  ]));

  Widget _gradientLayer() => Container(decoration:BoxDecoration(
    gradient:LinearGradient(
      begin:Alignment.topCenter, end:Alignment.bottomCenter,
      stops:[0.0,0.3,0.7,1.0],
      colors:[Color(0xCC000000),Colors.transparent,Colors.transparent,Color(0xDD000000)],
    ),
  ));

  // ── Top bar ───────────────────────────────────────────────────────────
  Widget _topBar() => SafeArea(child:Padding(
    padding:const EdgeInsets.fromLTRB(12,8,12,0),
    child:Row(children:[
      _ib(Icons.arrow_back_ios_new_rounded, ()=>Navigator.pop(context)),
      SizedBox(width:7),
      Container(
        padding:const EdgeInsets.symmetric(horizontal:9,vertical:4),
        decoration:BoxDecoration(
          gradient:LinearGradient(colors:[
            kCategoryColors[_category]??Colors.blue,
            (kCategoryColors[_category]??Colors.blue).withOpacity(0.6),
          ]),
          borderRadius:BorderRadius.circular(7),
        ),
        child:Row(mainAxisSize:MainAxisSize.min, children:[
          Icon(Icons.live_tv_rounded, color:XameColors.darkBg, size:12),
          SizedBox(width:4),
          Text('XAME TV', style:TextStyle(color:XameColors.darkBg,fontSize:9,
              fontWeight:FontWeight.w900,letterSpacing:1)),
        ]),
      ),
      SizedBox(width:5),
      Container(
        padding:const EdgeInsets.symmetric(horizontal:4,vertical:2),
        decoration:BoxDecoration(color:Colors.red,borderRadius:BorderRadius.circular(3)),
        child:Text('LIVE',style:TextStyle(color:XameColors.darkBg,fontSize:7,
            fontWeight:FontWeight.w900,letterSpacing:1)),
      ),
      if (_all.isNotEmpty) ...[
        SizedBox(width:5),
        Text('${_all.length}+ ch',style:TextStyle(color:XameColors.darkSurface.withValues(alpha: 0.3),fontSize:9)),
      ],
      Spacer(),
      _ib(Icons.search_rounded, (){setState((){_showSearch=true;_showList=false;});_showBriefly();}),
      SizedBox(width:5),
      _ib(_isMuted?Icons.volume_off_rounded:Icons.volume_up_rounded, (){
        setState(()=>_isMuted=!_isMuted); _ctrl?.setVolume(_isMuted?0:1); _showBriefly();
      }),
      SizedBox(width:5),
      _ib(_isFullscreen?Icons.fullscreen_exit_rounded:Icons.fullscreen_rounded,
          (){_toggleFullscreen();_showBriefly();}),
      SizedBox(width:5),
      _ib(Icons.refresh_rounded, (){TvChannelService.clearCache();_fetch(force:true);}),
    ]),
  ));

  Widget _ib(IconData icon, VoidCallback onTap) => GestureDetector(onTap:onTap,
    child:Container(width:32,height:32,
      decoration:BoxDecoration(color:Colors.black45,shape:BoxShape.circle,
          border:Border.all(color:XameColors.darkSurface)),
      child:Icon(icon,color:XameColors.darkBg,size:15)),
  );

  // ── Category strip ────────────────────────────────────────────────────
  Widget _catStrip() => Padding(
    padding:const EdgeInsets.only(top:10),
    child:SizedBox(height:32, child:ListView.builder(
      scrollDirection:Axis.horizontal,
      padding:const EdgeInsets.symmetric(horizontal:12),
      itemCount:kTvCategories.length,
      itemBuilder:(_,i) {
        final cat   = kTvCategories[i];
        final active= cat==_category;
        final color = kCategoryColors[cat]??Colors.blue;
        final count = TvChannelService.filterByCategory(_all,cat).length;
        return GestureDetector(
          onTap:(){
            setState((){_category=cat;_index=0;}); _applyFilter();
            if(_filtered.isNotEmpty) _initPlayer(_filtered.first.streamUrl);
            _showBriefly();
          },
          child:AnimatedContainer(
            duration:Duration(milliseconds:180),
            margin:const EdgeInsets.only(right:6),
            padding:const EdgeInsets.symmetric(horizontal:12,vertical:5),
            decoration:BoxDecoration(
              color:active?color:Colors.black45,
              borderRadius:BorderRadius.circular(16),
              border:Border.all(color:active?color:XameColors.darkBg.withOpacity(0.18)),
            ),
            child:Row(mainAxisSize:MainAxisSize.min, children:[
              Text(cat,style:TextStyle(color:XameColors.darkBg,fontSize:11,
                  fontWeight:active?FontWeight.w700:FontWeight.w400)),
              if(active && count>0)...[
                SizedBox(width:4),
                Text('$count',style:TextStyle(color:XameColors.darkBg.withValues(alpha: 0.6),fontSize:9)),
              ],
            ]),
          ),
        );
      },
    )),
  );

  // ── Bottom bar ────────────────────────────────────────────────────────
  Widget _bottomBar() => SafeArea(top:false, child:Padding(
    padding:const EdgeInsets.fromLTRB(14,0,14,20),
    child:Row(crossAxisAlignment:CrossAxisAlignment.end, children:[
      Container(width:48,height:48,
        decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(10),
            border:Border.all(color:XameColors.darkSurface)),
        child:ClipRRect(borderRadius:BorderRadius.circular(9),
          child:_cur?.logo.isNotEmpty==true
              ? CachedNetworkImage(imageUrl:_cur!.logo,fit:BoxFit.contain,
                  errorWidget:(_,__,___)=>_logoFb())
              : _logoFb(),
        ),
      ),
      SizedBox(width:10),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          mainAxisSize:MainAxisSize.min, children:[
        Text(_cur?.name??'—',style:TextStyle(color:XameColors.darkBg,fontSize:15,
            fontWeight:FontWeight.w700),maxLines:1,overflow:TextOverflow.ellipsis),
        SizedBox(height:2),
        Row(children:[
          if(_cur?.country.isNotEmpty==true)
            Text(_cur!.country,style:TextStyle(color:XameColors.darkSurface,fontSize:10)),
          if(_cur?.country.isNotEmpty==true && _cur?.language.isNotEmpty==true)
            Text(' · ',style:TextStyle(color:XameColors.darkSurface.withValues(alpha: 0.5),fontSize:10)),
          if(_cur?.language.isNotEmpty==true)
            Flexible(child:Text(_cur!.language,style:TextStyle(color:XameColors.darkSurface,fontSize:10),
                maxLines:1,overflow:TextOverflow.ellipsis)),
        ]),
        SizedBox(height:2),
        Text(_cur?.category??'',style:TextStyle(
            color:(kCategoryColors[_cur?.category]??Colors.blue).withOpacity(0.8),
            fontSize:10,fontWeight:FontWeight.w500)),
      ])),
      GestureDetector(
        onTap:(){setState(()=>_showList=true);_showBriefly();},
        child:Container(
          padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),
          decoration:BoxDecoration(color:XameColors.darkSurface,borderRadius:BorderRadius.circular(18),
              border:Border.all(color:XameColors.darkBg.withOpacity(0.18))),
          child:Row(mainAxisSize:MainAxisSize.min, children:[
            Icon(Icons.list_rounded,color:XameColors.darkBg,size:14),
            SizedBox(width:4),
            Text('${_index+1}/${_filtered.length}',
                style:TextStyle(color:XameColors.darkBg,fontSize:10,fontWeight:FontWeight.w600)),
          ]),
        ),
      ),
    ]),
  ));

  Widget _logoFb() => Center(child:Text(
    _cur?.name.isNotEmpty==true?_cur!.name[0].toUpperCase():'TV',
    style:TextStyle(color:XameColors.darkBg.withValues(alpha: 0.54),fontSize:18,fontWeight:FontWeight.w800)));

  Widget _swipeHint() => Align(alignment:Alignment.centerRight,
    child:Padding(padding:const EdgeInsets.only(right:10),
      child:Column(mainAxisSize:MainAxisSize.min, children:const[
        Icon(Icons.keyboard_arrow_up_rounded,color:XameColors.darkSurface.withValues(alpha: 0.3),size:16),
        SizedBox(height:2),
        Text('Swipe',style:TextStyle(color:XameColors.darkSurface.withValues(alpha: 0.5),fontSize:8)),
        SizedBox(height:2),
        Icon(Icons.keyboard_arrow_down_rounded,color:XameColors.darkSurface.withValues(alpha: 0.3),size:16),
      ]),
    ),
  );

  // ── Channel list panel ────────────────────────────────────────────────
  Widget _listPanel() => GestureDetector(
    onTap:()=>setState(()=>_showList=false),
    child:Container(color:Colors.black54,
      child:Align(alignment:Alignment.centerRight,
        child:GestureDetector(onTap:(){},
          child:Container(
            width:MediaQuery.of(context).size.width*0.78,
            color:XameColors.darkBg,
            child:Column(children:[
              SafeArea(bottom:false,child:Padding(
                padding:const EdgeInsets.fromLTRB(14,14,14,8),
                child:Row(children:[
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                    Text(_category,style:TextStyle(
                        color:kCategoryColors[_category]??Colors.blue,
                        fontSize:16,fontWeight:FontWeight.w800)),
                    Text('${_filtered.length} channels',
                        style:TextStyle(color:XameColors.darkSurface,fontSize:10)),
                  ])),
                  GestureDetector(onTap:()=>setState(()=>_showList=false),
                      child:Icon(Icons.close_rounded,color:XameColors.darkSurface,size:18)),
                ]),
              )),
              Divider(color:XameColors.darkSurface,height:1),
              Expanded(child:ListView.builder(
                controller:_listCtrl,
                padding:const EdgeInsets.symmetric(vertical:6),
                itemCount:_filtered.length,
                itemBuilder:(_,i) {
                  final ch    = _filtered[i];
                  final active= i==_index;
                  final color = kCategoryColors[_category]??Colors.blue;
                  return GestureDetector(
                    onTap:(){setState(()=>_showList=false);_switchTo(i);},
                    child:AnimatedContainer(
                      duration:Duration(milliseconds:150),
                      margin:const EdgeInsets.symmetric(horizontal:8,vertical:2),
                      padding:const EdgeInsets.all(10),
                      decoration:BoxDecoration(
                        color:active?color.withOpacity(0.18):Colors.transparent,
                        borderRadius:BorderRadius.circular(10),
                        border:Border.all(color:active?color.withOpacity(0.4):Colors.transparent),
                      ),
                      child:Row(children:[
                        Container(width:38,height:38,
                          decoration:BoxDecoration(color:XameColors.darkSurface,
                              borderRadius:BorderRadius.circular(7)),
                          child:ClipRRect(borderRadius:BorderRadius.circular(7),
                            child:ch.logo.isNotEmpty
                                ?CachedNetworkImage(imageUrl:ch.logo,fit:BoxFit.contain,
                                    errorWidget:(_,__,___)=>Center(child:Text(
                                        ch.name.isNotEmpty?ch.name[0]:'T',
                                        style:TextStyle(color:XameColors.darkBg.withValues(alpha: 0.54),
                                            fontWeight:FontWeight.w700))))
                                :Center(child:Text(ch.name.isNotEmpty?ch.name[0]:'T',
                                    style:TextStyle(color:XameColors.darkBg.withValues(alpha: 0.54),
                                        fontWeight:FontWeight.w700))),
                          ),
                        ),
                        SizedBox(width:9),
                        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
                            mainAxisSize:MainAxisSize.min, children:[
                          Text(ch.name,style:TextStyle(color:active?XameColors.darkBg:XameColors.darkBg.withValues(alpha: 0.7),
                              fontSize:12,fontWeight:active?FontWeight.w700:FontWeight.w400),
                              maxLines:1,overflow:TextOverflow.ellipsis),
                          Text([if(ch.country.isNotEmpty)ch.country,
                                if(ch.language.isNotEmpty)ch.language].join(' · '),
                              style:TextStyle(color:XameColors.darkSurface.withValues(alpha: 0.3),fontSize:9),
                              maxLines:1,overflow:TextOverflow.ellipsis),
                        ])),
                        if(active) Container(width:6,height:6,
                            decoration:BoxDecoration(color:color,shape:BoxShape.circle)),
                      ]),
                    ),
                  );
                },
              )),
            ]),
          ),
        ),
      ),
    ),
  );

  // ── Search panel ──────────────────────────────────────────────────────
  Widget _searchPanel() => Container(
    color:Colors.black87,
    child:SafeArea(child:Column(children:[
      Padding(
        padding:const EdgeInsets.fromLTRB(12,12,12,0),
        child:Row(children:[
          Expanded(child:Container(
            height:42,
            decoration:BoxDecoration(color:XameColors.darkSurface,
                borderRadius:BorderRadius.circular(22),
                border:Border.all(color:XameColors.darkBg.withOpacity(0.18))),
            child:TextField(
              controller:_searchCtrl, autofocus:true,
              style:TextStyle(color:XameColors.darkBg,fontSize:14),
              decoration:InputDecoration(
                hintText:'Search channels, country, language...',
                hintStyle:TextStyle(color:XameColors.darkSurface.withValues(alpha: 0.3),fontSize:12),
                prefixIcon:Icon(Icons.search_rounded,color:XameColors.darkSurface,size:18),
                border:InputBorder.none,
                contentPadding:EdgeInsets.symmetric(vertical:12),
              ),
              onChanged:(q){setState(()=>_searchQuery=q);_applyFilter();},
            ),
          )),
          SizedBox(width:8),
          GestureDetector(
            onTap:(){setState((){_showSearch=false;_searchQuery='';_searchCtrl.clear();});
                _applyFilter();},
            child:Text('Cancel',style:TextStyle(color:XameColors.darkBg.withValues(alpha: 0.6),fontSize:13)),
          ),
        ]),
      ),
      Padding(
        padding:const EdgeInsets.fromLTRB(12,8,12,4),
        child:Row(children:[
          Text('${_filtered.length} results',
              style:TextStyle(color:XameColors.darkSurface,fontSize:11)),
        ]),
      ),
      Divider(color:XameColors.darkSurface,height:1),
      Expanded(child:ListView.builder(
        padding:const EdgeInsets.symmetric(vertical:6),
        itemCount:_filtered.length.clamp(0,200),
        itemBuilder:(_,i){
          final ch=_filtered[i];
          return GestureDetector(
            onTap:(){
              setState((){_showSearch=false;_searchQuery='';_searchCtrl.clear();});
              _switchTo(i);
            },
            child:Padding(
              padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
              child:Row(children:[
                Container(width:36,height:36,
                  decoration:BoxDecoration(color:XameColors.darkSurface,
                      borderRadius:BorderRadius.circular(6)),
                  child:ch.logo.isNotEmpty
                      ?ClipRRect(borderRadius:BorderRadius.circular(6),
                          child:CachedNetworkImage(imageUrl:ch.logo,fit:BoxFit.contain,
                              errorWidget:(_,__,___)=>Center(child:Text(
                                  ch.name.isNotEmpty?ch.name[0]:'T',
                                  style:TextStyle(color:XameColors.darkBg.withValues(alpha: 0.54))))))
                      :Center(child:Text(ch.name.isNotEmpty?ch.name[0]:'T',
                          style:TextStyle(color:XameColors.darkBg.withValues(alpha: 0.54)))),
                ),
                SizedBox(width:10),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                  Text(ch.name,style:TextStyle(color:XameColors.darkBg,fontSize:13),
                      maxLines:1,overflow:TextOverflow.ellipsis),
                  Text([ch.category,if(ch.country.isNotEmpty)ch.country,
                        if(ch.language.isNotEmpty)ch.language].join(' · '),
                      style:TextStyle(color:XameColors.darkSurface,fontSize:10),
                      maxLines:1,overflow:TextOverflow.ellipsis),
                ])),
                Container(
                  padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                  decoration:BoxDecoration(
                      color:(kCategoryColors[ch.category]??Colors.blue).withOpacity(0.25),
                      borderRadius:BorderRadius.circular(4)),
                  child:Text(ch.category,style:TextStyle(
                      color:kCategoryColors[ch.category]??Colors.blue,
                      fontSize:8,fontWeight:FontWeight.w700)),
                ),
              ]),
            ),
          );
        },
      )),
    ])),
  );

  Widget _pill(String label, VoidCallback onTap, Color color) => GestureDetector(
    onTap:onTap,
    child:Container(
      padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
      decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(20),
          border:Border.all(color:XameColors.darkBg.withOpacity(0.18))),
      child:Text(label,style:TextStyle(color:XameColors.darkBg,
          fontWeight:FontWeight.w600,fontSize:12)),
    ),
  );
}
