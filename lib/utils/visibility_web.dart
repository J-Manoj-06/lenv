// Web-only visibility handler using dart:html
// This file is included only when compiling for web via conditional import.
import 'dart:async';
import 'dart:html' as html;

StreamSubscription<html.Event>? _visibilitySub;

void attachWebVisibilityListener(void Function() onHidden) {
  // Listen for document visibility change; when hidden, trigger callback
  _visibilitySub = html.document.onVisibilityChange.listen((_) {
    if (html.document.hidden == true) {
      onHidden();
    }
  });
}

void detachWebVisibilityListener() {
  _visibilitySub?.cancel();
  _visibilitySub = null;
}
