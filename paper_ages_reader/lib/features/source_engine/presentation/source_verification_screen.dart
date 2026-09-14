import 'package:flutter/material.dart';

import '../open_reading/book_sources/protocol/book_source_protocol.dart';
import '../open_reading/book_sources/source_engine/source_interaction_coordinator.dart';
import '../open_reading/book_sources/source_engine/source_interactive_browser.dart';
import '../open_reading/book_sources/source_engine/source_script_contract.dart';

class SourceVerificationScreen extends StatefulWidget {
  const SourceVerificationScreen({super.key, required this.ticket});

  final SourceInteractionTicket ticket;

  @override
  State<SourceVerificationScreen> createState() =>
      _SourceVerificationScreenState();
}

class _SourceVerificationScreenState extends State<SourceVerificationScreen> {
  final _code = TextEditingController();
  bool _working = false;
  bool _completed = false;
  String? _error;

  SourceScriptInteractionRequest get _request => widget.ticket.request;

  @override
  void initState() {
    super.initState();
    if (_request.kind != SourceScriptInteractionKind.verificationCode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openBrowser());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _openBrowser() async {
    if (_working || _completed) return;
    setState(() => _working = true);
    try {
      final url = Uri.tryParse(_request.url);
      if (url == null || !url.hasAuthority) {
        throw const BookSourceProtocolException('验证地址无效');
      }
      final result = await const SourceInteractiveBrowser().open(
        url: url,
        headers: _request.headers,
        html: _request.html,
      );
      _complete(
        SourceScriptInteractionResult(
          body: result.body,
          finalUrl: result.finalUri.toString(),
          cookieHeader: result.cookieHeader,
        ),
      );
    } on SourceInteractiveBrowserCancelled {
      _cancel();
    } catch (error) {
      if (!mounted || _completed) return;
      setState(() {
        _working = false;
        _error = error is BookSourceProtocolException
            ? error.message
            : error.toString();
      });
    }
  }

  void _submitCode() {
    final value = _code.text.trim();
    if (value.isNotEmpty) {
      _complete(SourceScriptInteractionResult(value: value));
    }
  }

  void _complete(SourceScriptInteractionResult result) {
    if (_completed) return;
    _completed = true;
    SourceInteractionCoordinator.instance.complete(
      widget.ticket.requestId,
      result,
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _cancel() =>
      _complete(const SourceScriptInteractionResult(cancelled: true));

  @override
  Widget build(BuildContext context) {
    final isCode =
        _request.kind == SourceScriptInteractionKind.verificationCode;
    return PopScope(
      canPop: _completed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_request.title.trim().isEmpty ? '书源验证' : _request.title),
          leading: IconButton(
            onPressed: _cancel,
            icon: const Icon(Icons.close),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(isCode ? '请输入图片或网页中的验证码。' : '请在浏览器内完成验证，然后点击“完成验证”。'),
            if (isCode) ...[
              const SizedBox(height: 18),
              if (_request.imageBytes != null)
                Image.memory(_request.imageBytes!, height: 150),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                autofocus: true,
                onSubmitted: (_) => _submitCode(),
                decoration: const InputDecoration(
                  labelText: '验证码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(onPressed: _submitCode, child: const Text('提交')),
            ] else ...[
              const SizedBox(height: 18),
              if (_working) const LinearProgressIndicator(),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                FilledButton(onPressed: _openBrowser, child: const Text('重试')),
              ],
            ],
            const SizedBox(height: 12),
            TextButton(onPressed: _cancel, child: const Text('取消')),
          ],
        ),
      ),
    );
  }
}
