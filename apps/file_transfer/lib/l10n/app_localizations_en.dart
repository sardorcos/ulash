// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get unitB => 'B';

  @override
  String get unitKiB => 'KB';

  @override
  String get unitMiB => 'MB';

  @override
  String get unitGiB => 'GB';

  @override
  String get unitTiB => 'TB';

  @override
  String filesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '$count file',
    );
    return '$_temp0';
  }

  @override
  String get platformUnknown => 'Device';

  @override
  String get phasePreparing => 'Preparing files';

  @override
  String get phaseQueued => 'Queued';

  @override
  String get phaseRetrying => 'Reconnecting';

  @override
  String get phaseWaitingForConsent => 'Waiting for approval';

  @override
  String get phaseTransferring => 'Transferring files';

  @override
  String get phaseVerifying => 'Verifying file';

  @override
  String get phaseCompleted => 'Transfer complete';

  @override
  String get phasePaused => 'Transfer paused';

  @override
  String get phaseFailed => 'Could not finish';

  @override
  String get phaseCancelled => 'Transfer cancelled';

  @override
  String get phaseExpired => 'Request expired';

  @override
  String get networkStarting => 'Connecting…';

  @override
  String get networkReady => 'Local network';

  @override
  String get networkUnavailable => 'Not connected';

  @override
  String get networkPermissionRequired => 'Network access needed';

  @override
  String speedPerSecond(String value) {
    return '$value/s';
  }

  @override
  String get navSend => 'Send';

  @override
  String get navReceive => 'Receive';

  @override
  String get navDevices => 'Devices';

  @override
  String get navHistory => 'History';

  @override
  String get navSettings => 'Settings';

  @override
  String get actionFailedRetry =>
      'The action could not be completed. Please try again.';

  @override
  String get localNetworkNotice =>
      'No local network access. Open Settings → Ulash, turn on Local Network, then tap Try again.';

  @override
  String get openSettingsShort => 'Settings';

  @override
  String get retry => 'Try again';

  @override
  String get incomingWaitingNotice =>
      'Incoming files are waiting for your approval';

  @override
  String get view => 'View';

  @override
  String get pairingWaitingNotice => 'A new device wants to connect';

  @override
  String get check => 'Review';

  @override
  String get sidebarTagline => 'Between your\ndevices';

  @override
  String get sidebarTaglineDetail => 'Files travel over\nyour local network.';

  @override
  String get sendEyebrow => 'LOCAL TRANSFER';

  @override
  String get sendTitle => 'Send';

  @override
  String get sendSubtitle =>
      'Choose what to send and to whom. Photos, videos and documents keep their original quality.';

  @override
  String get recipientStep => '2. Recipient';

  @override
  String get recipientSubtitle => 'Available trusted devices';

  @override
  String get refreshDevices => 'Refresh devices';

  @override
  String get connectDeviceTitle => 'Connect a device';

  @override
  String get connectDeviceHint =>
      'Open the app on your other device and add it with an invitation.';

  @override
  String get connect => 'Connect';

  @override
  String get chooseRecipient => 'Choose a recipient';

  @override
  String get sendFiles => 'Send files';

  @override
  String get recipientWillConfirm =>
      'The recipient approves the transfer on their device.';

  @override
  String get currentTransfers => 'Current transfers';

  @override
  String get foldersUnsupported =>
      'Choose individual files. Folders are not supported yet.';

  @override
  String get dropFilesHere => 'Drop files here';

  @override
  String get filesStep => '1. Files';

  @override
  String get whatToSend => 'What would you like to send?';

  @override
  String get clearSelectedFiles => 'Clear selected files';

  @override
  String get startWithFiles => 'Start with files';

  @override
  String get startWithFilesHint =>
      'A photo from your phone, a work document\nor a whole video — pick anything.';

  @override
  String get photosAndVideos => 'Photos & videos';

  @override
  String get files => 'Files';

  @override
  String get chooseFiles => 'Choose files';

  @override
  String get orDropHere => 'or drag them here';

  @override
  String get preparingFile => 'Preparing file…';

  @override
  String get preparationFailed => 'Could not prepare';

  @override
  String get sizePending => 'Calculating size';

  @override
  String removeSource(String name) {
    return 'Remove $name';
  }

  @override
  String get add => 'Add';

  @override
  String totalSize(String size) {
    return 'Total: $size';
  }

  @override
  String get receiveEyebrow => 'RECEIVING';

  @override
  String get receiveTitle => 'Your files will\nappear here.';

  @override
  String get receiveSubtitle =>
      'Keep the app open. The sender will see this device once you are connected.';

  @override
  String get receivingOn => 'Receiving is on';

  @override
  String get receivingOff => 'Receiving is off';

  @override
  String saveLocation(String location) {
    return 'Saved to: $location';
  }

  @override
  String get showInvitation => 'Show QR';

  @override
  String get myDevices => 'My devices';

  @override
  String get noIncomingTitle => 'No incoming offers yet';

  @override
  String get noIncomingReady =>
      'When a sender picks this device, you can review the files and accept the transfer.';

  @override
  String get noIncomingOff =>
      'Turn on receiving when you are ready to get files.';

  @override
  String get incomingOffers => 'Waiting for you';

  @override
  String andMoreFiles(String files) {
    return 'And $files more';
  }

  @override
  String offerValidUntil(String time) {
    return 'This offer is valid until $time. Without an answer the sender will need to create a new one.';
  }

  @override
  String get acceptFiles => 'Accept files';

  @override
  String get decline => 'Decline';

  @override
  String get devicesEyebrow => 'YOUR DEVICES';

  @override
  String get devicesTitle => 'Connect once.\nThen it just works.';

  @override
  String get devicesSubtitle =>
      'Add a phone or computer to send files without setting up again.';

  @override
  String get connectDevice => 'Connect a device';

  @override
  String get appOpenBothSides => 'The app must be open on both devices.';

  @override
  String get createInvitation => 'Show QR';

  @override
  String get enterInvitation => 'Enter code';

  @override
  String get scanInvitationTooltip => 'Scan an invitation from another device';

  @override
  String get cameraUnavailableTooltip =>
      'Camera unavailable. Use the invitation text.';

  @override
  String get scanQr => 'Scan QR';

  @override
  String deviceCodeHint(String code) {
    return 'This device\'s code: $code. When connecting, it must match the code in the request on the other device.';
  }

  @override
  String get pairingRequest => 'Connection request';

  @override
  String get pairingConfirmGeneric =>
      'Approve only if you just added this device.';

  @override
  String pairingConfirmCode(String code) {
    return 'Approve only if the code $code matches the code on the connecting device.';
  }

  @override
  String get connectedDevices => 'Connected devices';

  @override
  String get availabilityChecked => 'The app checks availability';

  @override
  String get onlyThisDeviceTitle => 'Only this device so far';

  @override
  String get onlyThisDeviceHint =>
      'Create an invitation or enter one from your other device. It appears here once approved.';

  @override
  String disconnectDevice(String name) {
    return 'Disconnect $name';
  }

  @override
  String get peerAvailable => 'Available';

  @override
  String get peerOffline => 'Offline';

  @override
  String get trustedDevice => 'Trusted device';

  @override
  String get historyEyebrow => 'HISTORY';

  @override
  String get historyTitle => 'Everything you sent.\nIn one place.';

  @override
  String get historySubtitle =>
      'Status, recipient and saved files. Unfinished transfers stay here too.';

  @override
  String get filterAll => 'All';

  @override
  String get filterSent => 'Sent';

  @override
  String get filterReceived => 'Received';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get historyEmptyTitle => 'No history yet';

  @override
  String get historyFilteredEmptyTitle => 'No such transfers yet';

  @override
  String get historyEmptyHint =>
      'After your first transfer, its result appears here.';

  @override
  String get historyFilteredEmptyHint =>
      'Choose another filter or start a new transfer.';

  @override
  String showMore(int count) {
    return 'Show more ($count)';
  }

  @override
  String get clearHistoryQuestion => 'Clear history?';

  @override
  String get clearHistoryBody =>
      'Records of finished, cancelled and failed transfers will be removed, together with their unused prepared copies. Received files stay — you can delete them individually.';

  @override
  String get cancel => 'Cancel';

  @override
  String get clear => 'Clear';

  @override
  String get deleteReceivedQuestion => 'Delete received files?';

  @override
  String get deleteRecordQuestion => 'Delete record?';

  @override
  String deleteReceivedBody(String title, String size) {
    return '$title\n\nThe transfer and its files ($size) will be deleted from this device. Copies you already saved or shared stay.';
  }

  @override
  String deleteRecordBody(String title) {
    return '$title\n\nThe record will be removed from history along with unused prepared copies. If the original file was already deleted, such a copy may have been the only one.';
  }

  @override
  String get delete => 'Delete';

  @override
  String get shareFile => 'Share file';

  @override
  String get close => 'Close';

  @override
  String toPeer(String name) {
    return 'To: $name';
  }

  @override
  String fromPeer(String name) {
    return 'From: $name';
  }

  @override
  String savedAt(String location) {
    return 'Saved: $location';
  }

  @override
  String filesFolder(String location) {
    return 'Files folder: $location';
  }

  @override
  String previouslySaved(String destination) {
    return 'Previously saved: $destination';
  }

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get cancelTransfer => 'Cancel';

  @override
  String get sendAgain => 'Send again';

  @override
  String get openFiles => 'Open files';

  @override
  String get openFile => 'Open file';

  @override
  String get saveFileCopyEllipsis => 'Save a copy of a file…';

  @override
  String get saveCopyEllipsis => 'Save a copy…';

  @override
  String get share => 'Share';

  @override
  String get settingsEyebrow => 'SETTINGS';

  @override
  String get settingsTitle => 'Made comfortable for you.';

  @override
  String get settingsSubtitle =>
      'Device name, appearance and where received files live.';

  @override
  String get thisDevice => 'This device';

  @override
  String get deviceName => 'Device name';

  @override
  String deviceNameWithCode(String name, String code) {
    return '$name\nDevice code: $code';
  }

  @override
  String get change => 'Change';

  @override
  String get receivedFiles => 'Received files';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get connection => 'Connection';

  @override
  String get localNetwork => 'Local network';

  @override
  String get trustedDevices => 'Trusted devices';

  @override
  String get trustedDevicesHint =>
      'Every new device connects only with your approval.';

  @override
  String get open => 'Open';

  @override
  String get privacyAndSupport => 'Privacy & support';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacySummary => 'No accounts, cloud, ads or analytics.';

  @override
  String get more => 'Details';

  @override
  String get diagnosticsLog => 'Support report';

  @override
  String get diagnosticsHint =>
      'Error codes without file names or addresses. Only you can send it.';

  @override
  String get send => 'Send';

  @override
  String get resetKeys => 'Reset device keys';

  @override
  String get resetKeysHint =>
      'Disconnects all devices. You can connect them again with a QR code.';

  @override
  String get reset => 'Reset';

  @override
  String get privacyBody =>
      'Ulash sends files directly between your devices on the local network. Files are never uploaded to servers; the app needs no account and has no ads, tracking or analytics.\n\nConnections are encrypted (TLS) and verified against the device key approved during pairing. You accept every incoming transfer yourself.\n\nThe camera is used only to scan QR codes. Local network access is needed to find your devices. The diagnostics log stays on the device and is sent only when you choose to.';

  @override
  String get resetKeysQuestion => 'Reset device keys?';

  @override
  String get resetKeysBody =>
      'New keys will be created and all connected devices forgotten. To exchange files again, reconnect them with a QR code. Received files and history stay.';

  @override
  String versionLabel(String version) {
    return 'Ulash $version';
  }

  @override
  String get storage => 'Storage';

  @override
  String get refreshStorage => 'Refresh storage info';

  @override
  String get storageUnavailable => 'Storage information is not available yet.';

  @override
  String get freeSpace => 'Free space';

  @override
  String get freeSpaceUnknown =>
      'The system did not report capacity. The temporary copy limit still applies.';

  @override
  String freeSpaceChecked(String size, String time) {
    return '$size · checked $time';
  }

  @override
  String get temporaryCopies => 'Prepared copies';

  @override
  String temporaryUsage(String used, String reserved) {
    return '$used in use; $reserved reserved for transfers in progress.';
  }

  @override
  String get quotaUsageSemantics => 'Temporary storage limit usage';

  @override
  String get quotaTitle => 'Temporary storage limit';

  @override
  String quotaHint(String reserve) {
    return 'Before writing, $reserve of free space is kept in reserve. Completed received files do not count toward this limit and are never removed when temporary copies are cleared.';
  }

  @override
  String get unusedCopies => 'Unused copies';

  @override
  String unusedCopiesSummary(String files, String size) {
    return '$files · $size';
  }

  @override
  String get clearUnusedCopies => 'Clear unused copies';

  @override
  String get incompleteIncoming => 'Unfinished incoming';

  @override
  String incompleteSummary(int count, String used, String reserved) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transfers',
      one: '$count transfer',
    );
    return '$_temp0 · $used in use; $reserved reserved to continue.';
  }

  @override
  String get incompleteHint =>
      'Clearing stops the selected incoming transfers and deletes their unfinished parts. They will need to be sent again. Completed received files stay in place.';

  @override
  String get clearIncomplete => 'Clear unfinished incoming';

  @override
  String get deleteTemporaryQuestion => 'Delete temporary copies?';

  @override
  String deleteTemporaryBody(int count, String size) {
    return 'Up to $count copies ($size) not used by selected files or unfinished transfers will be deleted. To send them again you will need to choose them again. Originals and completed received files stay. If an original was already deleted, its temporary copy may be the only one and cannot be restored after clearing.';
  }

  @override
  String fileWithSize(String name, String size) {
    return '$name · $size';
  }

  @override
  String andMoreFilesDot(int count) {
    return 'And $count more files.';
  }

  @override
  String get keep => 'Keep';

  @override
  String get deleteCopies => 'Delete copies';

  @override
  String get stopIncomingQuestion => 'Stop receiving and delete partial files?';

  @override
  String stopIncomingBody(int count, String used, String reserved) {
    return 'The listed transfers will be stopped: $count. Their unfinished parts currently use $used, with $reserved more reserved to continue. The amount may change if receiving is still in progress. These transfers cannot be resumed after clearing: the sender will need to create new ones. Completed received files and history are kept.';
  }

  @override
  String incompleteItem(
    String title,
    String peer,
    String files,
    String size,
    int completed,
  ) {
    return '$title\n$peer · $files unfinished · $size\nCompleted files kept: $completed';
  }

  @override
  String get stopAndClear => 'Stop and clear';

  @override
  String get resendQuestion => 'Create a new send?';

  @override
  String resendBody(String title, String peer, String size) {
    return '$title\nRecipient: $peer\n\nThe app uses the saved prepared copies ($size). You will not need to choose the originals again. The recipient gets a new request to approve. The previous attempt stays in history.';
  }

  @override
  String get sendNewRequest => 'Send new request';

  @override
  String get saveFileCopyTitle => 'Save a copy of a file';

  @override
  String get receivedInApp => 'Received in the app';

  @override
  String get pairByInvitation => 'Connect with a code';

  @override
  String get pairByInvitationHint =>
      'On the other device tap Show QR → Copy code, then paste the whole code here.';

  @override
  String get invitationText => 'Connection code';

  @override
  String get pairConnect => 'Connect';

  @override
  String get renameHint =>
      'Other devices see this name when connecting and transferring.';

  @override
  String get name => 'Name';

  @override
  String get save => 'Save';

  @override
  String disconnectQuestion(String name) {
    return 'Disconnect $name?';
  }

  @override
  String get disconnectBody =>
      'You will need to connect this device again for the next transfer.';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get invitationTitle => 'Connect a device';

  @override
  String get invitationHint =>
      'Scan this QR code with Ulash on the other device.';

  @override
  String get invitationQrSemantics => 'QR code for connecting a device';

  @override
  String get invitationExpired => 'The QR code has expired. Create a new one.';

  @override
  String invitationRemaining(String time) {
    return 'Valid for $time';
  }

  @override
  String get copied => 'Copied';

  @override
  String get copyInvitation => 'Copy code';

  @override
  String get pairOnlyIfCodeMatches =>
      'Connect only if this code matches the code on the connecting device\'s screen.';

  @override
  String get requestNoLongerActive => 'This request is no longer active.';

  @override
  String get incomingFiles => 'Incoming files';

  @override
  String offerSummary(String peer, String files, String size) {
    return '$peer · $files · $size';
  }

  @override
  String filesAndSize(String files, String size) {
    return '$files · $size';
  }

  @override
  String get offerNoLongerActive => 'This offer is no longer active.';

  @override
  String get onbTitle1 => 'Files between your devices';

  @override
  String get onbBody1 =>
      'Photos, videos and documents between your phone and computer in original quality. No cloud, no sign-up, and you approve every transfer.';

  @override
  String get onbTitle2 => 'One Wi-Fi network';

  @override
  String get onbBody2 =>
      'Your devices need to be on the same network. The system will ask to allow local network access — without it the app cannot find your devices.';

  @override
  String get onbTitle3 => 'Only with your consent';

  @override
  String get onbBody3 =>
      'A new device connects with a QR code and your approval, and you accept every incoming transfer yourself. Data is encrypted.';

  @override
  String get skip => 'Skip';

  @override
  String onbStep(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get start => 'Get started';

  @override
  String get next => 'Next';

  @override
  String get resetKeysStartupBody =>
      'New keys will be created. All previously connected devices will need to be connected again with a QR code. Received files stay on the device.';

  @override
  String get repairQuestion => 'Repair the journal?';

  @override
  String get repairBody =>
      'The damaged journal will be set aside and the app will start fresh. Transfer history from that journal becomes unavailable. If you recently downgraded the app, update it first instead.';

  @override
  String get repair => 'Repair';

  @override
  String get startupFailedTitle => 'The app could not start';

  @override
  String get repairJournal => 'Repair journal';

  @override
  String get sendDiagnostics => 'Send diagnostics log';

  @override
  String get scannerTitle => 'Connect a device';

  @override
  String get cameraUnavailable =>
      'Camera unavailable. Allow access in Settings or go back and enter the connection code manually.';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get scannerHint =>
      'Point the camera at the QR code: on the other device open Ulash → Devices → Show QR. Both devices must be on the same network.';

  @override
  String get busyPreparingStorage => 'Preparing secure storage';

  @override
  String get startupKeysFailed =>
      'Could not open the device\'s protected keys. Unlock the device and try again. If the keys were lost (for example after moving to a new phone), reset them and connect your devices again.';

  @override
  String get startupJournalFailed =>
      'The transfer journal is damaged or was created by a newer version of the app. Update the app or repair the journal.';

  @override
  String startupFailed(String reason) {
    return 'The app could not start. $reason';
  }

  @override
  String get allowLocalNetwork =>
      'Allow local network access in the app settings, then tap Refresh.';

  @override
  String get resetKeysFailed =>
      'Could not reset the keys. Restart the device and try again.';

  @override
  String get defaultNameIos => 'My iPhone';

  @override
  String get defaultNameAndroid => 'My Android';

  @override
  String get defaultNameWindows => 'My Windows PC';

  @override
  String get defaultNameLinux => 'My Linux PC';

  @override
  String get defaultNameOther => 'My device';

  @override
  String get discoveryUnavailable =>
      'Automatic discovery is unavailable. Connect with a QR code on a shared network.';

  @override
  String get saveLocationMobile =>
      'Inside the app. To save a file elsewhere, use Share or Save a copy… in History.';

  @override
  String get networkDenied =>
      'Local network access is turned off in system settings.';

  @override
  String get networkNoAddress =>
      'Connect your devices to the same Wi-Fi or Ethernet network.';

  @override
  String get networkKeepOpen =>
      'Local network · keep the app open on both devices while transferring';

  @override
  String get peerKeyVerified => 'Device key verified';

  @override
  String get peerOpenApp => 'Open the app on the other device';

  @override
  String get peerScanToConnect =>
      'Scan the QR code to connect for the first time';

  @override
  String get waitingForRecipient => 'Waiting for the recipient';

  @override
  String get busyChoosingMedia => 'Choosing photos and videos';

  @override
  String get busyChoosingFiles => 'Choosing files';

  @override
  String get pickerTitle => 'Choose files';

  @override
  String busyPreparing(String name) {
    return 'Preparing: $name';
  }

  @override
  String get waitCurrentSendOrPause =>
      'Wait for the current send to finish or pause it.';

  @override
  String get requestSent => 'Request sent. Approve it on the other device.';

  @override
  String get peerUnavailableOrRevoked =>
      'The device is unavailable or no longer trusted.';

  @override
  String get cancelRetriesExhausted =>
      'Automatic attempts ran out. The cancellation is not confirmed yet; the app will check once the recipient is reachable again.';

  @override
  String get connectionLostAutoResume =>
      'Connection lost. Confirmed progress is saved; the transfer continues automatically when the other device is back online.';

  @override
  String get connectionNotRestored =>
      'Connection not restored. Confirmed progress is saved. Open the app on both devices and tap Resume.';

  @override
  String cancelRetrying(int attempt, int max, String seconds) {
    return 'Confirming cancellation: retry $attempt of $max in $seconds s. The recipient\'s result is not known yet.';
  }

  @override
  String connectionRetrying(int attempt, int max, String seconds) {
    return 'Connection lost. Retry $attempt of $max in $seconds s. Confirmed progress is saved.';
  }

  @override
  String get senderPausedTapResume =>
      'Paused by sender. Tap Resume to continue.';

  @override
  String get recipientPaused => 'The recipient paused the transfer.';

  @override
  String get consentExpiredNewRequest =>
      'The approval window expired. A new request is needed.';

  @override
  String get receiveNotFinished =>
      'Receiving did not finish. Choose the files again to send anew.';

  @override
  String partiallySaved(int completed, int total) {
    return '$completed of $total files saved. Completed files are available to the recipient; the rest can be sent again.';
  }

  @override
  String get newRequestFromCopies =>
      'A new request was created from the saved copies. The recipient must approve it again.';

  @override
  String get senderPaused => 'Paused by sender';

  @override
  String get receiveAllowed =>
      'Receiving allowed. If the transfer stopped, tap Resume on the sender.';

  @override
  String get waitCurrentSend => 'Wait for the current send to finish.';

  @override
  String get confirmingCancel =>
      'Confirming the cancellation with the recipient.';

  @override
  String get tapResumeToConfirmCancel =>
      'Tap Resume to confirm the cancellation with the recipient.';

  @override
  String get recipientUnavailableCancel =>
      'The recipient is unavailable. The cancellation is not confirmed yet; Resume will check again.';

  @override
  String confirmPairingWithCode(String code) {
    return 'Approve the connection on the other device. This device\'s code is $code — it must match the code in the request.';
  }

  @override
  String pairedWith(String name) {
    return 'Connected: $name. You can send files now.';
  }

  @override
  String get pairingApproved =>
      'Connection approved. Waiting for pairing to finish.';

  @override
  String get pairingDeclined => 'Connection request declined.';

  @override
  String get trustRevokedCancelUnknown =>
      'Trust revoked. The remote cancellation result is not confirmed.';

  @override
  String get trustRevokedStopped => 'Trust revoked. The transfer was stopped.';

  @override
  String get deviceRenamed =>
      'Device name changed. Connected devices will see it the next time they connect.';

  @override
  String get transferDeleted => 'The transfer and its files were deleted.';

  @override
  String get recordDeleted => 'The record was removed from history.';

  @override
  String historyCleared(int count) {
    return 'Records removed: $count. Received files were kept.';
  }

  @override
  String diagnosticsSaved(String path) {
    return 'Diagnostics log saved: $path';
  }

  @override
  String get quotaSaved => 'Temporary storage limit saved.';

  @override
  String get busyCleaningCopies => 'Clearing unused copies';

  @override
  String copiesCleared(int count) {
    return 'Unused temporary copies removed: $count. Received files were kept.';
  }

  @override
  String get busyCleaningIncoming => 'Clearing unfinished incoming transfers';

  @override
  String incomingCleared(int stopped, int removed) {
    return 'Unfinished transfers processed: $stopped. Temporary files removed: $removed. Completed received files were kept.';
  }

  @override
  String get exportNotExported => 'Received into app storage';

  @override
  String get exportInProgress => 'Saving a copy…';

  @override
  String exportDone(String destination) {
    return 'Copy saved: $destination';
  }

  @override
  String get exportCancelledDetail => 'Last save was cancelled';

  @override
  String get exportFileChanged =>
      'The file was changed or moved. Saving a copy was stopped.';

  @override
  String get exportFailedDetail =>
      'Could not save a copy. The received file stays in the app.';

  @override
  String get exportUnknownDetail =>
      'The save was not confirmed. Check the chosen folder before trying again.';

  @override
  String get exportCancelled =>
      'Saving a copy was cancelled. The received file stays in the app.';

  @override
  String get cannotOpenFile =>
      'The file is saved, but no app could open it. Try Share or Save a copy….';

  @override
  String get backgroundedWillResume =>
      'The app went to the background. The transfer will continue when you return.';

  @override
  String get interruptedOnClose =>
      'The transfer stopped when the app was closed. Tap Resume to check its status with the recipient.';

  @override
  String get verifiedAndSaved => 'Verified and saved';

  @override
  String get consentNotReceived =>
      'No approval within 120 seconds. A new request is needed.';

  @override
  String partSavedTapResume(String reason) {
    return '$reason The confirmed part of the file is saved; then tap Resume.';
  }

  @override
  String get recipientPausedShort => 'Paused by recipient';

  @override
  String get consentRequired => 'Recipient approval required';

  @override
  String get someFilesUnfinished =>
      'Some files are unfinished. Verified results are saved.';

  @override
  String get receivedFilesMissing =>
      'The received files were deleted or moved outside the app.';

  @override
  String get errPeerUnavailable =>
      'The device is unavailable. Put both devices on the same network and open the app.';

  @override
  String get errQrExpired =>
      'The QR code has expired. Create a new one on the other device.';

  @override
  String get errPairingRejected =>
      'The connection was declined on the other device.';

  @override
  String get errSelfPairing => 'This QR code belongs to this device.';

  @override
  String get errUnauthorized =>
      'Trust was revoked or pairing did not finish. Connect the devices again.';

  @override
  String get errConsentRequired =>
      'The recipient has not approved yet. Approve the request and resume sending.';

  @override
  String get errOfferExpired =>
      'The offer expired. Choose files and send a new request.';

  @override
  String get errTransferPaused =>
      'The transfer is paused. It can continue once both sides remove their pause.';

  @override
  String get errHashMismatch =>
      'The checksum did not match. The file was not marked as complete.';

  @override
  String get errSourceChanged =>
      'The original file changed while it was being prepared. Choose it again.';

  @override
  String get errFileTooLarge => 'The file is larger than the 10 GB limit.';

  @override
  String get errDiskFull =>
      'Not enough free space, counting transfers in progress and the reserve. Free up space in storage settings and try again.';

  @override
  String get errTempQuotaExceeded =>
      'The temporary copy limit was reached. Clear unused copies or raise the limit in settings.';

  @override
  String get errQuotaBelowUsage =>
      'This limit is smaller than the temporary copies plus space for transfers in progress. Finish transfers or free up space first.';

  @override
  String get errCapacityUnavailable =>
      'Could not determine available space. Check again in storage settings.';

  @override
  String get errCommittedFileChanged =>
      'The received file was deleted, moved or changed. Saving a copy was stopped; check the file.';

  @override
  String get errExportFailed =>
      'Could not save an external copy. The received file stays in the app; choose another location or try again.';

  @override
  String get errExportSourceUnavailable =>
      'The received file is not available for saving a copy. Check that it was not deleted or moved.';

  @override
  String get errExportUnsupported =>
      'System saving is not supported on this device. The file stays in the app.';

  @override
  String get errExportBusy =>
      'Wait for the current save to finish or close the open system window.';

  @override
  String get errDestinationExists =>
      'A file with this name already exists. Choose another name or folder.';

  @override
  String get errRateLimited =>
      'The recipient is temporarily limiting requests. Try again in a few minutes.';

  @override
  String get errQuotaExceeded =>
      'The transfer is larger than the space available on the recipient\'s device.';

  @override
  String get errJournal =>
      'The transfer journal is unavailable. Update the app or repair the journal.';

  @override
  String get errIdentityChanged =>
      'The other device\'s key changed. Remove it from the list and connect it again.';

  @override
  String get errTransferTooSlow =>
      'The connection is too slow. The transfer was paused and will be retried.';

  @override
  String get errFileMissing =>
      'The received file was deleted or moved outside the app.';

  @override
  String get errTransferActive =>
      'Finish or cancel the transfer before deleting it.';

  @override
  String get errQueueFull =>
      'The queue is full. Finish or cancel unfinished transfers.';

  @override
  String get errBusy =>
      'The recipient is busy with another transfer. Try again later.';

  @override
  String get errNotFound =>
      'This transfer\'s data is unavailable. Check saved files or choose the source again.';

  @override
  String get errHandshake =>
      'Could not verify the device key. Check the device and pair again.';

  @override
  String get errConnectionLost =>
      'The connection was interrupted. Open the app on both devices and resume the transfer.';

  @override
  String get errFormat => 'Invalid QR code or unsupported data format.';

  @override
  String get errFileSystem =>
      'Could not read or save the file. Check access and free space.';

  @override
  String get errUnknown =>
      'Something went wrong. Try again. If the problem continues, send the diagnostics log from Settings.';

  @override
  String errWithCode(String code) {
    return 'The operation stopped (code $code). Data was not marked as transferred.';
  }

  @override
  String get statusDeviceKeysReset =>
      'Device keys were reset. Pair your devices again with a QR code.';

  @override
  String statusReceivedDone(String title) {
    return 'Files received: $title';
  }

  @override
  String statusSentDone(String title) {
    return 'Delivered: $title';
  }

  @override
  String etaLeft(String value) {
    return '$value left';
  }

  @override
  String get messageSent =>
      'Message sent. The recipient will confirm it on their device.';

  @override
  String get errMessageTooLong =>
      'The message is too long (up to 64 KB). Send it as a file instead.';

  @override
  String get journalWarningText =>
      'Some history records could not be read. Prepared copies are kept and will not be offered for cleanup.';

  @override
  String get preparationCancelled =>
      'Preparation stopped. Files already prepared stay selected.';

  @override
  String get errUrlUnavailable =>
      'Could not open the link. Make sure a browser is installed.';

  @override
  String get browserPeer => 'Browser';

  @override
  String get webUploadDetail => 'Uploaded from a browser via an Ulash link';

  @override
  String get webPageTitle => 'Files from the device';

  @override
  String get webPageDownload => 'Download';

  @override
  String get webPageNoFiles => 'No files were chosen for download.';

  @override
  String get webPageUpload => 'Send to the device';

  @override
  String get webPageChoose => 'Choose files';

  @override
  String get webPageWaiting => 'Confirm on the device…';

  @override
  String get webPageUploading => 'Uploading';

  @override
  String get webPageDone => 'Done: the files are on the device.';

  @override
  String get webPageRejected => 'The device declined the upload.';

  @override
  String get webPageFailed => 'Upload failed. Please try again.';

  @override
  String get webPageExpires => 'Link valid until';

  @override
  String get unknownDevice => 'Device';

  @override
  String get pairingCancelled => 'Pairing cancelled';

  @override
  String peerBusyRetrying(int seconds) {
    return 'The recipient is busy. Retrying in $seconds s.';
  }

  @override
  String get errFoldersUnsupported =>
      'The other device runs an older Ulash that cannot receive folders. Update it there or choose individual files.';

  @override
  String get errFolderTooLarge =>
      'The folder has more than 1,000 files. Choose a smaller folder.';

  @override
  String get errFolderPath =>
      'The folder is nested too deeply or has unsupported names. Choose a subfolder or individual files.';

  @override
  String get errFolderEmpty => 'The chosen folder has no files.';

  @override
  String get errNearbyUnavailable =>
      'The device is no longer waiting to connect. Ask to open its connect screen again.';

  @override
  String get errPhotosDenied =>
      'No access to Photos. Allow adding photos in Settings.';

  @override
  String get errPhotosFailed =>
      'Could not save to Photos. The file is still in Ulash.';

  @override
  String get savedToPhotos => 'Saved to Photos';

  @override
  String get errOpenBlocked =>
      'This is a program or script, and Ulash does not run such files. Open the folder and run it yourself if you trust the sender.';

  @override
  String get saveLocationFiles => 'Files app → On My iPhone → Ulash';

  @override
  String intakeAdded(int count) {
    return 'Added from another app: $count';
  }

  @override
  String get errTooManyFiles =>
      'Up to 1,000 files can be sent at once. Remove some from the list.';

  @override
  String get moreActions => 'More';

  @override
  String get copyAction => 'Copy';

  @override
  String get textCopied => 'Copied';

  @override
  String get sendLead =>
      'Photos, videos and documents in original quality, straight over Wi-Fi.';

  @override
  String get folder => 'Folder';

  @override
  String get textMessage => 'Text';

  @override
  String get addMore => 'Add more';

  @override
  String get sendTo => 'To';

  @override
  String sendToDevice(String name) {
    return 'Send to $name';
  }

  @override
  String get addFilesFirst => 'Add files';

  @override
  String get noAppLink => 'No Ulash on the other device? Send a link';

  @override
  String get firstDeviceTitle => 'Connect your first device';

  @override
  String get firstDeviceBody =>
      'Open Ulash on the second device on the same Wi-Fi and scan the QR code. You only do this once.';

  @override
  String get activeTransfers => 'In progress';

  @override
  String get messageTitle => 'Message';

  @override
  String get messageHint => 'Text or link';

  @override
  String get chooseRecipientFirst => 'Choose a recipient first.';

  @override
  String selectedSummary(String files, String size) {
    return '$files · $size';
  }

  @override
  String get searchHint => 'Search by name or device';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get nothingFound => 'Nothing found';

  @override
  String get saveToPhotos => 'Save to Photos';

  @override
  String get revealInFolder => 'Show in folder';

  @override
  String get executableTitle => 'Open a program?';

  @override
  String executableBody(String name) {
    return '“$name” can run a program on this device. Open such files only if you trust the sender.';
  }

  @override
  String get openAnyway => 'Open anyway';

  @override
  String folderLabel(String name) {
    return 'Folder “$name”';
  }

  @override
  String get receiveFiles => 'Receive files';

  @override
  String get receiveHintOn =>
      'Your devices can send files here — you approve every transfer.';

  @override
  String get receiveHintOff =>
      'Receiving is off: this device is hidden from others.';

  @override
  String get deviceCode => 'Device code';

  @override
  String get showQr => 'Show QR';

  @override
  String get noCameraEnterCode => 'No camera? Enter a code';

  @override
  String get connectFooter =>
      'Open Ulash on the other device on the same Wi-Fi. You connect only once.';

  @override
  String get nearby => 'Nearby';

  @override
  String get nearbyFooter =>
      'Devices on this network that have the connection screen open.';

  @override
  String get waitingRequests => 'Connection requests';

  @override
  String get qrHint => 'On the other device open Ulash → Devices → Scan QR.';

  @override
  String get qrNearbyVisible =>
      'While this screen is open, this device is visible nearby and can be connected without QR.';

  @override
  String get codesMatchTitle => 'Do the codes match?';

  @override
  String sasHostBody(String name) {
    return 'Compare with the code on “$name”. Connect only if the codes are the same.';
  }

  @override
  String get sasJoinerTitle => 'Confirm on the other device';

  @override
  String sasJoinerBody(String name) {
    return '“$name” should show the same code. Tap Connect there.';
  }

  @override
  String get codesMatch => 'Yes, connect';

  @override
  String get codesDiffer => 'Codes differ';

  @override
  String get webShareEntry => 'Via link';

  @override
  String get webShareTitle => 'Send via link';

  @override
  String get webShareBody =>
      'Open the link in a browser on a device on the same Wi-Fi — for example, a computer without Ulash.';

  @override
  String get webShareInsecure =>
      'The link works without encryption (HTTP). Use it only on your own network and stop it when you are done.';

  @override
  String get webShareAllowUpload => 'Allow uploads to this device';

  @override
  String webShareValid(String time) {
    return 'Link valid until $time';
  }

  @override
  String webShareStats(int clients, int downloads, int uploads) {
    return 'Opened: $clients · downloaded: $downloads · uploaded: $uploads';
  }

  @override
  String get webShareCreate => 'Create link';

  @override
  String get webShareStop => 'Stop';

  @override
  String get copyLink => 'Copy link';

  @override
  String get webShareSelectFirst =>
      'The link serves the selected files. Choose files or allow uploads.';

  @override
  String get webShareQrSemantics => 'QR code of the browser link';

  @override
  String get receiving => 'Receiving';

  @override
  String get autoSaveToPhotos => 'Save photos and videos to Photos';

  @override
  String get autoSaveHint =>
      'Received photos and videos appear in your library right away.';

  @override
  String get theme => 'Theme';

  @override
  String get support => 'Support';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get howDataHandled => 'How your data is handled';

  @override
  String get advanced => 'Advanced';

  @override
  String get advancedHint => 'Storage, diagnostics, key reset';

  @override
  String get about => 'About';

  @override
  String get dangerZone => 'Security';

  @override
  String get onbAllowTitle => 'Allow local network access';

  @override
  String get onbAllowBody =>
      'Ulash looks for your devices only on your Wi-Fi. Without this permission your devices can’t find each other.';

  @override
  String get allowAccess => 'Allow access';

  @override
  String get webUploadTitle => 'Upload from a browser';

  @override
  String webUploadBody(String client, String files, String size) {
    return '$client wants to upload $files ($size) here.';
  }

  @override
  String get allow => 'Allow';

  @override
  String waitingForApprovalOn(String name) {
    return 'Waiting for approval on $name';
  }

  @override
  String connectedTo(String name) {
    return 'Connected to $name';
  }

  @override
  String get shareSheetLink => 'Link';

  @override
  String get nearbyEmpty =>
      'Nobody nearby yet. On the other device open Devices → Show QR.';

  @override
  String get noDevicesYet => 'No connected devices yet';

  @override
  String get filterText => 'Text';

  @override
  String get saveDestination => 'Save to';

  @override
  String get largeTextSample => 'Text size follows your device settings.';
}
