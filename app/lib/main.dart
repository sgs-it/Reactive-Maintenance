import 'package:flutter/material.dart';
import 'api.dart';
import 'workspace.dart';

void main() => runApp(const RmcsApp());

const ink = Color(0xff173029);
const green = Color(0xff176245);
const canvas = Color(0xfff4f7f4);
const line = Color(0xffe0e9e2);
const muted = Color(0xff52665d);

class RmcsApp extends StatefulWidget {
  const RmcsApp({super.key});
  @override
  State<RmcsApp> createState() => _RmcsAppState();
}

class _RmcsAppState extends State<RmcsApp> {
  final api = Api();
  final navigator = GlobalKey<NavigatorState>();
  Data? user;
  bool expired = false;

  @override
  void initState() {
    super.initState();
    api.onSessionExpired = () {
      if (!mounted) return;
      navigator.currentState?.popUntil((route) => route.isFirst);
      setState(() {
        expired = true;
        user = null;
      });
    };
  }

  @override
  void dispose() {
    api.onSessionExpired = null;
    api.dispose();
    super.dispose();
  }

  void signOut() {
    api.post('logout', {}).ignore();
    api.token = null;
    setState(() => user = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: green,
      surface: Colors.white,
    );
    return MaterialApp(
      navigatorKey: navigator,
      debugShowCheckedModeBanner: false,
      title: 'RMCS | Reactive Maintenance',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors.copyWith(
          primary: green,
          onSurface: ink,
          outlineVariant: line,
        ),
        scaffoldBackgroundColor: canvas,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xfff9fbf9),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: line),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
      home: user == null
          ? SignIn(
              api: api,
              sessionExpired: expired,
              onSignIn: (value) => setState(() {
                expired = false;
                user = value;
              }),
            )
          : Workspace(api: api, user: user!, onSignOut: signOut),
    );
  }
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.inverse = false});
  final bool inverse;
  @override
  Widget build(BuildContext context) => Container(
    width: inverse ? 162 : 104,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: inverse ? const Color(0xffc7e3da) : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Image.asset(
      'assets/italian-planters-logo-transparent.png',
      fit: BoxFit.contain,
      semanticLabel: 'Italian Planters LLC',
    ),
  );
}

class SignIn extends StatefulWidget {
  const SignIn({
    super.key,
    required this.api,
    required this.onSignIn,
    this.sessionExpired = false,
  });
  final Api api;
  final ValueChanged<Data> onSignIn;
  final bool sessionExpired;
  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  late final server = TextEditingController(
    text: widget.api.origin?.toString(),
  );
  bool loading = false;
  bool obscure = true;
  late String? error = widget.sessionExpired
      ? 'Your session has expired. Sign in again to continue.'
      : null;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    server.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (loading || !form.currentState!.validate()) return;
    if (Api.needsOrigin) widget.api.origin = companyOrigin(server.text);
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final user = await widget.api.login(email.text.trim(), password.text);
      if (mounted) widget.onSignIn(user);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, space) {
        final wide = space.maxWidth >= 850;
        return Row(
          children: [
            if (wide)
              Expanded(
                child: Container(
                  height: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xff102d22), Color(0xff24724e)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(52),
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: CustomPaint(painter: GardenLines()),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Brand(inverse: true),
                          const Spacer(),
                          const Text(
                            'Reactive\nMaintenance\nControl System',
                            style: TextStyle(
                              height: 1.03,
                              fontSize: 51,
                              letterSpacing: -2.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Field operations, work verification and client updates.',
                            style: TextStyle(
                              fontSize: 17,
                              color: Colors.white.withValues(alpha: .82),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(26),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 392),
                    child: Form(
                      key: form,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!wide) ...[
                              const Brand(),
                              const SizedBox(height: 34),
                            ],
                            const Text(
                              'Sign In to RMCS',
                              style: TextStyle(
                                fontSize: 33,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.9,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Use your staff or client account.',
                              style: TextStyle(fontSize: 15, color: muted),
                            ),
                            const SizedBox(height: 30),
                            if (Api.needsOrigin) ...[
                              TextFormField(
                                controller: server,
                                keyboardType: TextInputType.url,
                                decoration: const InputDecoration(
                                  labelText: 'Company Server URL',
                                  hintText: 'https://rmcs.example.com',
                                  prefixIcon: Icon(Icons.language),
                                ),
                                validator: (value) =>
                                    companyOrigin(value ?? '') == null
                                    ? 'Enter the HTTPS address provided by your company.'
                                    : null,
                              ),
                              const SizedBox(height: 13),
                            ],
                            TextFormField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.username],
                              decoration: const InputDecoration(
                                labelText: 'Email Address',
                                prefixIcon: Icon(Icons.alternate_email),
                              ),
                              validator: (value) =>
                                  (value?.contains('@') ?? false)
                                  ? null
                                  : 'Enter your email.',
                            ),
                            const SizedBox(height: 13),
                            TextFormField(
                              controller: password,
                              obscureText: obscure,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => signIn(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: obscure
                                      ? 'Show Password'
                                      : 'Hide Password',
                                  onPressed: () =>
                                      setState(() => obscure = !obscure),
                                  icon: Icon(
                                    obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) => value?.isNotEmpty == true
                                  ? null
                                  : 'Enter your password.',
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                error!,
                                style: const TextStyle(
                                  color: Color(0xffa52b24),
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            FilledButton(
                              onPressed: loading ? null : signIn,
                              child: Text(loading ? 'Signing in…' : 'Sign In'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class GardenLines extends CustomPainter {
  const GardenLines();
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 12; i++) {
      final offset = i * 15.0;
      final path = Path()
        ..moveTo(size.width * .19 + offset, size.height + 40)
        ..cubicTo(
          size.width * .47 + offset,
          size.height * .86,
          size.width * .92 - offset * .25,
          size.height * .57,
          size.width + 100,
          size.height * .12 + offset * 1.7,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xffd7eea8).withValues(alpha: .19)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(GardenLines oldDelegate) => false;
}
