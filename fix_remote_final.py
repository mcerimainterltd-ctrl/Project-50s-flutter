import os

path = 'lib/core/services/webrtc_service.dart'
with open(path, 'r') as f:
    content = f.read()

# Fix A: Enhanced onTrack with Hardware Initialization
# This ensures that as soon as a track (Audio or Video) arrives, 
# the renderer is attached and the state is pushed to the UI.
old_on_track = '''    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        _remoteRenderer.srcObject = e.streams[0];
        _remoteStreamController.add(e.streams[0]);
      }
    };'''

new_on_track = '''    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        // Assign the stream to the renderer
        _remoteRenderer.srcObject = e.streams[0];
        
        // Explicitly enable all incoming tracks (Audio/Video)
        for (var track in e.streams[0].getTracks()) {
          track.enabled = true;
        }
        
        _remoteStreamController.add(e.streams[0]);
        // Trigger UI refresh
        _callStateController.add(_callState);
      }
    };'''

content = content.replace(old_on_track, new_on_track)

# Fix B: Audio Routing for Android
# We use the class variable 'isIncomingVideo' to decide if speakerphone should be on.
if 'Helper.setSpeakerphoneOn' not in content:
    content = content.replace(
        '_callState = CallState.active; _callStateController.add(CallState.active);',
        'Helper.setSpeakerphoneOn(isIncomingVideo); _callState = CallState.active; _callStateController.add(CallState.active);'
    )

with open(path, 'w') as f:
    f.write(content)
