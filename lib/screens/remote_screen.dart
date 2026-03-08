import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/samsung_tv_service.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  final SamsungTVService _tv = SamsungTVService();
  bool _connected = false;
  bool _scanning = false;
  List<String> _foundTVs = [];
  String _connectedIP = '';
  final String _connectedName = 'Living Room TV';

  // --- Ads Variables ---
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  
  InterstitialAd? _interstitialAd;
  int _clickCount = 0;
  
  RewardedAd? _rewardedAd;
  bool _isRewardedAdLoaded = false;
  // ---------------------

  static const _bg = Color(0xFF101722);
  static const _card = Color(0xFF1a2235);
  static const _blue = Color(0xFF0d69f2);
  static const _border = Color(0xFF2a3a55);

  @override
  void initState() {
    super.initState();
    _tv.onConnectionChanged = (v) => setState(() => _connected = v);
    _loadAd();
  }

  void _loadAd() {
    // Banner Ad
    final bannerId = Platform.isAndroid
        ? 'ca-app-pub-6500154299593172/1589134287' 
        : 'ca-app-pub-6500154299593172/1589134287';

    _bannerAd = BannerAd(
      adUnitId: bannerId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() => _isAdLoaded = true),
        onAdFailedToLoad: (ad, err) {
          debugPrint('BannerAd failed: $err');
          ad.dispose();
        },
      ),
    )..load();

    _loadInterstitialAd();
    _loadRewardedAd();
  }

  void _loadInterstitialAd() {
    final interstitialId = Platform.isAndroid
        ? 'ca-app-pub-6500154299593172/4291173456'
        : 'ca-app-pub-6500154299593172/4291173456';

    InterstitialAd.load(
      adUnitId: interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _setupInterstitialCallbacks();
        },
        onAdFailedToLoad: (err) => debugPrint('Interstitial failed: $err'),
      ),
    );
  }

  void _setupInterstitialCallbacks() {
    _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitialAd(); // Load the next one
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _loadInterstitialAd();
      },
    );
  }

  void _loadRewardedAd() {
    final rewardedId = Platform.isAndroid
        ? 'ca-app-pub-6500154299593172/2597596640'
        : 'ca-app-pub-6500154299593172/2597596640';

    RewardedAd.load(
      adUnitId: rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          setState(() => _isRewardedAdLoaded = true);
          _rewardedAd = ad;
          _rewardedAd?.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              setState(() => _isRewardedAdLoaded = false);
              ad.dispose();
              _loadRewardedAd();
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              setState(() => _isRewardedAdLoaded = false);
              ad.dispose();
              _loadRewardedAd();
            },
          );
        },
        onAdFailedToLoad: (err) => debugPrint('Rewarded failed: $err'),
      ),
    );
  }

  void _showInterstitialIfReady() {
    _clickCount++;
    if (_clickCount >= 10 && _interstitialAd != null) {
      _interstitialAd!.show();
      _interstitialAd = null;
      _clickCount = 0;
    }
  }

  void _showRewardedAd() {
    if (_isRewardedAdLoaded && _rewardedAd != null) {
      _rewardedAd!.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thank you for supporting the developer! ❤️')),
          );
        }
      });
      _rewardedAd = null;
      setState(() => _isRewardedAdLoaded = false);
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    _tv.disconnect();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() { _scanning = true; _foundTVs = []; });
    final tvs = await SamsungTVService.scanForTVs();
    setState(() { _scanning = false; _foundTVs = tvs; });
    if (tvs.isNotEmpty) {
      _showTVList(tvs);
    } else {
      _showManualIP();
    }
  }

  void _showTVList(List<String> tvs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          const Text('TVs Found', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...tvs.map((ip) => ListTile(
            leading: const Icon(Icons.tv, color: Color(0xFF0d69f2)),
            title: Text(ip, style: const TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _connectTo(ip); },
          )),
        ],
      ),
    );
  }

  void _showManualIP() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Enter TV IP', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '192.168.1.100',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF0d69f2))),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(context); _connectTo(ctrl.text.trim()); },
            child: const Text('Connect', style: TextStyle(color: Color(0xFF0d69f2))),
          ),
        ],
      ),
    );
  }

  Future<void> _connectTo(String ip) async {
    setState(() { _connectedIP = ip; });
    
    // Show a dialog telling the user to check the TV
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: _blue),
            const SizedBox(height: 20),
            const Text('Connecting to TV...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('Please check your TV for a permission prompt and select "Allow".', 
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      ),
    );

    final ok = await _tv.connect(ip);
    
    if (mounted) Navigator.pop(context); // Close connecting dialog

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect to $ip. Make sure you accepted the prompt on TV.'), backgroundColor: Colors.red),
      );
    }
  }

  void _key(String key, {bool isSafeBtn = false}) {
    HapticFeedback.lightImpact();
    _tv.sendKey(key);
    
    // Only count non-critical buttons for ads to avoid being annoying
    if (isSafeBtn) {
      _showInterstitialIfReady();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildNavButtons(),
                    const SizedBox(height: 28),
                    _buildDPad(),
                    const SizedBox(height: 28),
                    _buildVolumeChannel(),
                    const SizedBox(height: 28),
                    _buildStreamingButtons(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            _buildAdBanner(),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          // Connection status pill
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: (_connected ? _blue : Colors.grey).withOpacity(0.12),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: (_connected ? _blue : Colors.grey).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi, color: _connected ? _blue : Colors.grey, size: 14),
                const SizedBox(width: 6),
                Text(
                  _connected ? 'Connected: $_connectedName' : 'Not Connected',
                  style: TextStyle(
                    color: _connected ? _blue : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _iconBtn(Icons.menu, () => _scan()),
              const Expanded(
                child: Text('Mando Smart TV',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              _iconBtn(Icons.power_settings_new, () => _key('KEY_POWER', isSafeBtn: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Icon(icon, color: Colors.grey[400], size: 22),
      ),
    );
  }

  Widget _buildNavButtons() {
    final btns = [
      (Icons.arrow_back, 'Back', 'KEY_RETURN'),
      (Icons.home, 'Home', 'KEY_HOME'),
      (Icons.settings, 'Input', 'KEY_SOURCE'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: btns.map((b) => _navBtn(b.$1, b.$2, b.$3)).toList(),
    );
  }

  Widget _navBtn(IconData icon, String label, String key) {
    return GestureDetector(
      onTap: () => _key(key, isSafeBtn: true),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Icon(icon, color: Colors.grey[300], size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
        ],
      ),
    );
  }

  Widget _buildDPad() {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _card.withOpacity(0.3),
              border: Border.all(color: _border, width: 3),
            ),
          ),
          // Up
          Positioned(top: 8, child: _dpadBtn(Icons.keyboard_arrow_up, 'KEY_UP')),
          // Down
          Positioned(bottom: 8, child: _dpadBtn(Icons.keyboard_arrow_down, 'KEY_DOWN')),
          // Left
          Positioned(left: 8, child: _dpadBtn(Icons.keyboard_arrow_left, 'KEY_LEFT')),
          // Right
          Positioned(right: 8, child: _dpadBtn(Icons.keyboard_arrow_right, 'KEY_RIGHT')),
          // OK center
          GestureDetector(
            onTap: () => _key('KEY_ENTER'),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _blue,
                boxShadow: [BoxShadow(color: _blue.withOpacity(0.4), blurRadius: 20, spreadRadius: 2)],
              ),
              child: const Center(
                child: Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dpadBtn(IconData icon, String key) {
    return GestureDetector(
      onTap: () => _key(key),
      child: Container(
        width: 56,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.transparent,
        ),
        child: Icon(icon, color: Colors.white, size: 32),
      ),
    );
  }

  Widget _buildVolumeChannel() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _verticalControl('VOL', Icons.add, Icons.remove, 'KEY_VOLUP', 'KEY_VOLDOWN'),
        GestureDetector(
          onTap: () => _key('KEY_MUTE'),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _card,
              border: Border.all(color: _border),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12)],
            ),
            child: const Icon(Icons.mic, color: _blue, size: 28),
          ),
        ),
        _verticalControl('CH', Icons.expand_less, Icons.expand_more, 'KEY_CHUP', 'KEY_CHDOWN'),
      ],
    );
  }

  Widget _verticalControl(String label, IconData up, IconData down, String keyUp, String keyDown) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: _card.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _key(keyUp),
            child: Padding(padding: const EdgeInsets.all(12), child: Icon(up, color: Colors.white, size: 22)),
          ),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold)),
          GestureDetector(
            onTap: () => _key(keyDown),
            child: Padding(padding: const EdgeInsets.all(12), child: Icon(down, color: Colors.white, size: 22)),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingButtons() {
    return Row(
      children: [
        Expanded(child: _streamBtn('NETFLIX', const Color(0xFFE50914), Colors.white, 'KEY_NETFLIX')),
        const SizedBox(width: 10),
        Expanded(child: _streamBtn('YouTube', Colors.white, const Color(0xFFFF0000), 'KEY_YOUTUBE')),
        const SizedBox(width: 10),
        Expanded(child: _streamBtn('Disney+', const Color(0xFF0063e5), Colors.white, 'KEY_DISNEYPLUS')),
      ],
    );
  }

  Widget _streamBtn(String label, Color bg, Color text, String key) {
    return GestureDetector(
      onTap: () => _key(key, isSafeBtn: true),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: bg.withOpacity(0.3), blurRadius: 8)],
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildAdBanner() {
    if (_isAdLoaded && _bannerAd != null) {
      return Container(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: AdWidget(ad: _bannerAd!),
      );
    }
    
    return Container(
      width: double.infinity,
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _card.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.9),
        border: const Border(top: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _bottomNavItem(Icons.settings_remote, 'Remote', true),
          
          // Support Developer Button (Rewarded Ad trigger)
          if (_isRewardedAdLoaded)
            GestureDetector(
              onTap: _showRewardedAd,
              child: _bottomNavItem(Icons.favorite, 'Support dev', false, color: Colors.pinkAccent),
            )
          else 
            _bottomNavItem(Icons.grid_view, 'Apps', false),

          _bottomNavItem(Icons.search, 'Search', false),
          _bottomNavItem(Icons.keyboard, 'Input', false),
        ],
      ),
    );
  }

  Widget _bottomNavItem(IconData icon, String label, bool active, {Color? color}) {
    final itemColor = color ?? (active ? _blue : Colors.grey[500]);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: itemColor, size: 22),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: itemColor, fontSize: 10, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
