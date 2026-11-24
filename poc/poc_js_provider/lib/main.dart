import 'package:flutter/material.dart';
import 'package:qjs/qjs.dart';

void main() {
  runApp(const PocJsProviderApp());
}

class PocJsProviderApp extends StatelessWidget {
  const PocJsProviderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureRead PoC-2: QuickJS BookProvider',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const _QuickJsProbePage(),
    );
  }
}

class _QuickJsProbePage extends StatefulWidget {
  const _QuickJsProbePage();

  @override
  State<_QuickJsProbePage> createState() => _QuickJsProbePageState();
}

class _QuickJsProbePageState extends State<_QuickJsProbePage> {
  String _status = 'Ready to probe QuickJS (package:qjs)';

  void _runQuickProbe() {
    final rt = JSRuntime.create(const JSRuntimeConfig.hardened());
    try {
      rt.setDeadline(const Duration(milliseconds: 500));
      final val = rt.evaluateJavascript(
        '(() => { const msg = "QuickJS-NG OK: " + (21 * 2); return msg; })()',
      );
      setState(() {
        _status = val.asDartString;
      });
    } finally {
      rt.release();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PureRead PoC-2: JS Provider')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _runQuickProbe,
                child: const Text('Run QuickJS Probe'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
