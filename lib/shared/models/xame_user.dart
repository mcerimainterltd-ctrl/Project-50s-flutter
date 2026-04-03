class XameUser {
  final String  xameId;
  final String  firstName;
  final String  lastName;
  final String? email;
  final String? phone;
  final String? profilePic;
  final String? preferredName;
  final bool    hideProfilePicture;
  final bool    hidePreferredName;
  final String? personalStatusEmoji;
  final String? personalStatusMessage;
  final String? sessionToken;

  const XameUser({
    required this.xameId,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    this.profilePic,
    this.preferredName,
    this.hideProfilePicture = false,
    this.hidePreferredName  = false,
    this.personalStatusEmoji,
    this.personalStatusMessage,
    this.sessionToken,
  });

  String get fullName    => '$firstName $lastName';
  String get displayName => preferredName?.isNotEmpty == true ? preferredName! : firstName;
  String get statusText  => [personalStatusEmoji, personalStatusMessage]
      .where((s) => s?.isNotEmpty == true).join(' ');

  factory XameUser.fromMap(Map<String, dynamic> m) => XameUser(
    xameId:                m['xameId']            as String,
    firstName:             m['firstName']          as String? ?? '',
    lastName:              m['lastName']           as String? ?? '',
    email:                 m['email']              as String?,
    phone:                 m['phone']              as String?,
    profilePic:            m['profilePic']         as String?,
    preferredName:         m['preferredName']      as String?,
    hideProfilePicture:    m['hideProfilePicture'] as bool? ?? false,
    hidePreferredName:     m['hidePreferredName']  as bool? ?? false,
    personalStatusEmoji:   m['personalStatus']?['emoji']   as String?,
    personalStatusMessage: m['personalStatus']?['message'] as String?,
    sessionToken:          m['sessionToken']       as String?,
  );

  Map<String, dynamic> toMap() => {
    'xameId':             xameId,
    'firstName':          firstName,
    'lastName':           lastName,
    'email':              email,
    'phone':              phone,
    'profilePic':         profilePic,
    'preferredName':      preferredName,
    'hideProfilePicture': hideProfilePicture,
    'hidePreferredName':  hidePreferredName,
    'personalStatus': {
      'emoji':   personalStatusEmoji,
      'message': personalStatusMessage,
    },
  };
}
