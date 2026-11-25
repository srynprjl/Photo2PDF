import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets/notices.dart';

/// Takes photos with the device camera, one page after another.
///
/// The shots come back as JPEG bytes rather than files, because the app only
/// needs the pixels and a temporary file would have to be cleaned up anyway.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  /// Opens the screen and returns what was captured, or an empty list.
  static Future<List<Uint8List>> open(BuildContext context) async {
    final List<Uint8List>? shots = await Navigator.of(context)
        .push<List<Uint8List>>(
          MaterialPageRoute<List<Uint8List>>(
            builder: (BuildContext context) => const CameraScreen(),
          ),
        );
    return shots ?? const <Uint8List>[];
  }

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  int _cameraIndex = 0;

  final List<Uint8List> _shots = <Uint8List>[];

  bool _starting = true;
  bool _taking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });

    CameraController? started;
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        _stop('This device has no camera.');
        return;
      }

      started = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await started.initialize();
      if (!mounted) {
        await started.dispose();
        return;
      }

      final CameraController? previous = _controller;
      setState(() {
        _controller = started;
        _starting = false;
      });
      await previous?.dispose();
    } on CameraException catch (error) {
      await started?.dispose();
      _stop(
        error.code == 'CameraAccessDenied'
            ? 'Camera access is off. Allow it for Photo2PDF in the system '
                  'settings and try again.'
            : 'Could not start the camera: ${error.description ?? error.code}',
      );
    }
  }

  void _stop(String message) {
    if (!mounted) return;
    setState(() {
      _starting = false;
      _error = message;
    });
  }

  Future<void> _takePhoto() async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized || _taking) {
      return;
    }

    setState(() => _taking = true);
    try {
      final XFile file = await controller.takePicture();
      final Uint8List bytes = await file.readAsBytes();
      await _deleteQuietly(file.path);
      if (!mounted) return;
      setState(() => _shots.add(bytes));
    } on CameraException catch (error) {
      if (mounted) {
        showNotice(
          context,
          'Could not take the photo: ${error.description ?? error.code}',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _taking = false);
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _controller == null) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _controller?.dispose();
    if (!mounted) return;
    setState(() => _controller = null);
    await _start();
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // The system clears its own cache; a leftover file is harmless.
    }
  }

  /// Hands whatever was captured back to the converter.
  void _done() => Navigator.of(context).pop(_shots);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return PopScope<List<Uint8List>>(
      // Back should keep the shots rather than throw them away.
      canPop: _shots.isEmpty,
      onPopInvokedWithResult: (bool didPop, List<Uint8List>? result) {
        if (!didPop) {
          _done();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          titleTextStyle: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
          ),
          title: Text(
            _shots.isEmpty
                ? 'Take photos'
                : '${_shots.length} photo${_shots.length == 1 ? '' : 's'}',
          ),
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _done,
            icon: const Icon(Icons.close),
          ),
          actions: <Widget>[
            if (_cameras.length > 1)
              IconButton(
                tooltip: 'Switch camera',
                onPressed: _starting ? null : _switchCamera,
                icon: const Icon(Icons.cameraswitch_outlined),
              ),
          ],
        ),
        body: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final String? error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.no_photography_outlined,
                size: 56,
                color: Colors.white70,
              ),
              const SizedBox(height: 16),
              Text(
                error,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _start, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final CameraController? controller = _controller;
    if (_starting || controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        Expanded(child: Center(child: CameraPreview(controller))),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _shots.isEmpty
                      ? 'Shoot a page'
                      : '${_shots.length} ready to add',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ),
              IconButton.filled(
                tooltip: 'Take photo',
                onPressed: _taking ? null : _takePhoto,
                iconSize: 34,
                padding: const EdgeInsets.all(18),
                icon: _taking
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _shots.isEmpty ? null : _done,
                    child: Text(
                      _shots.isEmpty ? 'Done' : 'Done (${_shots.length})',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
