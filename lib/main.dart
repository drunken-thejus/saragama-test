import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
// pubspec.yaml dependencies (compatible with Dart SDK 2.19.2):
//
// dependencies:
//   flutter:
//     sdk: flutter
//   http: ^0.13.6       # last version supporting Dart 2.x
//   just_audio: ^0.9.34 # stable, supports Dart 2.x

// ─────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────
class SongResult {
  final String title;
  final String videoId;
  final List<String> artists;
  final String thumbnail;

  SongResult({
    required this.title,
    required this.videoId,
    required this.artists,
    required this.thumbnail,
  });

  factory SongResult.fromJson(Map<String, dynamic> json) => SongResult(
        title: json['title'] ?? '',
        videoId: json['video_url'] ?? '',
        artists: List<String>.from(json['artist'] ?? []),
        thumbnail: json['thumbnail'] ?? '',
      );

  String get artistLine => artists.join(', ');
}

// ─────────────────────────────────────────────
// YT-DLP SERVICE  — runs `yt-dlp -f bestaudio -g <url>`
// ─────────────────────────────────────────────
class YtDlpService {
  static Future<String> getAudioUrl(String videoId) async {
    final ytUrl = 'https://www.youtube.com/watch?v=$videoId';
    final result = await Process.run('yt-dlp', ['-f', 'bestaudio', '-g', ytUrl]);
    if (result.exitCode != 0) throw Exception('yt-dlp: ${result.stderr}');
    return (result.stdout as String).trim();
  }
}

// ─────────────────────────────────────────────
// AUTOCOMPLETE SERVICE
// ─────────────────────────────────────────────
class SearchService {
  static const _base = 'https://sara-autocomplete-crosverfied.onrender.com/autocomplete';

  static Future<List<SongResult>> search(String q) async {
    print("Sure");
    if (q.trim().isEmpty) return [];
    final uri = Uri.parse('$_base?q=${Uri.encodeComponent(q)}');
    print(uri);
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    print(res.statusCode);
    if (res.statusCode != 200) throw Exception('API error ${res.statusCode}');
    final List data = jsonDecode(res.body);
    print(data);
    return data.map((e) => SongResult.fromJson(e)).toList();
  }
}

// ─────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────
void main() => runApp(const SaragamaApp());

class SaragamaApp extends StatelessWidget {
  const SaragamaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Saragama',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0A0A),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF4D00),
            surface: Color(0xFF141414),
          ),
          fontFamily: 'monospace',
        ),
        home: const SearchPage(),
      );
}

// ─────────────────────────────────────────────
// SEARCH PAGE
// ─────────────────────────────────────────────
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _player = AudioPlayer();
  Timer? _debounce;

  List<SongResult> _results = [];
  SongResult? _currentSong;
  bool _searching = false;
  bool _loadingAudio = false;
  String? _error;

  // Player state
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      setState(() => _isPlaying = state.playing);
    });
    _player.positionStream.listen((p) => setState(() => _position = p));
    _player.durationStream.listen((d) => setState(() => _duration = d ?? Duration.zero));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── DEBOUNCED SEARCH ──
  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() { _results = []; _error = null; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _doSearch(value));
  }

  Future<void> _doSearch(String q) async {
    setState(() { _searching = true; _error = null; });
    try {
      final results = await SearchService.search(q);
      setState(() => _results = results);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _searching = false);
    }
  }

  // ── PLAY SONG ──
  Future<void> _playSong(SongResult song) async {
    setState(() { _loadingAudio = true; _currentSong = song; _error = null; });
    try {
      final url = await YtDlpService.getAudioUrl(song.videoId);
      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      setState(() => _error = 'Playback error: $e');
    } finally {
      setState(() => _loadingAudio = false);
    }
  }

  void _togglePlay() {
    if (_player.playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasPlayer = _currentSong != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── TOP BAR ──
            _buildHeader(),

            // ── SEARCH BOX ──
            _buildSearchBar(),

            // ── RESULTS ──
            Expanded(
              child: _buildResults(),
            ),

            // ── MINI PLAYER ──
            if (hasPlayer)
              _buildMiniPlayer(),

            SizedBox(height: hasPlayer ? 0 : 12),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4D00),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'SARAGAMA',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
                color: Color(0xFFF0ECE4),
              ),
            ),
          ],
        ),
      );

  Widget _buildSearchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: TextField(
            controller: _controller,
            onChanged: _onChanged,
            autofocus: true,
            style: const TextStyle(
              color: Color(0xFFF0ECE4),
              fontSize: 16,
              letterSpacing: 0.5,
            ),
            decoration: InputDecoration(
              hintText: 'Search songs, artists...',
              hintStyle: const TextStyle(color: Color(0xFF444444), fontSize: 15),
              prefixIcon: _searching
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: const Color(0xFFFF4D00),
                        ),
                      ),
                    )
                  : const Icon(Icons.search_rounded, color: Color(0xFF555555), size: 22),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF555555)),
                      onPressed: () {
                        _controller.clear();
                        setState(() { _results = []; _error = null; });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      );

  Widget _buildResults() {
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Color(0xFFFF4D00), fontSize: 13)),
      );
    }

    if (_results.isEmpty && _controller.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq_rounded, size: 48, color: const Color(0xFF222222)),
            const SizedBox(height: 12),
            const Text(
              'Type to discover music',
              style: TextStyle(color: Color(0xFF333333), fontSize: 14, letterSpacing: 1),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty && !_searching) {
      return const Center(
        child: Text('No results found', style: TextStyle(color: Color(0xFF444444))),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      itemCount: _results.length,
      itemBuilder: (_, i) => _SongTile(
        song: _results[i],
        isActive: _currentSong?.videoId == _results[i].videoId,
        isLoading: _loadingAudio && _currentSong?.videoId == _results[i].videoId,
        onTap: () => _playSong(_results[i]),
      ),
    );
  }

  Widget _buildMiniPlayer() {
    final song = _currentSong!;
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: const Border(top: BorderSide(color: Color(0xFF1E1E1E))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: const Color(0xFFFF4D00),
                  inactiveTrackColor: const Color(0xFF252525),
                  thumbColor: const Color(0xFFFF4D00),
                  overlayColor: const Color(0x22FF4D00),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: (v) {
                    final pos = Duration(milliseconds: (v * _duration.inMilliseconds).round());
                    _player.seek(pos);
                  },
                ),
              ),

              Row(
                children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      song.thumbnail,
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 46,
                        height: 46,
                        color: const Color(0xFF1E1E1E),
                        child: const Icon(Icons.music_note, color: Color(0xFF444444), size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Title + Artist
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF0ECE4),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artistLine,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Time
                  Text(
                    '${_fmt(_position)} / ${_fmt(_duration)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF555555)),
                  ),
                  const SizedBox(width: 12),

                  // Play/Pause
                  GestureDetector(
                    onTap: _loadingAudio ? null : _togglePlay,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4D00),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _loadingAudio
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SONG TILE
// ─────────────────────────────────────────────
class _SongTile extends StatelessWidget {
  final SongResult song;
  final bool isActive;
  final bool isLoading;
  final VoidCallback onTap;

  const _SongTile({
    required this.song,
    required this.isActive,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1A1208) : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? const Color(0xFFFF4D00).withOpacity(0.5) : const Color(0xFF1E1E1E),
          ),
        ),
        child: Row(
          children: [
            // Thumbnail
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    song.thumbnail,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 52,
                      height: 52,
                      color: const Color(0xFF1E1E1E),
                      child: const Icon(Icons.music_note, color: Color(0xFF444444)),
                    ),
                  ),
                ),
                if (isLoading)
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFF4D00),
                      ),
                    ),
                  ),
                if (isActive && !isLoading)
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.graphic_eq_rounded,
                        color: Color(0xFFFF4D00), size: 22),
                  ),
              ],
            ),

            const SizedBox(width: 14),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isActive ? const Color(0xFFFF4D00) : const Color(0xFFF0ECE4),
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artistLine,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF666666),
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Play icon
            Icon(
              isActive ? Icons.volume_up_rounded : Icons.play_circle_outline_rounded,
              color: isActive ? const Color(0xFFFF4D00) : const Color(0xFF333333),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}