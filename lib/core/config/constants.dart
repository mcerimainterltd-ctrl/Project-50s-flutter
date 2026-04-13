class AppConstants {
  static const serverUrl             = 'https://project-50s.onrender.com';
  static const appVersion            = '2.1';
  static const keyUser               = 'xame:user';
  static const keyContacts           = 'xame:contacts';
  static const keyDrafts             = 'xame:drafts';
  static const keySettings           = 'xame:settings';
  static const keySessionToken       = 'xame:sessionToken';
  static const keyStealth            = 'xame:stealth';
  static String keyChat(String id)   => 'xame:chat:$id';
  static const maxFileSizeBytes      = 500 * 1024 * 1024;
  static const maxReconnectAttempts  = 10;
  static const reconnectBaseDelayMs  = 1500;
  static const heartbeatIntervalMs   = 30000;
  static const offlineGracePeriodMs  = 10000;
  static const callTimeoutSeconds    = 60;
  static const stealthHeartbeatMs    = 8000;
  static const messagePageSize       = 100;
  static const apiSearchUser         = '$serverUrl/api/search-user';
  static const apiAddContact         = '$serverUrl/api/add-contact';
  static const apiSetPassword        = '$serverUrl/api/set-password';
  static const apiSessionKill        = '$serverUrl/api/sessions/kill';
  static const channelAndroidBridge  = 'com.xamepage.app/android_bridge';
  static const iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {
      'urls':       'turn:openrelay.metered.ca:80',
      'username':   'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];
  static const allowedImageTypes    = ['image/jpeg','image/jpg','image/png','image/gif','image/webp'];
  static const allowedVideoTypes    = ['video/mp4','video/webm','video/ogg'];
  static const allowedAudioTypes    = ['audio/mpeg','audio/wav','audio/ogg','audio/webm','audio/mp4','audio/aac','audio/x-aac','audio/3gpp','audio/amr'];
  static const allowedDocumentTypes = [
    'application/pdf','application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain','text/html','application/vnd.android.package-archive',
  ];
}
