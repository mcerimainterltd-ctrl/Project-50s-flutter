import sys

with open('lib/screens/xame_pay_screen.dart', 'r') as f:
    content = f.read()

old = """              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: 'https://nigerianbanks.xyz/logo/indulge-microfinance-bank.png',
                    width: 48, height: 48, fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B3A5C),
                        borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('I',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w800, fontSize: 22)))),
                  ),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Indulge MFB',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const Text('Virtual Account',
                      style: TextStyle(color: _kMuted, fontSize: 11)),
                ]),
              ]),"""

new = """              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: 'https://nigerianbanks.xyz/logo/' +
                        (_account!["bank_name"] ?? "").toString().toLowerCase()
                            .replaceAll(' ', '-') + '.png',
                    width: 48, height: 48, fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B3A5C),
                        borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text(
                          ((_account!["bank_name"] ?? "B") as String).isNotEmpty
                              ? (_account!["bank_name"] as String)[0].toUpperCase()
                              : 'B',
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w800, fontSize: 22)))),
                  ),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_account!["bank_name"]?.toString() ?? "Bank",
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const Text('Virtual Account',
                      style: TextStyle(color: _kMuted, fontSize: 11)),
                ]),
              ]),"""

c = content.count(old)
if c != 1:
    print(f"ERROR: expected 1 match, found {c}. Aborting — no changes made.")
    sys.exit(1)
content = content.replace(old, new)
with open('lib/screens/xame_pay_screen.dart', 'w') as f:
    f.write(content)
print("Patch applied successfully.")
