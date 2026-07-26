import 'dart:async';

/// Creates a stream that can be listened to again after a previous listener
/// cancels. A fresh source subscription is created for every listener.
Stream<T> reusableStream<T>(Stream<T> Function() sourceFactory) {
  return Stream<T>.multi((controller) {
    late final StreamSubscription<T> subscription;
    try {
      subscription = sourceFactory().listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    } catch (error, stackTrace) {
      controller
        ..addError(error, stackTrace)
        ..close();
      return;
    }

    controller.onPause = subscription.pause;
    controller.onResume = subscription.resume;
    controller.onCancel = subscription.cancel;
  });
}

/// A reusable equivalent of [Stream.value].
Stream<T> reusableValueStream<T>(T value) {
  return reusableStream<T>(() => Stream<T>.value(value));
}
