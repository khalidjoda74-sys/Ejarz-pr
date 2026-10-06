import 'package:firebase_core/firebase_core.dart';

import 'models.dart';

bool canQueueDraftSave(Object error) =>
    error is FirebaseException &&
    const {'unavailable', 'deadline-exceeded', 'network-request-failed'}
        .contains(error.code);

/// Preserve unsaved content without overwriting a newer remote revision.
ContractDraft forkConflictedDraft(ContractDraft source) =>
    ContractDraft.copyOf(source)
      ..serverRevision = null
      ..submissionId = ''
      ..acceptAccuracyDeclaration = false
      ..acceptDataSharing = false
      ..acceptTerms = false;
