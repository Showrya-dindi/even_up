import 'package:flutter/cupertino.dart';
import 'package:even_up_app/features/dashboard/dashboard_screen.dart';
import 'package:even_up_app/features/friends/friends_screen.dart';
import 'package:even_up_app/features/genie/genie_screen.dart';
import 'package:even_up_app/features/account/account_screen.dart';
import 'package:even_up_app/features/expenses/add_expense_screen.dart';
import 'package:even_up_app/core/user_session.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CupertinoTabController _tabController = CupertinoTabController();
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(debugLabel: 'Navigator Groups'),
    GlobalKey<NavigatorState>(debugLabel: 'Navigator Friends'),
    GlobalKey<NavigatorState>(debugLabel: 'Navigator Add'),
    GlobalKey<NavigatorState>(debugLabel: 'Navigator Genie'),
    GlobalKey<NavigatorState>(debugLabel: 'Navigator Account'),
  ];

  // Getter to prevent crashes during hot-reload when existing tab views
  // still refer to the old variable name.
  List<Widget> get _screens => _buildScreens();

  @override
  void initState() {
    super.initState();
    UserSession.instance.refreshPendingRequestCount();
  }

  List<Widget> _buildScreens() {
    return [
      const DashboardScreen(),
      const FriendsScreen(),
      AddExpenseScreen(tabController: _tabController),
      const GenieScreen(),
      const AccountScreen(),
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTap(int index) {
    if (_tabController.index == index) {
      // Tapping the already selected tab: Pop to root
      _navigatorKeys[index].currentState?.popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      controller: _tabController,
      tabBar: CupertinoTabBar(
        onTap: _onTap,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.group),
            label: 'Groups',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_2),
            label: 'Friends',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.add_circled_solid, size: 32),
            label: 'Add',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.sparkles, size: 32),
            label: 'Genie',
          ),
          BottomNavigationBarItem(
            icon: ListenableBuilder(
              listenable: UserSession.instance,
              builder: (context, _) {
                final count = UserSession.instance.pendingRequestCount;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(CupertinoIcons.person_circle),
                    if (count > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: CupertinoColors.destructiveRed,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            label: 'Account',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          key: ValueKey('TabView_$index'),
          navigatorKey: _navigatorKeys[index],
          builder: (context) => _buildScreens()[index],
        );
      },
    );
  }
}
