enum MessageType      { text, image, video, audio, file, call }
enum MessageDirection { sent, received }

class XameMessage {
  final String           id;
  final String           senderId;
  final String           recipientId;
  final String           text;
  final MessageType      type;
  final MessageDirection direction;
  final int              ts;
  final String           status;
  final bool             isDisappearing;
  final int?             expiresAt;
  final String?          replyToId;
  final String?          replyToText;
  final String?          replyToFileUrl;
  final String?          replyToFileMime;
  final bool             forwarded;
  final bool             viewOnce;
  final String?          fileUrl;
  final String?          fileName;
  final String?          fileMime;
  final int?             fileSize;
  final String?          localPath;  // local device path — open without download
  final Map<String, String>? reactions;
  final bool             isDeleted;
  final String?          callType;      // 'voice' | 'video'
  final String?          callStatus;    // 'ended' | 'no-answer'
  final int?             callDuration;  // seconds
  final Map<String, dynamic>? actionButton; // {label, url} tappable button for system messages
  final String?          albumId;       // groups multi-image picks sent together
  final int?             albumIndex;    // position within the album (0-based)
  final int?             albumTotal;    // total images in this album

  const XameMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.text,
    required this.type,
    required this.direction,
    required this.ts,
    required this.status,
    this.isDisappearing = false,
    this.expiresAt,
    this.replyToId,
    this.replyToText,
    this.replyToFileUrl,
    this.replyToFileMime,
    this.forwarded  = false,
    this.viewOnce   = false,
    this.fileUrl,
    this.fileName,
    this.fileMime,
    this.fileSize,
    this.localPath,
    this.reactions,
    this.isDeleted  = false,
    this.callType,
    this.callStatus,
    this.callDuration,
    this.actionButton,
    this.albumId,
    this.albumIndex,
    this.albumTotal,
  });

XameMessage copyWith({String? status, Map<String, String>? reactions, String? localPath, bool? isDeleted, String? callType, String? callStatus, int? callDuration}) => XameMessage(
    id:             id,             senderId:      senderId,
    recipientId:    recipientId,    text:          text,
    type:           type,           direction:     direction,
    ts:             ts,             status:        status ?? this.status,
    isDisappearing: isDisappearing, expiresAt:     expiresAt,
    replyToId:      replyToId,      replyToText:   replyToText,
    replyToFileUrl: replyToFileUrl, replyToFileMime: replyToFileMime,
    forwarded:      forwarded,      viewOnce:      viewOnce,
    fileUrl:        fileUrl,        fileName:      fileName,
    fileMime:       fileMime,       fileSize:      fileSize,
    localPath:      localPath ?? this.localPath,
    reactions:      reactions ?? this.reactions,
    isDeleted:      isDeleted ?? this.isDeleted,
    callType:       callType ?? this.callType,
    callStatus:     callStatus ?? this.callStatus,
    callDuration:   callDuration ?? this.callDuration,
    actionButton:   actionButton,
    albumId:        albumId,
    albumIndex:     albumIndex,
    albumTotal:     albumTotal,
  );

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(ts);
  bool get isSent       => direction == MessageDirection.sent;
  bool get isReceived   => direction == MessageDirection.received;
}
