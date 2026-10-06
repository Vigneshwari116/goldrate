import 'dart:html' as html;

html.EventListener? _listener;

void pushBrowserHistoryState() {
  html.window.history.pushState(null, '', html.window.location.href);
}

void goBackInBrowser() {
  html.window.history.back();
}

void listenBrowserBack(void Function() onBack) {
  _listener = (_) => onBack();
  html.window.addEventListener('popstate', _listener!);
}

void disposeBrowserBack() {
  if (_listener != null) {
    html.window.removeEventListener('popstate', _listener!);
    _listener = null;
  }
}
