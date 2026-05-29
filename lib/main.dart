import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:math';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  // Wait for the app to find and unlock the .env vault before starting
  await dotenv.load(fileName: ".env");
  runApp(const LifeSimulatorApp());
}

class LifeSimulatorApp extends StatelessWidget {
  const LifeSimulatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Life Simulator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // ---------------------------------------------------------
  // Pulls the key safely from the hidden .env file
  static final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? 'KEY_NOT_FOUND';
  // ---------------------------------------------------------

// --- GAME STATE ---
  String _gender = '';
  int _age = 0;
  int _health = 90;
  int _money = 0; 
  String _job = 'Unemployed'; 
  int _salary = 0;            
  List<String> _inventory = []; 
  Map<String, int> _relationships = {}; // <-- NEW: The Social Ledger
  bool _isGenerating = false;
  
  // Crossroads Variables
  bool _awaitingChoice = false;
  List<String> _currentChoices = [];

  final List<String> _lifeHistory = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _startNewLife();
  }

  void _startNewLife() {
    _gender = Random().nextBool() ? 'Male' : 'Female';
    _health = 90;
    _money = 0; 
    _job = 'Unemployed'; 
    _salary = 0;         
    _inventory.clear(); 
    _relationships.clear(); // <-- NEW: You are born knowing nobody
    _lifeHistory.clear();
    _lifeHistory.add("Year 0: You were born $_gender. You cry loudly, letting the world know you have arrived.");
  }


Future<void> _ageUp({String? playerChoice}) async {
    if (_health <= 0) return;

    setState(() {
      _isGenerating = true;
      if (playerChoice == null) {
        _age++;
        _money += _salary; 
      }
    });

    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      
      bool isCrossroads = _age % 5 == 0 && _age > 0 && playerChoice == null;
      
      // Tell the AI what you own and who you know
      String assets = _inventory.isEmpty ? "None" : _inventory.join(', ');
      String relations = _relationships.isEmpty ? "None" : _relationships.entries.map((e) => "${e.key} (${e.value}/100)").join(', ');
      
      String prompt = '';

      if (playerChoice != null) {
        prompt = '''
        Player: $_age yrs old, $_gender. Health: $_health. Wealth: \$$_money. Job: $_job. Assets: $assets.
        Relationships: $relations.
        They chose: "$playerChoice". Write a 2-sentence outcome. 
        If dangerous, include "[Health -15]". If healthy, include "[Health +10]".
        If money changes, include "[Money +X]" or "[Money -X]".
        If job changes, include "[Set Job: Title]" and "[Set Salary: Amount]".
        If they buy an item, include "[Buy: Item, Cost]".
        If they meet someone new or a relationship changes, include exactly "[Rel: Person Name, +X]" or "[Rel: Person Name, -X]". Example: [Rel: Noel, +15]
        ''';
      } else if (isCrossroads) {
        prompt = '''
        Player just turned $_age. Health: $_health. Wealth: \$$_money. Job: $_job. Assets: $assets.
        Relationships: $relations.
        Generate a major life dilemma. Incorporate their existing relationships or introduce new NPCs.
        CRITICAL RULE: PROVIDE EXACTLY 3 DISTINCT CHOICES. 
        Format EXACTLY like this:
        EVENT: [2 sentence description]
        CHOICE: [First choice]
        CHOICE: [Second choice]
        CHOICE: [Third choice]
        ''';
      } else {
        prompt = '''
        Player just turned $_age. Health: $_health. Wealth: \$$_money. Job: $_job. Assets: $assets.
        Relationships: $relations.
        Write a single, 1-sentence life event. Do not give choices. 
        If money changes, include "[Money +X]" or "[Money -X]".
        If a relationship changes or starts, include "[Rel: Name, +X]" or "[Rel: Name, -X]". 
        ''';
      }

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      final responseText = response.text?.trim() ?? '';

      setState(() {
        if (isCrossroads && responseText.contains('EVENT:')) {
          _awaitingChoice = true;
          _currentChoices.clear(); 
          
          List<String> lines = responseText.split('\n');
          String eventText = lines.firstWhere((l) => l.startsWith('EVENT:'), orElse: () => 'EVENT: A situation arises.').replaceAll('EVENT:', '').trim();
          
          for (String line in lines) {
            if (line.trim().startsWith('CHOICE:')) _currentChoices.add(line.replaceAll('CHOICE:', '').trim());
          }
          if (_currentChoices.isEmpty) _currentChoices = ["React calmly", "Take a big risk", "Do something completely unexpected"];
          
          _lifeHistory.add("Year $_age (CROSSROADS): $eventText");
        } else {
          _awaitingChoice = false;
          _lifeHistory.add("Year $_age: $responseText");
          
          if (responseText.contains('[Health -15]')) _health -= 15;
          if (responseText.contains('[Health +10]')) _health += 10;
          if (_health > 100) _health = 100; 
          
          // --- THE EXTRACTORS ---
          RegExp moneyRegex = RegExp(r'\[Money ([+-]\d+)\]');
          Match? moneyMatch = moneyRegex.firstMatch(responseText);
          if (moneyMatch != null) _money += int.parse(moneyMatch.group(1)!);

          RegExp jobRegex = RegExp(r'\[Set Job: ([^\]]+)\]');
          Match? jobMatch = jobRegex.firstMatch(responseText);
          if (jobMatch != null) _job = jobMatch.group(1)!.trim();

          RegExp salaryRegex = RegExp(r'\[Set Salary: (\d+)\]');
          Match? salaryMatch = salaryRegex.firstMatch(responseText);
          if (salaryMatch != null) _salary = int.parse(salaryMatch.group(1)!);
          
          RegExp buyRegex = RegExp(r'\[Buy: ([^,]+),\s*(\d+)\]');
          Match? buyMatch = buyRegex.firstMatch(responseText);
          if (buyMatch != null) {
            _inventory.add(buyMatch.group(1)!.trim());
            _money -= int.parse(buyMatch.group(2)!); 
          }

          // NEW: The Social Extractor (Using allMatches for multiple NPCs)
          RegExp relRegex = RegExp(r'\[Rel:\s*([^,]+),\s*([+-]\d+)\]');
          for (Match m in relRegex.allMatches(responseText)) {
            String person = m.group(1)!.trim();
            int change = int.parse(m.group(2)!);
            int currentScore = _relationships[person] ?? 50; // Strangers start at 50
            _relationships[person] = (currentScore + change).clamp(0, 100); // Keeps score between 0 and 100
          }

          if (_age > 50 && playerChoice == null) _health -= 2; 
          if (_health <= 0) _lifeHistory.add("Year $_age: Your health has reached zero. You have passed away.");
        }
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        if (e.toString().contains('quota') || e.toString().contains('429')) {
          _lifeHistory.add("System Pause: The AI needs to catch its breath. Please wait 15 seconds.");
        } else {
          _lifeHistory.add("System Error: The timeline fractured. Please try clicking again.");
        }
        if (playerChoice == null) _age--; 
      });
    } finally {
      setState(() { _isGenerating = false; });
    }
  }
  
Future<void> _openRiskMarket({String? wagerChoice}) async {
    if (_health <= 0 || _money <= 0 && wagerChoice == null) {
      setState(() {
        _lifeHistory.add("System: You don't have enough money to enter the Risk Market.");
      });
      _scrollToBottom();
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      String prompt = '';

      if (wagerChoice != null) {
        prompt = '''
        The player has \$$_money. They made this wager in the Risk Market: "$wagerChoice".
        Determine if they won or lost based on realistic football match probabilities. 
        Write a thrilling 2-sentence outcome describing the match climax (e.g., a late goal, a crucial red card, or unexpected player fouls).
        If they won the bet, include exactly "[Money +X]" (where X is their profit). 
        If they lost, include exactly "[Money -X]" (where X is the wager amount lost).
        ''';
      } else {
        prompt = '''
        The player has \$$_money and wants to place a sports bet. 
        Generate a high-stakes European football betting scenario. Mention specific tactical elements like team form, defensive setups, or a heated rivalry.
        CRITICAL RULE: YOU MUST PROVIDE EXACTLY 3 DISTINCT CHOICES.
        Format EXACTLY like this:
        EVENT: [2 sentence description of the upcoming match and the current odds]
        CHOICE: [Safe bet - e.g., Bet \$50 on the heavy favorites]
        CHOICE: [Risky tactical bet - e.g., Bet \$200 on high player fouls or the underdog]
        CHOICE: [Walk away without betting]
        ''';
      }

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      final responseText = response.text?.trim() ?? '';

      setState(() {
        if (wagerChoice == null && responseText.contains('EVENT:')) {
          _awaitingChoice = true;
          _currentChoices.clear(); 
          
          List<String> lines = responseText.split('\n');
          String eventText = lines.firstWhere((l) => l.startsWith('EVENT:'), orElse: () => 'EVENT: The bookies post the odds.').replaceAll('EVENT:', '').trim();
          
          for (String line in lines) {
            if (line.trim().startsWith('CHOICE:')) _currentChoices.add(line.replaceAll('CHOICE:', '').trim());
          }
          if (_currentChoices.isEmpty) _currentChoices = ["Bet \$50", "Bet \$200", "Walk away"];
          
          _lifeHistory.add("RISK MARKET: $eventText");
        } else {
          // Resolve the wager
          _awaitingChoice = false;
          _lifeHistory.add("MATCH RESULT: $responseText");
          
          RegExp moneyRegex = RegExp(r'\[Money ([+-]\d+)\]');
          Match? moneyMatch = moneyRegex.firstMatch(responseText);
          if (moneyMatch != null) _money += int.parse(moneyMatch.group(1)!);
        }
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _lifeHistory.add("System Error: The bookies closed the market. Try again later.");
      });
    } finally {
      setState(() { _isGenerating = false; });
    }
  }
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Life Simulator'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // THE STATS BAR
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('Age: $_age', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('Gender: $_gender', style: const TextStyle(fontSize: 16, color: Colors.grey)),
                    Row(
                      children: [
                        const Icon(Icons.attach_money, color: Colors.green),
                        Text('$_money', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 16),
                        const Icon(Icons.favorite, color: Colors.red),
                        const SizedBox(width: 8),
                        Text('$_health/100', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('$_job | \$$_salary / year', style: const TextStyle(fontSize: 16, color: Colors.teal, fontWeight: FontWeight.w600)),
                
                // The Asset Display 
                if (_inventory.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  Text('Assets: ${_inventory.join(', ')}', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                ],

                // NEW: The Social Ledger Display
                if (_relationships.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: _relationships.entries.map((e) {
                      // Green for good friends, Red for enemies, Orange for neutral
                      Color relColor = e.value >= 70 ? Colors.green : (e.value <= 30 ? Colors.red : Colors.orange);
                      return Chip(
                        label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
                        avatar: Icon(Icons.person, size: 14, color: relColor),
                        backgroundColor: relColor.withOpacity(0.1),
                        side: BorderSide.none,
                        padding: EdgeInsets.zero,
                      );
                    }).toList(),
                  ),
                ]
              ],
            ),
          ),
          
          // THE LIFE HISTORY (JOURNAL)
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _lifeHistory.length,
              itemBuilder: (context, index) {
                bool isCrossroads = _lifeHistory[index].contains('(CROSSROADS)');
                
                // Bulletproof scrubber for ALL tags, including the new Rel tag
                String displayString = _lifeHistory[index]
                    .replaceAll('[Health -15]', '')
                    .replaceAll('[Health +10]', '')
                    .replaceAll(RegExp(r'\[Money[^\]]*\]', caseSensitive: false), '')
                    .replaceAll(RegExp(r'\[Set Job:[^\]]*\]', caseSensitive: false), '')
                    .replaceAll(RegExp(r'\[Set Salary:[^\]]*\]', caseSensitive: false), '')
                    .replaceAll(RegExp(r'\[Buy:[^\]]*\]', caseSensitive: false), '')
                    .replaceAll(RegExp(r'\[Rel:[^\]]*\]', caseSensitive: false), '')
                    .trim();

                return Card(
                  color: isCrossroads ? Colors.teal.withOpacity(0.2) : null,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      displayString,
                      style: TextStyle(
                        fontSize: 16, 
                        fontWeight: isCrossroads ? FontWeight.bold : FontWeight.normal
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          
          // THE CONTROL PANEL
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              width: double.infinity,
              child: _isGenerating 
                  ? const Center(child: CircularProgressIndicator())
                  : _awaitingChoice 
                      ? Column(
                          children: _currentChoices.map((choice) {
                            // If we are in the risk market, route the choice back to the market logic
                            bool isRiskChoice = _lifeHistory.last.startsWith("RISK MARKET:");
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: ElevatedButton(
                                onPressed: () => isRiskChoice ? _openRiskMarket(wagerChoice: choice) : _ageUp(playerChoice: choice),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 50),
                                  backgroundColor: isRiskChoice ? Colors.orange.shade800 : Theme.of(context).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.all(16)
                                ),
                                child: Text(choice, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
                              ),
                            );
                          }).toList(),
                        )
                      : Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: _health <= 0 ? null : () => _ageUp(),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 60),
                                  backgroundColor: _health <= 0 ? Colors.grey : Theme.of(context).colorScheme.primary,
                                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                ),
                                child: Text(
                                  _health <= 0 ? 'GAME OVER' : 'AGE UP ( +1 Year )', 
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                                ),
                              ),
                            ),
                            if (_age >= 18) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 1,
                                child: ElevatedButton(
                                  onPressed: _health <= 0 || _money <= 0 ? null : () => _openRiskMarket(),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(0, 60),
                                    backgroundColor: Colors.orange.shade700,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Icon(Icons.sports_soccer, size: 30),
                                ),
                              ),
                            ]
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }
}