import 'package:flutter_test/flutter_test.dart';
import 'package:privatelm/services/model_url.dart';

void main() {
  group('parseModelUrl', () {
    test('accepts a Hugging Face resolve link', () {
      final r = parseModelUrl(
          'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf');
      expect(r.error, isNull);
      expect(r.value!.filename, 'Qwen2.5-3B-Instruct-Q4_K_M.gguf');
      expect(r.value!.isHuggingFace, isTrue);
    });

    test('rewrites a /blob/ page link to /resolve/ and drops the fragment', () {
      final r = parseModelUrl(
          'https://huggingface.co/a/b/blob/main/m.safetensors#x');
      expect(r.value!.url, 'https://huggingface.co/a/b/resolve/main/m.safetensors');
    });

    test('keeps query strings such as ?download=true', () {
      final r = parseModelUrl(
          'https://huggingface.co/a/b/resolve/main/m.gguf?download=true');
      expect(r.value!.url, endsWith('m.gguf?download=true'));
      expect(r.value!.filename, 'm.gguf');
    });

    test('upgrades http to https for Hugging Face', () {
      final r = parseModelUrl('http://huggingface.co/a/b/resolve/main/m.gguf');
      expect(r.value!.url, startsWith('https://'));
    });

    test('rejects a bare repository link with guidance', () {
      final r = parseModelUrl('https://huggingface.co/Umranz/SD1.5-Uncensored-Photoreal');
      expect(r.value, isNull);
      expect(r.error, contains('repository link'));
    });

    test('rejects a tree (folder) link', () {
      final r = parseModelUrl('https://huggingface.co/a/b/tree/main');
      expect(r.error, contains('repository link'));
    });

    test('rejects a lone Diffusers component such as the UNet', () {
      final r = parseModelUrl(
          'https://huggingface.co/Umranz/SD1.5-Uncensored-Photoreal/resolve/main/unet/diffusion_pytorch_model.safetensors');
      expect(r.value, isNull);
      expect(r.error, contains('Diffusers'));
    });

    test('rejects unsupported file types', () {
      final r = parseModelUrl('https://example.com/model.bin');
      expect(r.error, contains('Only'));
    });

    test('rejects vision projector files', () {
      final r = parseModelUrl('https://example.com/mmproj-model-f16.gguf');
      expect(r.error, contains('projector'));
    });

    test('rejects empty, malformed and non-web input', () {
      expect(parseModelUrl('').error, isNotNull);
      expect(parseModelUrl('not a url').error, isNotNull);
      expect(parseModelUrl('ftp://example.com/m.gguf').error, isNotNull);
    });

    test('sanitises file names so they cannot escape the models folder', () {
      final r = parseModelUrl('https://example.com/a/..%2F..%2Fevil.gguf');
      expect(r.value!.filename, isNot(contains('/')));
      expect(r.value!.filename, isNot(startsWith('.')));
    });

    test('a direct link on another host is not marked Hugging Face', () {
      final r = parseModelUrl('https://example.com/files/m.gguf');
      expect(r.value!.isHuggingFace, isFalse);
    });
  });

  group('shouldSendHfToken', () {
    test('only for https huggingface.co / hf.co hosts', () {
      expect(shouldSendHfToken('https://huggingface.co/a/b/resolve/main/m.gguf'), isTrue);
      expect(shouldSendHfToken('https://cdn-lfs.huggingface.co/x'), isTrue);
      expect(shouldSendHfToken('https://hf.co/a/b/resolve/main/m.gguf'), isTrue);
    });

    test('never for look-alike or plain-http hosts', () {
      expect(shouldSendHfToken('http://huggingface.co/a'), isFalse);
      expect(shouldSendHfToken('https://huggingface.co.evil.com/a'), isFalse);
      expect(shouldSendHfToken('https://evilhuggingface.co/a'), isFalse);
      expect(shouldSendHfToken('https://example.com/a'), isFalse);
    });
  });

  test('modelNameFromFilename strips the extension', () {
    expect(modelNameFromFilename('Foo-Q4_K_M.gguf'), 'Foo-Q4_K_M');
    expect(modelNameFromFilename('noext'), 'noext');
  });
}
