import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:even_up_app/core/config.dart';
import 'package:even_up_app/core/user_session.dart';
import 'package:even_up_app/features/auth/login_screen.dart';
import 'package:even_up_app/features/friends/friend_requests_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  @override
  void initState() {
    super.initState();
    _fetchRequestsCount();
  }

  Future<void> _fetchRequestsCount() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/friend-requests'),
        headers: UserSession.instance.authHeaders,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        UserSession.instance.setPendingRequestCount(data.length);
      }
    } catch (e) {
      debugPrint('Error fetching requests: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isFirst = true;
    final session = UserSession.instance;
    final initials = session.name.isNotEmpty
        ? session.name.trim().split(' ').map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').take(2).join()
        : '?';

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Account'),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 32),

            // Avatar + Name
            Center(
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: CupertinoColors.activeBlue.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: CupertinoColors.activeBlue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    session.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    session.email,
                    style: const TextStyle(
                      color: CupertinoColors.secondaryLabel,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${session.userId}',
                    style: const TextStyle(
                      color: CupertinoColors.tertiaryLabel,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            CupertinoListSection.insetGrouped(
              header: const Text('Preferences'),
              children: [
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.bell_fill, color: CupertinoColors.systemOrange),
                  title: const Text('Notifications'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {},
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.globe, color: CupertinoColors.systemBlue),
                  title: const Text('Currency'),
                  trailing: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('₹ INR', style: TextStyle(color: CupertinoColors.secondaryLabel)),
                      SizedBox(width: 6),
                      CupertinoListTileChevron(),
                    ],
                  ),
                  onTap: () {},
                ),
              ],
            ),

            CupertinoListSection.insetGrouped(
              header: const Text('Account'),
              children: [
                ListenableBuilder(
                  listenable: UserSession.instance,
                  builder: (context, _) {
                    final count = UserSession.instance.pendingRequestCount ?? 0;
                    return CupertinoListTile(
                      leading: const Icon(CupertinoIcons.person_badge_plus_fill, color: CupertinoColors.activeGreen),
                      title: const Text('Friend Requests'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (count > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: CupertinoColors.destructiveRed,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: const TextStyle(color: CupertinoColors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          const SizedBox(width: 4),
                          const CupertinoListTileChevron(),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(builder: (_) => const FriendRequestsScreen()),
                        ).then((_) => _fetchRequestsCount());
                      },
                    );
                  },
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.info_circle_fill, color: CupertinoColors.systemGrey),
                  title: const Text('About EvenUp'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {},
                ),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.square_arrow_left,
                    color: CupertinoColors.destructiveRed,
                  ),
                  title: const Text(
                    'Sign Out',
                    style: TextStyle(color: CupertinoColors.destructiveRed),
                  ),
                  onTap: () {
                    showCupertinoDialog(
                      context: context,
                      builder: (ctx) => CupertinoAlertDialog(
                        title: const Text('Sign Out'),
                        content: const Text('Are you sure you want to sign out?'),
                        actions: [
                          CupertinoDialogAction(
                            child: const Text('Cancel'),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                          CupertinoDialogAction(
                            isDestructiveAction: true,
                            onPressed: () {
                              Navigator.pop(ctx);
                              UserSession.instance.logout();
                              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                                CupertinoPageRoute(builder: (_) => const LoginScreen()),
                                (_) => false,
                              );
                            },
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
