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
    _lifeHistory.clear();
    _lifeHistory.add("Year 0: You were born $_gender. You cry loudly, letting the world know you have arrived.");
  }

  Future<void> _ageUp({String? playerChoice}) async {
    if (_health <= 0) return;

    setState(() {
      _isGenerating = true;
      if (playerChoice == null) {
        _age++;
      }
    });

    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      
      bool isCrossroads = _age % 5 == 0 && _age > 0 && playerChoice == null;
      String prompt = '';

      if (playerChoice != null) {
        prompt = '''
        The player is $_age years old, $_gender. Health: $_health/100.
        They were faced with a choice and chose: "$playerChoice".
        Write a 2-sentence outcome of this choice. 
        If it was a reckless or dangerous choice, include the exact text "[Health -15]" at the end.
        If it was a very healthy or healing choice, include the exact text "[Health +10]" at the end.
        ''';
      } else if (isCrossroads) {
        prompt = '''
        The player just turned $_age. They are $_gender. Health: $_health/100.
        Generate a major life dilemma appropriate for their age. 
        CRITICAL RULE: YOU MUST PROVIDE EXACTLY 3 DISTINCT CHOICES. DO NOT PROVIDE 2. 
        Make Choice 1 safe, Choice 2 risky, and Choice 3 weird or unexpected.
        Format your response EXACTLY like this, with no extra text:
        EVENT: [2 sentence description of the dilemma]
        CHOICE: [First choice]
        CHOICE: [Second choice]
        CHOICE: [Third choice]
        ''';
      } else {
        prompt = '''
        The player just turned $_age. They are $_gender. Health: $_health/100.
        Write a single, 1-sentence life event that happens this year. Do not give choices.
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
          
          String eventText = lines.firstWhere(
            (l) => l.startsWith('EVENT:'), 
            orElse: () => 'EVENT: A sudden and mysterious situation arises.'
          ).replaceAll('EVENT:', '').trim();
          
          for (String line in lines) {
            if (line.trim().startsWith('CHOICE:')) {
              _currentChoices.add(line.replaceAll('CHOICE:', '').trim());
            }
          }
          
          if (_currentChoices.isEmpty) {
            _currentChoices = ["React calmly", "Take a big risk", "Do something completely unexpected"];
          }
          
          _lifeHistory.add("Year $_age (CROSSROADS): $eventText");
        } else {
          _awaitingChoice = false;
          _lifeHistory.add("Year $_age: $responseText");
          
          if (responseText.contains('[Health -15]')) _health -= 15;
          if (responseText.contains('[Health +10]')) _health += 10;
          if (_health > 100) _health = 100; 
          
          if (_age > 50 && playerChoice == null) _health -= 2; 
          
          if (_health <= 0) {
            _lifeHistory.add("Year $_age: Your health has reached zero. You have passed away.");
          }
        }
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        String errorString = e.toString();
        if (errorString.contains('quota') || errorString.contains('429')) {
          _lifeHistory.add("System Pause: The AI needs to catch its breath. Please wait 15 seconds before aging up again.");
        } else {
          _lifeHistory.add("System Error: The timeline fractured. Please try clicking again.");
        }
        if (playerChoice == null) _age--; 
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('Age: $_age', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Gender: $_gender', style: const TextStyle(fontSize: 16, color: Colors.grey)),
                Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.red),
                    const SizedBox(width: 8),
                    Text('$_health/100', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
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
                return Card(
                  color: isCrossroads ? Colors.teal.withOpacity(0.2) : null,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _lifeHistory[index].replaceAll('[Health -15]', '').replaceAll('[Health +10]', ''),
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
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: ElevatedButton(
                                onPressed: () => _ageUp(playerChoice: choice),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 50),
                                  padding: const EdgeInsets.all(16)
                                ),
                                child: Text(choice, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
                              ),
                            );
                          }).toList(),
                        )
                      : ElevatedButton(
                          onPressed: _health <= 0 ? null : () => _ageUp(),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 60),
                            backgroundColor: _health <= 0 ? Colors.grey : Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          ),
                          child: Text(
                            _health <= 0 ? 'GAME OVER' : 'AGE UP ( +1 Year )', 
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}