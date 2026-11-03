import 'dart:async';
import 'dart:io';
import 'dart:math' show Point;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:telvox_chat_mobile_app/mobile/camera.dart';

/// The phone's cameras, as the camera plugin's platform side answers: a back
/// camera with flash and zoom, and a front one without flash.
class FakeCameras extends CameraPlatform {
  final created = <int, CameraDescription>{};
  final disposed = <int>[];
  final flash = <int, FlashMode>{};
  final focusPoints = <Point<double>?>[];
  final zooms = <double>[];
  final initialized = StreamController<CameraInitializedEvent>.broadcast();
  int recordingStarts = 0, recordingStops = 0;

  /// Errors, closings and turns that never come: open, but silent.
  final _quiet = StreamController<Object>.broadcast();

  /// Holds a recording's start, as a slow device does.
  Completer<void>? slowStart;

  /// A photo taken by the front camera: red on its left, blue on its right.
  late final String photo = () {
    final picture = img.Image(width: 32, height: 16);
    for (var x = 0; x < 32; x++) {
      for (var y = 0; y < 16; y++) {
        picture.setPixelRgb(x, y, x < 16 ? 255 : 0, 0, x < 16 ? 0 : 255);
      }
    }
    final file = File('${Directory.systemTemp.path}/fake-shot.jpg')
      ..writeAsBytesSync(img.encodeJpg(picture, quality: 100));
    return file.path;
  }();
  int _next = 0;

  static const back = CameraDescription(
    name: 'back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );
  static const front = CameraDescription(
    name: 'front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 270,
  );

  Iterable<int> get open => created.keys.where((id) => !disposed.contains(id));

  @override
  Future<List<CameraDescription>> availableCameras() async => [back, front];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings? mediaSettings,
  ) async {
    final id = ++_next;
    created[id] = cameraDescription;
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    scheduleMicrotask(
      () => initialized.add(
        CameraInitializedEvent(
          cameraId,
          1920,
          1080,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      initialized.stream.where((e) => e.cameraId == cameraId);

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _quiet.stream.cast();

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      _quiet.stream.cast();

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      _quiet.stream.cast();

  @override
  Widget buildPreview(int cameraId) =>
      ColoredBox(key: ValueKey('preview-$cameraId'), color: Colors.teal);

  @override
  Future<void> dispose(int cameraId) async => disposed.add(cameraId);

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    if (created[cameraId]!.lensDirection == CameraLensDirection.front) {
      throw CameraException('setFlashModeFailed', 'No flash on this camera');
    }
    flash[cameraId] = mode;
  }

  @override
  Future<void> setFocusMode(int cameraId, FocusMode mode) async {}
  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async =>
      focusPoints.add(point);
  @override
  Future<void> setExposurePoint(int cameraId, Point<double>? point) async {}
  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;
  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 8;
  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async => zooms.add(zoom);
  @override
  Future<double> getMinExposureOffset(int cameraId) async => -2;
  @override
  Future<double> getMaxExposureOffset(int cameraId) async => 2;
  @override
  Future<double> getExposureOffsetStepSize(int cameraId) async => .5;
  @override
  Future<void> lockCaptureOrientation(int cameraId, _) async {}
  @override
  Future<void> unlockCaptureOrientation(int cameraId) async {}

  @override
  Future<XFile> takePicture(int cameraId) async => XFile(photo);

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    recordingStarts++;
    await slowStart?.future;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    recordingStops++;
    final clip = File('${Directory.systemTemp.path}/fake-clip.mp4')
      ..writeAsBytesSync(List.filled(64, 1));
    return XFile(clip.path);
  }
}

/// Frames for a second: a spinner never settles, so no pumpAndSettle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeCameras cameras;

  setUp(() => CameraPlatform.instance = cameras = FakeCameras());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
    await settle(tester);
  }

  Finder preview() => find.byKey(const ValueKey('camera-preview'));

  testWidgets('back from another app, the preview comes back by itself', (
    tester,
  ) async {
    await open(tester);
    expect(preview(), findsOneWidget);
    expect(cameras.created.values.single, FakeCameras.back);

    // The notification shade, a call, another app: the camera is let go.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle(tester);
    expect(cameras.open, isEmpty);

    // Back: it opens again, with no need to close and reopen the screen.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(preview(), findsOneWidget);
    expect(cameras.open, hasLength(1));
    expect(cameras.created, hasLength(2));
  });

  testWidgets('switching cameras keeps one open, and flash only on the back', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Flash'));
    await settle(tester);

    await tester.tap(find.byTooltip('Switch camera'));
    await settle(tester);
    // The front camera opened despite flash being on (it has none).
    expect(cameras.created.values.last, FakeCameras.front);
    expect(cameras.open, hasLength(1));
    expect(preview(), findsOneWidget);
    expect(find.textContaining('could not start'), findsNothing);

    await tester.tap(find.byTooltip('Switch camera'));
    await settle(tester);
    expect(cameras.created.values.last, FakeCameras.back);
    expect(cameras.open, hasLength(1));
  });

  testWidgets('tap focuses there; the zoom button goes to 2x', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    expect(find.byKey(const ValueKey('focus-ring')), findsOneWidget);
    final point = cameras.focusPoints.single!;
    expect(point.x, inInclusiveRange(0, 1));
    expect(point.y, inInclusiveRange(0, 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('focus-ring')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('zoom')));
    await tester.pump();
    expect(cameras.zooms.last, 2);
    expect(find.text('2.0x'), findsOneWidget);
  });

  testWidgets('a selfie is kept as the mirror image the preview showed', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Switch camera'));
    await settle(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('shutter')));
      for (
        var i = 0;
        i < 40 && find.byType(MediaPreviewPage).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await settle(tester);
    final page = tester.widget<MediaPreviewPage>(find.byType(MediaPreviewPage));
    final shot = img.decodeJpg(File(page.file.path).readAsBytesSync())!;
    // What was on the left (red) is now on the right, as in a mirror.
    expect(shot.getPixel(2, 8).r, lessThan(80));
    expect(shot.getPixel(2, 8).b, greaterThan(170));
    expect(shot.getPixel(29, 8).r, greaterThan(170));
  });

  testWidgets('hold records and letting go stops it', (tester) async {
    await open(tester);
    final hold = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('shutter'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(cameras.recordingStarts, 1);
    expect(find.byKey(const ValueKey('recording-timer')), findsOneWidget);
    expect(find.byKey(const ValueKey('stop')), findsOneWidget);
    await hold.up();
    await settle(tester);
    expect(cameras.recordingStops, 1);
    expect(find.byType(MediaPreviewPage), findsOneWidget);
  });

  testWidgets('let go before recording has started, it still stops', (
    tester,
  ) async {
    await open(tester);
    cameras.slowStart = Completer();
    final hold = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('shutter'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await hold.up();
    await tester.pump();
    cameras.slowStart!.complete();
    await settle(tester);
    // The old camera kept recording here, with nothing on screen to stop it.
    expect(cameras.recordingStops, 1);
  });

  testWidgets('slid up to the lock it keeps recording; Stop ends it', (
    tester,
  ) async {
    await open(tester);
    final hold = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('shutter'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('Slide up to keep recording'), findsOneWidget);
    await hold.moveBy(const Offset(0, -100));
    await tester.pump();
    await hold.up();
    await tester.pump(const Duration(seconds: 3));
    expect(cameras.recordingStops, 0);
    expect(find.text('0:03'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('shutter')));
    await settle(tester);
    expect(cameras.recordingStops, 1);
  });

  testWidgets('Video: tap to start, tap again to stop', (tester) async {
    await open(tester);
    await tester.tap(find.text('Video'));
    await tester.pump();
    expect(find.text('Tap to start, tap again to stop'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shutter')));
    await tester.pump();
    expect(cameras.recordingStarts, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('shutter')));
    await settle(tester);
    expect(cameras.recordingStops, 1);
  });
}
