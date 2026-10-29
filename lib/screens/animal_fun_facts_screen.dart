import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/breeder_provider.dart';
import '../models/breeder.dart';
import '../utils/system_ui_utils.dart';

class AnimalFact {
  final String id;
  final String title;
  final String fact;
  final String description;
  final String category;
  final String emoji;
  final IconData icon;
  final Color accentColor;
  bool isLiked;

  AnimalFact({
    required this.id,
    required this.title,
    required this.fact,
    required this.description,
    required this.category,
    required this.emoji,
    required this.icon,
    required this.accentColor,
    this.isLiked = false,
  });
}

class AnimalFunFactsScreen extends StatefulWidget {
  final String? initialCategory;

  const AnimalFunFactsScreen({
    super.key,
    this.initialCategory,
  });

  @override
  State<AnimalFunFactsScreen> createState() => _AnimalFunFactsScreenState();
}

class _AnimalFunFactsScreenState extends State<AnimalFunFactsScreen> {
  static const themeGreen = Color(0xFF2D6A4F);

  late String _selectedCategory;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<AnimalFact> _facts = [];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'All';
    _initFacts();
  }

  void _initFacts() {
    // Base curated facts
    _facts = [
      AnimalFact(
        id: '1',
        title: 'Unique Nose Prints',
        fact: 'A dog\'s nose print is as unique as a human fingerprint!',
        description: 'Just like humans have distinct fingerprints, every dog has a completely unique nose pad pattern of ridges and creases that can be used for identification.',
        category: 'Dog',
        emoji: '🐶',
        icon: Icons.pets_rounded,
        accentColor: const Color(0xFFE07A5F),
      ),
      AnimalFact(
        id: '2',
        title: 'Dreaming Pups',
        fact: 'Dogs have dreams just like humans when they enter REM sleep.',
        description: 'Small dogs tend to dream more frequently than large dogs. Twitching paws, tail wiggles, and soft yips during sleep mean your pup is actively dreaming!',
        category: 'Dog',
        emoji: '🐕',
        icon: Icons.bedtime_rounded,
        accentColor: const Color(0xFF3D405B),
      ),
      AnimalFact(
        id: '3',
        title: 'Super Whiskers',
        fact: 'Cat whiskers are so sensitive they detect tiny air current changes!',
        description: 'Whiskers are embedded deep in the cat\'s body with rich nervous tissue, helping them measure distance and navigate dark rooms effortlessly.',
        category: 'Cat',
        emoji: '🐱',
        icon: Icons.visibility_rounded,
        accentColor: const Color(0xFF81B29A),
      ),
      AnimalFact(
        id: '4',
        title: 'Night Vision Masters',
        fact: 'Cats need only 1/6th of the light humans need to see clearly.',
        description: 'A reflective tissue behind their retina bounces light back through retinal cells, giving feline eyes extraordinary low-light performance.',
        category: 'Cat',
        emoji: '🐈',
        icon: Icons.nightlight_round,
        accentColor: const Color(0xFFF2CC8F),
      ),
      AnimalFact(
        id: '5',
        title: 'Vocal Superpowers',
        fact: 'Parrots use a special chest organ called a syrinx to imitate speech.',
        description: 'Unlike humans who use vocal cords in the throat, birds produce pitch and sounds deep in their chest with two separate air passages.',
        category: 'Birds',
        emoji: '🦜',
        icon: Icons.record_voice_over_rounded,
        accentColor: const Color(0xFF118AB2),
      ),
      AnimalFact(
        id: '6',
        title: 'Internal Magnetic GPS',
        fact: 'Pigeons navigate across hundreds of miles using Earth\'s magnetic fields!',
        description: 'Pigeons contain tiny microscopic magnetic iron particles in their upper beaks that function like a built-in compass for flawless navigation.',
        category: 'Birds',
        emoji: '🕊️',
        icon: Icons.explore_rounded,
        accentColor: const Color(0xFF06D6A0),
      ),
      AnimalFact(
        id: '7',
        title: '360-Degree Vision',
        fact: 'Rabbits can see nearly 360 degrees around without turning their head.',
        description: 'Their high-set eyes on the side of their skull allow them to detect overhead and rear predators while grazing quietly.',
        category: 'Rabbit',
        emoji: '🐰',
        icon: Icons.remove_red_eye_rounded,
        accentColor: const Color(0xFFEF476F),
      ),
      AnimalFact(
        id: '8',
        title: 'The Joyful Binky',
        fact: 'When rabbits are overjoyed, they jump and twist in the air called a Binky!',
        description: 'A Binky involves flicking their ears, spinning mid-air, and kicking out hind legs—it\'s the ultimate expression of pure rabbit happiness.',
        category: 'Rabbit',
        emoji: '🐇',
        icon: Icons.auto_awesome_rounded,
        accentColor: const Color(0xFFFFD166),
      ),
      AnimalFact(
        id: '9',
        title: 'Standing Sleepers',
        fact: 'Horses can sleep standing up using a stay apparatus system in their leg muscles.',
        description: 'Special tendons and ligaments lock their leg joints in position so they can nap comfortably standing without risking a fall.',
        category: 'Horse',
        emoji: '🐴',
        icon: Icons.directions_run_rounded,
        accentColor: const Color(0xFF9C6644),
      ),
      AnimalFact(
        id: '10',
        title: 'Expressive Dual Ears',
        fact: 'A horse\'s ears can swivel 180 degrees and point in two directions at once!',
        description: 'Powered by 16 individual ear muscles, horses can pinpoint different sounds around them simultaneously without moving their head.',
        category: 'Horse',
        emoji: '🐎',
        icon: Icons.hearing_rounded,
        accentColor: const Color(0xFF7F5539),
      ),
      AnimalFact(
        id: '11',
        title: 'Independent Eyeballs',
        fact: 'Chameleons can swivel their eyes in two completely different directions at once!',
        description: 'Each eye operates independently with a 360-degree arc, allowing them to track prey and watch for predators at the exact same time.',
        category: 'Reptiles',
        emoji: '🦎',
        icon: Icons.center_focus_strong_rounded,
        accentColor: const Color(0xFF52B788),
      ),
      AnimalFact(
        id: '12',
        title: 'Goldfish Memory Myth',
        fact: 'Goldfish do not have a 3-second memory—their memory lasts up to 5 months!',
        description: 'Scientific studies prove goldfish can memorize feeding schedules, recognize their human caretakers, and learn complex navigation mazes.',
        category: 'Koi Fish',
        emoji: '🐠',
        icon: Icons.psychology_rounded,
        accentColor: const Color(0xFFFF9F1C),
      ),
      AnimalFact(
        id: '13',
        title: 'Smart & Clean Pigs',
        fact: 'Pigs are exceptionally intelligent and cleaner than most domestic animals!',
        description: 'Pigs rank among the smartest animals on earth (outsmarting dogs in certain cognitive tests) and naturally keep their living areas spotless.',
        category: 'Pig',
        emoji: '🐷',
        icon: Icons.pets_rounded,
        accentColor: const Color(0xFFE56B6F),
      ),
      AnimalFact(
        id: '14',
        title: 'Rectangular Goat Pupils',
        fact: 'Goats have rectangular pupils providing 320-degree panoramic vision!',
        description: 'This unique pupil shape lets goats see almost all around their bodies without turning their heads, helping them spot predators on steep terrain.',
        category: 'Goat',
        emoji: '🐐',
        icon: Icons.panorama_fish_eye_rounded,
        accentColor: const Color(0xFFB08968),
      ),
      AnimalFact(
        id: '15',
        title: 'Bovine Best Friends',
        fact: 'Cows form close lifelong friendships and experience stress when separated!',
        description: 'Studies show that cattle have best friends, share mutual grooming habits, and show measurable anxiety when separated from their bonded companions.',
        category: 'Cow',
        emoji: '🐄',
        icon: Icons.favorite_rounded,
        accentColor: const Color(0xFF6C757D),
      ),
      AnimalFact(
        id: '16',
        title: 'Social Sheep Memory',
        fact: 'Sheep can recognize and remember up to 50 individual human and sheep faces for years!',
        description: 'Sheep possess sophisticated facial recognition abilities, remembering friends and past experiences for long periods.',
        category: 'Sheep',
        emoji: '🐑',
        icon: Icons.face_rounded,
        accentColor: const Color(0xFFADB5BD),
      ),
      AnimalFact(
        id: '17',
        title: 'Clever Chickens',
        fact: 'Chickens can distinguish over 100 different human and animal faces.',
        description: 'They possess full color vision, experience REM sleep dreaming, and communicate with each other using over 30 distinct vocalizations.',
        category: 'Chicken',
        emoji: '🐔',
        icon: Icons.mic_rounded,
        accentColor: const Color(0xFFD4A373),
      ),
      AnimalFact(
        id: '18',
        title: 'Water Buffalo Mud Armor',
        fact: 'Carabao (Water Buffalo) wallow in mud to create natural sunscreen and cooling armor!',
        description: 'Because they have few sweat glands, mud caking protects their sensitive skin from harsh tropical sunlight and biting insects.',
        category: 'Carabao',
        emoji: '🐃',
        icon: Icons.water_drop_rounded,
        accentColor: const Color(0xFF495057),
      ),
      AnimalFact(
        id: '19',
        title: 'Betta Fish Breathing',
        fact: 'Betta fish possess a labyrinth organ that allows them to breathe oxygen directly from the air!',
        description: 'This evolutionary adaptation lets bettas survive in low-oxygen shallow waters and puddles in their natural habitats.',
        category: 'Betta Fish',
        emoji: '🐟',
        icon: Icons.air_rounded,
        accentColor: const Color(0xFF4361EE),
      ),
    ];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _getAllCategories(List<Breeder> breeders) {
    final Set<String> cats = {'All'};
    // Add categories from facts
    for (var f in _facts) {
      cats.add(f.category);
    }
    // Add categories from breeders and traders
    for (var b in breeders) {
      if (b.category.trim().isNotEmpty) {
        cats.add(b.category.trim());
      }
    }
    return cats.toList();
  }

  List<AnimalFact> _getFilteredFacts(List<Breeder> breeders) {
    // Ensure any breeder/trader category without explicit facts gets a dynamic fun fact generated
    final existingCategories = _facts.map((f) => f.category.toLowerCase()).toSet();
    for (var b in breeders) {
      final cat = b.category.trim();
      if (cat.isNotEmpty && !existingCategories.contains(cat.toLowerCase())) {
        existingCategories.add(cat.toLowerCase());
        _facts.add(AnimalFact(
          id: 'dynamic_${cat.hashCode}',
          title: '$cat Amazing Facts',
          fact: '$cat listings provide wonderful companionship and agricultural value!',
          description: 'Every $cat has unique care needs, personality traits, and wonderful benefits when raised responsibly by trusted breeders and traders.',
          category: cat,
          emoji: '🐾',
          icon: Icons.pets_rounded,
          accentColor: const Color(0xFF2D6A4F),
        ));
      }
    }

    return _facts.where((f) {
      final matchesCategory = _selectedCategory == 'All' || f.category.toLowerCase() == _selectedCategory.toLowerCase();
      final matchesQuery = _searchQuery.isEmpty ||
          f.title.toLowerCase().contains(_searchQuery) ||
          f.fact.toLowerCase().contains(_searchQuery) ||
          f.description.toLowerCase().contains(_searchQuery) ||
          f.category.toLowerCase().contains(_searchQuery);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  void _showRandomFactDialog() {
    final random = Random();
    final randomFact = _facts[random.nextInt(_facts.length)];
    _showFactDetailSheet(randomFact, isRandom: true);
  }

  void _showFactDetailSheet(AnimalFact fact, {bool isRandom = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF14241B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (isRandom)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: themeGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.casino_rounded, size: 16, color: themeGreen),
                      SizedBox(width: 6),
                      Text(
                        'Random Surprise Fact!',
                        style: TextStyle(
                          color: themeGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: fact.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      fact.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fact.category.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: fact.accentColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fact.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF6F8F6),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: fact.accentColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.format_quote_rounded,
                      color: fact.accentColor,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        fact.fact,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Did You Know?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                fact.description,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          fact.isLiked = !fact.isLiked;
                        });
                        setSheetState(() {});
                      },
                      icon: Icon(
                        fact.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: fact.isLiked ? Colors.redAccent : (isDark ? Colors.white : Colors.grey[800]),
                      ),
                      label: Text(
                        fact.isLiked ? 'Liked' : 'Like Fact',
                        style: TextStyle(
                          color: fact.isLiked ? Colors.redAccent : (isDark ? Colors.white : Colors.grey[800]),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.1),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: '${fact.title}: ${fact.fact} 🐾 Learn more on BreederFinder!'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Fact copied to clipboard!'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.share_rounded, color: Colors.white),
                      label: const Text(
                        'Share Fact',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeGreen,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final breederProvider = Provider.of<BreederProvider>(context);
    final breeders = breederProvider.breeders;
    final categories = _getAllCategories(breeders);
    final displayList = _getFilteredFacts(breeders);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1A14) : const Color(0xFFF6F8F6),
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Blurred Glassmorphic Header (SliverAppBar)
          SliverAppBar(
            pinned: true,
            floating: false,
            elevation: 0,
            backgroundColor: isDark ? const Color(0xFF0F1A14).withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.75),
            systemOverlayStyle: SystemUiUtils.getOverlayStyle(
              isDark: isDark,
              navBarColor: isDark ? const Color(0xFF0F1A14) : const Color(0xFFF6F8F6),
            ),
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : const Color(0xFF1A1A2E), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: themeGreen.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lightbulb_rounded, color: themeGreen, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'Animal Fun Facts',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: themeGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.casino_rounded, color: themeGreen, size: 20),
                ),
                tooltip: 'Surprise Me!',
                onPressed: _showRandomFactDialog,
              ),
              const SizedBox(width: 8),
            ],
          ),

          // Search Box Sliver
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A2B22) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.15),
                  ),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.toLowerCase().trim()),
                  style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
                  decoration: InputDecoration(
                    hintText: 'Search fun facts & breeder animals...',
                    hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400], fontSize: 13.5),
                    prefixIcon: const Icon(Icons.search_rounded, color: themeGreen, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ),

          // Categories horizontal list Sliver
          SliverToBoxAdapter(
            child: SizedBox(
              height: 42,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final isSelected = _selectedCategory == cat;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? themeGreen : (isDark ? const Color(0xFF1A2B22) : Colors.white),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? themeGreen : (isDark ? Colors.white10 : Colors.grey.shade300),
                        ),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? Colors.white : (isDark ? Colors.grey[300] : Colors.grey[700]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 14)),

          // Main content list
          displayList.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sentiment_dissatisfied_rounded, size: 56, color: isDark ? Colors.grey[600] : Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'No animal facts found',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Try searching for another word or category',
                          style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[500] : Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == 0) {
                          // Hero Featured Banner
                          final heroFact = displayList.first;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2D6A4F), Color(0xFF1B4332)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: themeGreen.withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        '🌟 FEATURED TRIVIA',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      heroFact.emoji,
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  heroFact.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  heroFact.fact,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                GestureDetector(
                                  onTap: () => _showFactDetailSheet(heroFact),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Read full story',
                                        style: TextStyle(
                                          color: Colors.amber[300],
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.arrow_forward_rounded, color: Colors.amber[300], size: 16),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final fact = displayList[index - 1];
                        return GestureDetector(
                          onTap: () => _showFactDetailSheet(fact),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1A2B22) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.12),
                              ),
                              boxShadow: isDark
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.03),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: fact.accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    fact.emoji,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: fact.accentColor.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              fact.category,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                color: fact.accentColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        fact.title,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        fact.fact,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: displayList.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
