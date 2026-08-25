import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';

/// Stored files sit behind the auth header, so Image.network would 401.
/// Fetches the bytes once and caches them for the widget's lifetime.
class AuthedImage extends StatefulWidget {
  const AuthedImage({
    super.key,
    required this.path,
    this.width = 64,
    this.height = 64,
    this.fit = BoxFit.cover,
    this.borderRadius = 6,
  });

  final String path;
  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;

  @override
  State<AuthedImage> createState() => _AuthedImageState();
}

class _AuthedImageState extends State<AuthedImage> {
  Future<Uint8List>? _future;

  @override
  void initState() {
    super.initState();
    _future = Api.instance.fileBytes(widget.path);
  }

  @override
  void didUpdateWidget(AuthedImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _future = Api.instance.fileBytes(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: FutureBuilder<Uint8List>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return const ColoredBox(
                color: Color(0x22000000),
                child: Center(child: Icon(Icons.broken_image_outlined, size: 18)),
              );
            }
            if (!snap.hasData) {
              return const ColoredBox(
                color: Color(0x11000000),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return Image.memory(snap.data!, fit: widget.fit);
          },
        ),
      ),
    );
  }
}
