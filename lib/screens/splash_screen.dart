import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
const SplashScreen({super.key});

@override
State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
with TickerProviderStateMixin {
late AnimationController _entranceController;
late AnimationController _pulseController;
late AnimationController _textController;
late AnimationController _shimmerController;
late AnimationController _floatController;

late Animation<double> _logoScale;
late Animation<double> _logoOpacity;

late Animation<double> _pulseScale;
late Animation<double> _pulseOpacity;

late Animation<double> _textSlide;
late Animation<double> _textOpacity;
late Animation<double> _bottomOpacity;

@override
void initState() {
super.initState();

// ============================================================
// LOGO ENTRANCE
// ============================================================

_entranceController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 1400),
);

_logoScale = Tween<double>(
begin: 0.0,
end: 1.0,
).animate(
CurvedAnimation(
parent: _entranceController,
curve: const Interval(
0.0,
0.70,
curve: Curves.elasticOut,
),
),
);

_logoOpacity = Tween<double>(
begin: 0.0,
end: 1.0,
).animate(
CurvedAnimation(
parent: _entranceController,
curve: const Interval(
0.0,
0.30,
curve: Curves.easeOut,
),
),
);

// ============================================================
// PULSE
// ============================================================

_pulseController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 2200),
)..repeat();

_pulseScale = Tween<double>(
begin: 1.0,
end: 2.0,
).animate(
CurvedAnimation(
parent: _pulseController,
curve: Curves.easeOut,
),
);

_pulseOpacity = Tween<double>(
begin: 0.22,
end: 0.0,
).animate(
CurvedAnimation(
parent: _pulseController,
curve: Curves.easeOut,
),
);

// ============================================================
// TEXT
// ============================================================

_textController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 900),
);

_textSlide = Tween<double>(
begin: 30.0,
end: 0.0,
).animate(
CurvedAnimation(
parent: _textController,
curve: Curves.easeOutCubic,
),
);

_textOpacity = Tween<double>(
begin: 0.0,
end: 1.0,
).animate(
CurvedAnimation(
parent: _textController,
curve: Curves.easeOut,
),
);

_bottomOpacity = Tween<double>(
begin: 0.0,
end: 1.0,
).animate(
CurvedAnimation(
parent: _textController,
curve: const Interval(
0.40,
1.0,
curve: Curves.easeOut,
),
),
);

// ============================================================
// LOGO SHIMMER
// ============================================================

_shimmerController = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 2000),
)..repeat();

// ============================================================
// FLOATING BACKGROUND
// ============================================================

_floatController = AnimationController(
vsync: this,
duration: const Duration(seconds: 5),
)..repeat(reverse: true);

// Start logo
_entranceController.forward();

// Start text after logo
Timer(const Duration(milliseconds: 800), () {
if (mounted) {
_textController.forward();
}
});

// Check Supabase session
_checkSession();
}

// ==============================================================
// SESSION CHECK
// ==============================================================

Future<void> _checkSession() async {
await Future.delayed(
const Duration(seconds: 3),
);

if (!mounted) return;

final session =
Supabase.instance.client.auth.currentSession;

if (session != null) {
try {
final userData = await Supabase.instance.client
    .from('create_account')
    .select('verification_status, role')
    .eq('id', session.user.id)
    .maybeSingle();

if (userData != null && userData['verification_status'] != 'BLOCKED') {
if (mounted) {
Provider.of<AuthProvider>(context, listen: false).setRole(userData['role']?.toString());
Navigator.of(context)
    .pushReplacementNamed('/home');
}

return;
} else {
await Supabase.instance.client.auth.signOut();
}
} catch (e) {
debugPrint(
'Auto-login session check error: $e',
);
}
}

if (mounted) {
Navigator.of(context).pushReplacement(
PageRouteBuilder(
pageBuilder: (
context,
animation,
secondaryAnimation,
) {
return const LoginScreen();
},
transitionsBuilder: (
context,
animation,
secondaryAnimation,
child,
) {
return FadeTransition(
opacity: animation,
child: child,
);
},
transitionDuration:
const Duration(milliseconds: 1000),
),
);
}
}

@override
void dispose() {
_entranceController.dispose();
_pulseController.dispose();
_textController.dispose();
_shimmerController.dispose();
_floatController.dispose();

super.dispose();
}

// ==============================================================
// BUILD
// ==============================================================

@override
Widget build(BuildContext context) {
const Color forestGreen = Color(0xFF2D6A4F);
const Color mossGreen = Color(0xFF40916C);
const Color deepGreen = Color(0xFF1B4332);
const Color gold = Color(0xFFFFB703);

return Scaffold(
backgroundColor: deepGreen,
body: AnnotatedRegion<SystemUiOverlayStyle>(
value: const SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Color(0xFF1B4332),
  systemNavigationBarIconBrightness: Brightness.light,
),
child: Container(
width: double.infinity,
height: double.infinity,

decoration: const BoxDecoration(
gradient: LinearGradient(
colors: [
Color(0xFF40916C),
Color(0xFF2D6A4F),
Color(0xFF1B4332),
],
stops: [
0.0,
0.50,
1.0,
],
begin: Alignment.topLeft,
end: Alignment.bottomRight,
),
),

child: Stack(
children: [
// ==================================================
// BACKGROUND GLOW 1
// ==================================================

AnimatedBuilder(
animation: _floatController,
builder: (context, child) {
final value =
math.sin(
_floatController.value *
math.pi,
);

return Positioned(
top: -120 + (value * 25),
right: -100,
child: Container(
width: 350,
height: 350,
decoration: BoxDecoration(
shape: BoxShape.circle,
gradient: RadialGradient(
colors: [
gold.withValues(
alpha: 0.13,
),
Colors.transparent,
],
),
),
),
);
},
),

// ==================================================
// BACKGROUND GLOW 2
// ==================================================

AnimatedBuilder(
animation: _floatController,
builder: (context, child) {
final value =
math.sin(
_floatController.value *
math.pi,
);

return Positioned(
bottom: -150 + (value * 20),
left: -100,
child: Container(
width: 380,
height: 380,
decoration: BoxDecoration(
shape: BoxShape.circle,
gradient: RadialGradient(
colors: [
mossGreen.withValues(
alpha: 0.18,
),
Colors.transparent,
],
),
),
),
);
},
),

// ==================================================
// FLOATING PAWS
// ==================================================

_buildFloatingPaw(
top: 110,
left: 35,
size: 25,
opacity: 0.08,
durationOffset: 0.0,
),

_buildFloatingPaw(
top: 190,
right: 30,
size: 18,
opacity: 0.07,
durationOffset: 0.3,
),

_buildFloatingPaw(
bottom: 170,
left: 45,
size: 20,
opacity: 0.06,
durationOffset: 0.6,
),

_buildFloatingPaw(
bottom: 250,
right: 35,
size: 27,
opacity: 0.06,
durationOffset: 0.2,
),

// ==================================================
// MAIN CONTENT
// ==================================================

Center(
child: Column(
mainAxisAlignment:
MainAxisAlignment.center,
children: [
// ==========================================
// LOGO
// ==========================================

AnimatedBuilder(
animation: Listenable.merge([
_entranceController,
_pulseController,
]),
builder: (context, child) {
return SizedBox(
width: 190,
height: 190,
child: Stack(
alignment: Alignment.center,
children: [
// Outer pulse
Transform.scale(
scale: _pulseScale.value,
child: Opacity(
opacity:
_pulseOpacity.value *
_logoOpacity.value,
child: Container(
width: 110,
height: 110,
decoration:
BoxDecoration(
shape:
BoxShape.circle,
border: Border.all(
color:
Colors.white,
width: 1.2,
),
),
),
),
),

// Gold pulse
Transform.scale(
scale: 1.0 +
((_pulseScale.value -
1.0) *
0.6),
child: Opacity(
opacity:
_pulseOpacity.value *
0.5 *
_logoOpacity.value,
child: Container(
width: 110,
height: 110,
decoration:
BoxDecoration(
shape:
BoxShape.circle,
border: Border.all(
color: gold,
width: 1,
),
),
),
),
),

// Logo
Opacity(
opacity:
_logoOpacity.value,
child: Transform.scale(
scale:
_logoScale.value,
child: child,
),
),
],
),
);
},

child: _buildLogo(
gold,
forestGreen,
mossGreen,
),
),

const SizedBox(height: 35),

// ==========================================
// TEXT
// ==========================================

AnimatedBuilder(
animation: _textController,
builder: (context, child) {
return Transform.translate(
offset: Offset(
0,
_textSlide.value,
),
child: Opacity(
opacity:
_textOpacity.value,
child: child,
),
);
},
child: Column(
children: [
// APP NAME
RichText(
text: const TextSpan(
style: TextStyle(
fontSize: 40,
fontWeight:
FontWeight.w800,
fontFamily:
'Poppins',
letterSpacing: -0.7,
),
children: [
TextSpan(
text: 'Breeder',
style: TextStyle(
color:
Colors.white,
),
),
TextSpan(
text: ' Finder',
style: TextStyle(
color: gold,
),
),
],
),
),

const SizedBox(height: 12),

// TAGLINE
Text(
'Find. Connect. Trade.',
style: TextStyle(
color: Colors.white
    .withValues(
alpha: 0.80,
),
fontSize: 14,
fontWeight:
FontWeight.w400,
letterSpacing: 1.8,
fontFamily: 'Poppins',
),
),

const SizedBox(height: 20),

// TRUST BADGE
Container(
padding:
const EdgeInsets
    .symmetric(
horizontal: 18,
vertical: 9,
),
decoration:
BoxDecoration(
color: Colors.white
    .withValues(
alpha: 0.08,
),
borderRadius:
BorderRadius
    .circular(40),
border: Border.all(
color: Colors.white
    .withValues(
alpha: 0.16,
),
width: 0.8,
),
),
child: Row(
mainAxisSize:
MainAxisSize.min,
children: [
_glowDot(gold),

const SizedBox(
width: 8),

const Text(
'Trusted Breeders',
style: TextStyle(
color:
Colors.white,
fontSize: 11,
fontWeight:
FontWeight.w500,
letterSpacing: 1.0,
fontFamily:
'Poppins',
),
),

const SizedBox(
width: 7),

const Text(
'•',
style: TextStyle(
color: gold,
),
),

const SizedBox(
width: 7),

const Text(
'Happy Pets',
style: TextStyle(
color:
Colors.white,
fontSize: 11,
fontWeight:
FontWeight.w500,
letterSpacing: 1.0,
fontFamily:
'Poppins',
),
),

const SizedBox(
width: 8),

_glowDot(gold),
],
),
),
],
),
),
],
),
),

// ==================================================
// LOADING
// ==================================================

Positioned(
bottom: 55,
left: 0,
right: 0,
child: AnimatedBuilder(
animation: _textController,
builder: (context, child) {
return Opacity(
opacity:
_bottomOpacity.value,
child: child,
);
},
child: Column(
children: [
const _DotLoader(
color: gold,
),

const SizedBox(
height: 15,
),

Row(
mainAxisAlignment:
MainAxisAlignment.center,
children: [
Icon(
Icons
    .lock_outline_rounded,
size: 12,
color: Colors.white
    .withValues(
alpha: 0.35,
),
),

const SizedBox(
width: 6,
),

Text(
'SECURE CONNECTION',
style: TextStyle(
color: Colors.white
    .withValues(
alpha: 0.35,
),
fontSize: 9,
fontWeight:
FontWeight.w600,
letterSpacing: 2.2,
fontFamily:
'Poppins',
),
),
],
),
],
),
),
),

// ==================================================
// SMALL BRAND TEXT
// ==================================================

Positioned(
bottom: 15,
left: 0,
right: 0,
child: Text(
'BREEDER FINDER',
textAlign: TextAlign.center,
style: TextStyle(
color: Colors.white.withValues(
alpha: 0.15,
),
fontSize: 8,
fontWeight: FontWeight.w500,
letterSpacing: 2.5,
fontFamily: 'Poppins',
),
),
),
],
),
),
),
);
}

// ==============================================================
// LOGO
// ==============================================================

Widget _buildLogo(
Color gold,
Color forestGreen,
Color mossGreen,
) {
return AnimatedBuilder(
animation: _shimmerController,
builder: (context, child) {
final angle =
_shimmerController.value *
math.pi *
2;

return Container(
width: 110,
height: 110,
decoration: BoxDecoration(
shape: BoxShape.circle,

gradient: RadialGradient(
colors: const [
Colors.white,
Color(0xFFF0F0F0),
],
center: Alignment(
math.cos(angle) * 0.3,
math.sin(angle) * 0.3,
),
),

boxShadow: [
BoxShadow(
color: Colors.black.withValues(
alpha: 0.18,
),
blurRadius: 30,
spreadRadius: 3,
offset: const Offset(
0,
12,
),
),

BoxShadow(
color: gold.withValues(
alpha: 0.28,
),
blurRadius: 25,
),
],
),

child: Stack(
alignment: Alignment.center,
children: [
Container(
width: 90,
height: 90,
decoration: BoxDecoration(
shape: BoxShape.circle,
border: Border.all(
color: mossGreen.withValues(
alpha: 0.10,
),
width: 1,
),
),
),

Icon(
Icons.pets_rounded,
size: 54,
color: forestGreen,
),

// Location icon
Positioned(
top: 13,
right: 17,
child: Container(
padding:
const EdgeInsets.all(4),
decoration: BoxDecoration(
color: gold,
shape: BoxShape.circle,
boxShadow: [
BoxShadow(
color: gold.withValues(
alpha: 0.55,
),
blurRadius: 9,
),
],
),
child: const Icon(
Icons.location_on_rounded,
color: Colors.white,
size: 15,
),
),
),
],
),
);
},
);
}

// ==============================================================
// FLOATING PAW
// ==============================================================

Widget _buildFloatingPaw({
double? top,
double? bottom,
double? left,
double? right,
required double size,
required double opacity,
required double durationOffset,
}) {
return AnimatedBuilder(
animation: _floatController,
builder: (context, child) {
final value = math.sin(
((_floatController.value +
durationOffset) %
1.0) *
math.pi *
2,
);

return Positioned(
top: top,
bottom: bottom,
left: left,
right: right,
child: Transform.translate(
offset: Offset(
0,
value * 10,
),
child: Transform.rotate(
angle: value * 0.08,
child: Icon(
Icons.pets_rounded,
size: size,
color: Colors.white.withValues(
alpha: opacity,
),
),
),
),
);
},
);
}

// ==============================================================
// GLOW DOT
// ==============================================================

Widget _glowDot(Color color) {
return Container(
width: 6,
height: 6,
decoration: BoxDecoration(
color: color,
shape: BoxShape.circle,
boxShadow: [
BoxShadow(
color: color.withValues(
alpha: 0.65,
),
blurRadius: 7,
spreadRadius: 1,
),
],
),
);
}
}

// ==================================================================
// DOT LOADER
// ==================================================================

class _DotLoader extends StatefulWidget {
final Color color;

const _DotLoader({
required this.color,
});

@override
State<_DotLoader> createState() =>
_DotLoaderState();
}

class _DotLoaderState extends State<_DotLoader>
with SingleTickerProviderStateMixin {
late AnimationController _controller;

@override
void initState() {
super.initState();

_controller = AnimationController(
vsync: this,
duration:
const Duration(milliseconds: 1200),
)..repeat();
}

@override
void dispose() {
_controller.dispose();
super.dispose();
}

@override
Widget build(BuildContext context) {
return AnimatedBuilder(
animation: _controller,
builder: (context, child) {
return Row(
mainAxisSize: MainAxisSize.min,
children: List.generate(
3,
(index) {
final delay = index / 3.0;

final value =
(_controller.value -
delay) %
1.0;

final scale =
0.65 +
(0.35 *
math.sin(
value * math.pi,
));

return Padding(
padding:
const EdgeInsets.symmetric(
horizontal: 4,
),
child: Transform.scale(
scale: scale,
child: Container(
width: 7,
height: 7,
decoration:
BoxDecoration(
color: widget.color
    .withValues(
alpha:
0.45 +
(0.55 * scale),
),
shape:
BoxShape.circle,
boxShadow: [
BoxShadow(
color: widget.color
    .withValues(
alpha: 0.25,
),
blurRadius: 7,
),
],
),
),
),
);
},
),
);
},
);
}
}
