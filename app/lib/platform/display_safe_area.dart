import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/reader/reader_cutout_insets.dart';

/// A route's background also fills the reserved, content-free window edges.
class DisplaySafeAreaController extends NavigatorObserver with ChangeNotifier {
  final _routes = <Route<dynamic>>[];
  final _colors = <Route<dynamic>, Map<Object, Color>>{};
  bool _scheduled = false;
  bool _disposed = false;
  Color? get background {
    for (final route in _routes.reversed) {
      if (route is! PageRoute) continue;
      final colors = _colors[route];
      return colors == null || colors.isEmpty ? null : colors.values.last;
    }
    return null;
  }

  void _changed() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void setBackground(Route<dynamic> route, Color? color, Object owner) {
    if (_disposed) return;
    if (color == null) {
      if (_colors[route]?.remove(owner) == null) return;
      if (_colors[route]!.isEmpty) _colors.remove(route);
    } else {
      final colors = _colors.putIfAbsent(route, () => {});
      if (colors[owner] == color) return;
      colors[owner] = color;
    }
    _changed();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _colors.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _colors.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _colors.remove(oldRoute);
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _DisplayScope extends InheritedWidget {
  const _DisplayScope({required this.controller, required super.child});
  final DisplaySafeAreaController controller;
  @override
  bool updateShouldNotify(_DisplayScope oldWidget) =>
      controller != oldWidget.controller;
}

class DisplaySafeBackground extends StatefulWidget {
  const DisplaySafeBackground({
    super.key,
    required this.color,
    required this.child,
  });
  final Color color;
  final Widget child;
  @override
  State<DisplaySafeBackground> createState() => _DisplaySafeBackgroundState();
}

class _DisplaySafeBackgroundState extends State<DisplaySafeBackground> {
  final _owner = Object();
  bool _enabled = true;
  DisplaySafeAreaController? _controller;
  ModalRoute<dynamic>? _route;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context
        .dependOnInheritedWidgetOfExactType<_DisplayScope>()
        ?.controller;
    final route = ModalRoute.of(context);
    if (_controller != controller || _route != route) {
      if (_route != null) _controller?.setBackground(_route!, null, _owner);
      _controller = controller;
      _route = route;
    }
    _enabled = TickerMode.valuesOf(context).enabled;
    if (route != null) {
      controller?.setBackground(route, _enabled ? widget.color : null, _owner);
    }
  }

  @override
  void didUpdateWidget(DisplaySafeBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_route != null) {
      _controller?.setBackground(
        _route!,
        _enabled ? widget.color : null,
        _owner,
      );
    }
  }

  @override
  void dispose() {
    if (_route != null) _controller?.setBackground(_route!, null, _owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Reserves physical space outside the Navigator, so even custom titles,
/// modal routes, full-screen video and overlays cannot paint into a cutout.
class DisplaySafeArea extends StatefulWidget {
  const DisplaySafeArea({
    super.key,
    required this.controller,
    required this.child,
    this.enabled,
  });
  final DisplaySafeAreaController controller;
  final Widget child;
  final bool? enabled;
  @override
  State<DisplaySafeArea> createState() => _DisplaySafeAreaState();
}

class _DisplaySafeAreaState extends State<DisplaySafeArea>
    with WidgetsBindingObserver {
  static const _method = MethodChannel('fqapp/display');
  static const _events = EventChannel('fqapp/display/events');
  StreamSubscription<dynamic>? _subscription;
  EdgeInsets _cutoutPixels = EdgeInsets.zero;
  bool get _enabled => widget.enabled ?? Platform.operatingSystem == 'ohos';

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _subscription = _events.receiveBroadcastStream().listen(
      _receive,
      onError: (Object _) {},
    );
    unawaited(_refresh());
  }

  void _receive(dynamic value) {
    if (!mounted || value is! Map) return;
    double edge(String key) {
      final raw = value[key];
      return raw is num && raw.isFinite ? math.max(0, raw.toDouble()) : 0;
    }

    final insets = EdgeInsets.fromLTRB(
      edge('left'),
      edge('top'),
      edge('right'),
      edge('bottom'),
    );
    if (insets != _cutoutPixels) setState(() => _cutoutPixels = insets);
  }

  Future<void> _refresh() async {
    try {
      _receive(await _method.invokeMapMethod<Object?, Object?>('cutoutInsets'));
    } on PlatformException {
      /* Retain the last cutout and Flutter view padding. */
    } on MissingPluginException {
      /* Host-side tests and non-Harmony embedders. */
    }
  }

  @override
  void didChangeMetrics() {
    if (_enabled) unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_enabled && state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    final data = readerMediaQueryWithCutoutInsets(MediaQuery.of(context));
    final cutout = _cutoutPixels / data.devicePixelRatio;
    final safe = EdgeInsets.fromLTRB(
      math.max(data.viewPadding.left, cutout.left),
      math.max(data.viewPadding.top, cutout.top),
      math.max(data.viewPadding.right, cutout.right),
      math.max(data.viewPadding.bottom, cutout.bottom),
    );
    EdgeInsets remaining(EdgeInsets edges) => EdgeInsets.fromLTRB(
      math.max(0, edges.left - safe.left),
      math.max(0, edges.top - safe.top),
      math.max(0, edges.right - safe.right),
      math.max(0, edges.bottom - safe.bottom),
    );
    return _DisplayScope(
      controller: widget.controller,
      child: AnimatedBuilder(
        animation: widget.controller,
        child: widget.child,
        builder: (context, child) {
          final color =
              widget.controller.background ??
              Theme.of(context).scaffoldBackgroundColor;
          return ColoredBox(
            key: const ValueKey('display-safe-background'),
            color: color,
            child: Padding(
              key: const ValueKey('display-safe-frame'),
              padding: safe,
              child: ClipRect(
                child: MediaQuery(
                  data: data.copyWith(
                    size: Size(
                      math.max(0, data.size.width - safe.horizontal),
                      math.max(0, data.size.height - safe.vertical),
                    ),
                    padding: remaining(data.padding),
                    viewPadding: remaining(data.viewPadding),
                    viewInsets: remaining(data.viewInsets),
                    displayFeatures: data.displayFeatures
                        .where(
                          (feature) =>
                              feature.type != ui.DisplayFeatureType.cutout,
                        )
                        .toList(),
                  ),
                  child: child!,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
