import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
// 保持使用 dart:html，但增加相容性處理，確保 Web 環境運行
import 'dart:html' as html; 

void main() => runApp(const NimTrapApp());

class NimTrapApp extends StatelessWidget {
  const NimTrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8E9775)),
      ),
      home: const NimSinglePileScreen(),
    );
  }
}

class GameMove {
  final int round;
  final String player;
  final int before;
  final int take;
  final int after;
  final bool isBest;
  final double? time;
  final int? confidence;

  GameMove({
    required this.round,
    required this.player,
    required this.before,
    required this.take,
    required this.after,
    required this.isBest,
    this.time,
    this.confidence,
  });
}

class NimSinglePileScreen extends StatefulWidget {
  const NimSinglePileScreen({super.key});

  @override
  State<NimSinglePileScreen> createState() => _NimSinglePileScreenState();
}

class _NimSinglePileScreenState extends State<NimSinglePileScreen> {
  int currentPile = 0;
  int initialRoundValue = 0;
  String? mode;
  bool gameStarted = false;
  bool isPreviewing = false;
  bool isAiThinking = false;
  bool isPlayerTurn = false;
  int countdown = 5;
  Timer? _previewTimer;
  List<GameMove> allMoves = [];
  List<int> sessionGTargets = [];
  int roundCounter = 1;
  final Stopwatch stopwatch = Stopwatch();

  final List<int> gOdd = [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0];
  final List<int> gSquare = [0, 1, 0, 1, 2, 0, 1, 0, 1, 2, 0, 1, 0, 1, 2, 0, 1, 0, 1, 2, 0, 1, 0, 1, 2, 3, 2, 3, 4, 5, 3, 2, 3, 4, 0, 1, 2, 3, 2, 0, 1, 0, 1, 2, 0, 1, 0, 1, 2, 0, 1];

  int getG(int n) {
    if (n < 0 || n > 50) return 0;
    return (mode == "奇數 (1,3,5,7,9)") ? gOdd[n] : gSquare[n];
  }

  void autoSendToGoogle(GameMove data) {
    const String formId = "1FAIpQLSf4GrHPwqVvIPAXoDvxmgDtEtDy-zKp9FLwXi6qLVvSlbcEXQ";
    final baseUrl = "https://docs.google.com/forms/d/e/$formId/formResponse";
    
    // 構建參數
    final Map<String, String> fields = {
      "entry.1200922991": data.round.toString(),
      "entry.466307744": data.player,
      "entry.546372114": data.before.toString(),
      "entry.175568571": data.take.toString(),
      "entry.1685802346": data.isBest ? '是' : '否',
      "entry.1462368715": (data.time ?? 0).toStringAsFixed(2),
      "entry.1248902856": (data.confidence ?? 0).toString()
    };

    final queryString = fields.entries.map((e) => "${e.key}=${Uri.encodeComponent(e.value)}").join("&");
    final finalUrl = "$baseUrl?$queryString&submit=Submit";

    try {
      // 使用 Image 標籤發送請求是繞過 CORS 且確保數據送出的最古老、最穩定的 Web 技巧
      html.ImageElement().src = finalUrl;
      debugPrint("數據傳送已觸發 (背景模式)");
    } catch (e) {
      debugPrint("傳送失敗: $e");
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  void _startNewExperiment() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("實驗規則確認"),
        content: Text(mode == "奇數 (1,3,5,7,9)"
            ? "規則：每次拿走 1, 3, 5, 7, 9。\n目標：拿走最後一個的人獲勝。"
            : "規則：每次拿走平方數 1, 4, 9, 16, 25。\n目標：拿走最後一個的人獲勝。"),
        actions: [
          ElevatedButton(
              onPressed: () {
                Navigator.pop(c);
                allMoves.clear();
                roundCounter = 1;
                sessionGTargets = (mode == "奇數 (1,3,5,7,9)") ? [0, 0, 0, 1, 1, 1] : [0, 1, 2, 3, 4, 5];
                sessionGTargets.shuffle();
                _setupRound();
              },
              child: const Text("開始"))
        ],
      ),
    );
  }

  void _setupRound() {
    int targetG = sessionGTargets[roundCounter - 1];
    List<int> candidates = [for (int i = 15; i <= 50; i++) if (getG(i) == targetG) i];
    initialRoundValue = candidates[Random().nextInt(candidates.length)];
    currentPile = initialRoundValue;
    setState(() {
      gameStarted = true;
      isPreviewing = true;
      countdown = 5;
    });
    _previewTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown > 1) {
        setState(() => countdown--);
      } else {
        timer.cancel();
        _executeAiFirstMove();
      }
    });
  }

  void _executeAiFirstMove() {
    setState(() {
      isPreviewing = false;
      isAiThinking = true;
    });
    Future.delayed(const Duration(milliseconds: 1500), () => _aiAction());
  }

  void _aiAction() {
    List<int> moves = (mode == "奇數 (1,3,5,7,9)") ? [1, 3, 5, 7, 9] : [1, 4, 9, 16, 25];
    int before = currentPile;
    int take = -1;
    List<int> winMoves = [for (int m in moves) if (currentPile >= m && getG(currentPile - m) == 0) m];
    
    // 增加一點隨機性與狡詐度
    if (winMoves.isNotEmpty && Random().nextDouble() > 0.4) {
      take = winMoves[Random().nextInt(winMoves.length)];
    } else {
      List<int> allPossible = [for (int m in moves) if (currentPile >= m) m];
      take = allPossible[Random().nextInt(allPossible.length)];
    }
    
    currentPile -= take;
    var move = GameMove(
      round: roundCounter,
      player: "AI",
      before: before,
      take: take,
      after: currentPile,
      isBest: getG(currentPile) == 0,
    );
    allMoves.add(move);
    autoSendToGoogle(move);
    
    if (currentPile == 0) {
      _showEnd("AI 獲勝");
    } else {
      setState(() {
        isAiThinking = false;
        isPlayerTurn = true;
        stopwatch.reset();
        stopwatch.start();
      });
    }
  }

  void _handlePlayerMove(int m) {
    stopwatch.stop();
    double elapsed = stopwatch.elapsedMilliseconds / 1000.0;
    int before = currentPile;
    double conf = 50;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
          builder: (c, setS) => AlertDialog(
                title: const Text("信心評估"),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text("拿走：$m，剩餘：${before - m}"),
                  Slider(value: conf, max: 100, divisions: 10, onChanged: (v) => setS(() => conf = v)),
                  Text("信心：${conf.toInt()}%"),
                ]),
                actions: [
                  ElevatedButton(
                      onPressed: () {
                        Navigator.pop(c);
                        setState(() {
                          currentPile -= m;
                          var move = GameMove(
                            round: roundCounter,
                            player: "Human",
                            before: before,
                            take: m,
                            after: currentPile,
                            isBest: getG(currentPile) == 0,
                            time: elapsed,
                            confidence: conf.toInt(),
                          );
                          allMoves.add(move);
                          autoSendToGoogle(move);
                          if (currentPile == 0) {
                            _showEnd("玩家獲勝");
                          } else {
                            isPlayerTurn = false;
                            isAiThinking = true;
                            Future.delayed(const Duration(milliseconds: 1500), () => _aiAction());
                          }
                        });
                      },
                      child: const Text("確定"))
                ],
              )),
    );
  }

  void _showEnd(String winner) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text("$winner (第 $roundCounter 局)"),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: DataTable(
              columnSpacing: 10,
              columns: const [DataColumn(label: Text("誰")), DataColumn(label: Text("拿")), DataColumn(label: Text("準")), DataColumn(label: Text("信心"))],
              rows: allMoves
                  .where((m) => m.round == roundCounter)
                  .map((m) => DataRow(cells: [
                        DataCell(Text(m.player)),
                        DataCell(Text("${m.take}")),
                        DataCell(Text(m.isBest ? "✓" : "✘")),
                        DataCell(Text(m.confidence != null ? "${m.confidence}%" : "-")),
                      ]))
                  .toList(),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
              onPressed: () {
                Navigator.pop(c);
                if (roundCounter < 6) {
                  roundCounter++;
                  _setupRound();
                } else {
                  setState(() => gameStarted = false);
                }
              },
              child: Text(roundCounter < 6 ? "下一局" : "實驗結束"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("博弈實驗數據採集系統"), centerTitle: true),
      body: !gameStarted ? _buildHome() : _buildGame(),
    );
  }

  Widget _buildHome() {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text("選擇模式以開始實驗", style: TextStyle(fontSize: 20)),
      const SizedBox(height: 20),
      DropdownButton<String>(
        value: mode,
        hint: const Text("點此選擇規則"),
        items: ["奇數 (1,3,5,7,9)", "平方數 (1,4,9,16,25)"]
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: (v) => setState(() => mode = v),
      ),
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: mode == null ? null : _startNewExperiment,
        child: const Text("啟動實驗"),
      ),
    ]));
  }

  Widget _buildGame() {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text("第 $roundCounter / 6 局", style: const TextStyle(color: Colors.grey)),
      if (isPreviewing) ...[
        const SizedBox(height: 40),
        const Text("觀察階段", style: TextStyle(fontSize: 24)),
        Text("$initialRoundValue", style: const TextStyle(fontSize: 100, fontWeight: FontWeight.bold)),
        Text("AI 將在 $countdown 秒後行動", style: const TextStyle(color: Colors.red)),
      ] else ...[
        const SizedBox(height: 40),
        CircleAvatar(radius: 60, child: Text("$currentPile", style: const TextStyle(fontSize: 48))),
        const SizedBox(height: 50),
        if (isAiThinking)
          const CircularProgressIndicator()
        else if (isPlayerTurn)
          Wrap(
              spacing: 15,
              children: ((mode == "奇數 (1,3,5,7,9)") ? [1, 3, 5, 7, 9] : [1, 4, 9, 16, 25])
                  .where((m) => currentPile >= m)
                  .map((m) => ElevatedButton(
                        onPressed: () => _handlePlayerMove(m),
                        child: Text("$m"),
                      ))
                  .toList()),
      ]
    ]));
  }
}
