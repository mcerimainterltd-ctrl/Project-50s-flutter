#!/bin/bash

FILE="lib/features/contacts/screens/contacts_screen.dart"

# 1. Add the field declaration if not present
if ! grep -q "StreamSubscription _incomingCallSub" "$FILE"; then
  sed -i '/class _ContactsScreenState.*{/a\
  late StreamSubscription _incomingCallSub;' "$FILE"
  echo "✓ Added subscription field"
fi

# 2. Add listener inside initState (after super.initState() and before any closing brace)
if ! grep -q "incomingCall.listen" "$FILE"; then
  sed -i '/super.initState();/a\
\
  // Listen for incoming calls\
  _incomingCallSub = ref.read(socketServiceProvider).incomingCall.listen((call) {\
    ref.read(incomingCallProvider.notifier).state = call;\
    if (mounted) context.go('\''/incoming-call'\'');\
  });' "$FILE"
  echo "✓ Added listener in initState"
fi

# 3. Add cancellation in dispose (after existing dispose lines)
if ! grep -q "_incomingCallSub.cancel()" "$FILE"; then
  sed -i '/_tabCtrl.dispose();/a\
  _incomingCallSub.cancel();' "$FILE"
  echo "✓ Added cleanup in dispose"
fi

echo "✅ All injections completed safely"
