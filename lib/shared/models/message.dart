enum MessageType      { text, image, video, audio, file }
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
  final bool             forwarded;
  final bool             viewOnce;
  final String?          fileUrl;
  final String?          fileName;
  final int?             fileSize;
  final Map<String, String>? reactions;

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
    this.forwarded  = false,
    this.viewOnce   = false,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.reactions,
  });

  XameMessage copyWith({String? status, Map<String, String>? reactions}) => XameMessage(
    id:             id,
    senderId:       senderId,
    recipientId:    recipientId,
    text:           text,
    type:           type,
    direction:      direction,
    ts:             ts,
    status:         status ?? this.status,
    isDisappearing: isDisappearing,
    expiresAt:      expiresAt,
    replyToId:      replyToId,
    replyToText:    replyToText,
    forwarded:      forwarded,
    viewOnce:       viewOnce,
    fileUrl:        fileUrl,
    fileName:       fileName,
    fileSize:       fileSize,
    reactions:      reactions ?? this.reactions,
  );

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(ts);
  bool get isSent       => direction == MessageDirection.sent;
  bool get isReceived   => direction == MessageDirection.received;
}
