import 'package:cryptography/cryptography.dart';

/// A SHA-256 as Pawchive's hash lookup takes it: 64 hex digits.
bool isSha256(String text) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(text);

/// The SHA-256 of [chunks] in lowercase hex, read a chunk at a time so a
/// large video never sits in memory whole. [onProgress] gets the bytes read
/// so far.
Future<String> sha256Hex(
  Stream<List<int>> chunks, {
  void Function(int read)? onProgress,
}) async {
  final sink = Sha256().newHashSink();
  var read = 0;
  await for (final chunk in chunks) {
    sink.add(chunk);
    read += chunk.length;
    onProgress?.call(read);
  }
  sink.close();
  final hash = await sink.hash();
  return [for (final byte in hash.bytes) byte.toRadixString(16).padLeft(2, '0')]
      .join();
}
