// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool _dirty = false, _attached = false;
void setAdminEditorDirty(bool value) {
  _dirty = value;
  if (!_attached) {
    _attached = true;
    html.window.onBeforeUnload.listen((event) {
      if (_dirty) {
        event.preventDefault();
        (event as html.BeforeUnloadEvent).returnValue = '';
      }
    });
  }
  html.window.parent?.postMessage(
      {'type': 'aqdak-editor-dirty', 'dirty': value},
      html.window.location.origin);
}

void completeAdminEditor(String contractId) {
  setAdminEditorDirty(false);
  html.window.parent?.postMessage(
      {'type': 'aqdak-contract-complete', 'contractId': contractId},
      html.window.location.origin);
}

void cancelAdminEditor() {
  setAdminEditorDirty(false);
  html.window.parent?.postMessage(
      {'type': 'aqdak-editor-cancel'}, html.window.location.origin);
}

void savedAdminEditor(String contractId) {
  html.window.parent?.postMessage(
      {'type': 'aqdak-contract-saved', 'contractId': contractId},
      html.window.location.origin);
}
