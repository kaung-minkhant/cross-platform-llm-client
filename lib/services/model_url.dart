/// Turns a link the user pasted (usually from Hugging Face) into something the
/// downloader can fetch. Pure Dart so it can be unit tested.
library;

/// File types the app can load.
const supportedModelExtensions = ['.gguf', '.litertlm', '.safetensors'];

class ModelUrl {
  /// URL to download from. Hugging Face `/blob/` pages are rewritten to the
  /// raw-file `/resolve/` form.
  final String url;

  /// Name to save the file under, safe for the models folder.
  final String filename;

  /// Only these hosts may receive a Hugging Face access token.
  final bool isHuggingFace;

  const ModelUrl(
      {required this.url,
      required this.filename,
      required this.isHuggingFace});
}

class ModelUrlResult {
  final ModelUrl? value;
  final String? error;
  const ModelUrlResult.ok(ModelUrl this.value) : error = null;
  const ModelUrlResult.error(String this.error) : value = null;
}

const _diffusersComponents = {
  'unet',
  'vae',
  'text_encoder',
  'text_encoder_2',
  'text_encoder_3',
  'transformer',
  'safety_checker',
  'feature_extractor',
};

/// True for huggingface.co / hf.co (and subdomains such as the CDN hosts).
bool isHuggingFaceHost(String host) {
  final h = host.toLowerCase();
  return h == 'huggingface.co' ||
      h.endsWith('.huggingface.co') ||
      h == 'hf.co' ||
      h.endsWith('.hf.co');
}

/// Whether [url] is allowed to carry a Hugging Face token.
bool shouldSendHfToken(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' && isHuggingFaceHost(uri.host);
}

ModelUrlResult parseModelUrl(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return const ModelUrlResult.error('Paste a link first.');

  var uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return const ModelUrlResult.error('That does not look like a web link.');
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    return const ModelUrlResult.error('Only http and https links work.');
  }

  final isHf = isHuggingFaceHost(uri.host);
  if (isHf && uri.scheme != 'https') {
    uri = uri.replace(scheme: 'https');
  }

  var segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  if (isHf) {
    // owner/repo/(resolve|blob)/revision/path/to/file
    final isFileLink = segments.length >= 5 &&
        (segments[2] == 'resolve' || segments[2] == 'blob');
    if (!isFileLink) {
      return const ModelUrlResult.error(
        'This is a repository link, not a file. Open the repository\'s '
        '"Files" tab, pick one .gguf / .safetensors / .litertlm file and '
        'paste that file\'s link.',
      );
    }
    // Diffusers repos split one model into component folders. The app loads
    // a single-file checkpoint, so a lone component is useless on its own.
    final folders = segments.sublist(4, segments.length - 1);
    if (folders.any(_diffusersComponents.contains)) {
      return const ModelUrlResult.error(
        'This file is one part of a Diffusers-format model (unet, vae or '
        'text encoder). The app needs a single-file checkpoint. Convert the '
        'model to one .safetensors file, then import or link that.',
      );
    }
    if (segments[2] == 'blob') {
      segments = [...segments]..[2] = 'resolve';
    }
    uri = uri.replace(pathSegments: segments).removeFragment();
  } else if (segments.isEmpty) {
    return const ModelUrlResult.error('The link does not point to a file.');
  }

  final name = _safeFilename(Uri.decodeComponent(segments.last));
  final lower = name.toLowerCase();
  if (!supportedModelExtensions.any(lower.endsWith)) {
    return ModelUrlResult.error(
      'Only ${supportedModelExtensions.join(', ')} files can be added. '
      'This link ends in "$name".',
    );
  }
  if (lower.endsWith('.gguf') && lower.contains('mmproj')) {
    return const ModelUrlResult.error(
      'That is a vision projector, not a model. It downloads automatically '
      'with its model.',
    );
  }

  return ModelUrlResult.ok(ModelUrl(
    url: uri.toString(),
    filename: name,
    isHuggingFace: isHf,
  ));
}

String _safeFilename(String name) {
  final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_');
  // Never allow a name that climbs out of the models folder.
  return cleaned.replaceAll(RegExp(r'^\.+'), '');
}

/// Readable model name from a file name: "Foo-Q4_K_M.gguf" -> "Foo-Q4_K_M".
String modelNameFromFilename(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot > 0 ? filename.substring(0, dot) : filename;
}
