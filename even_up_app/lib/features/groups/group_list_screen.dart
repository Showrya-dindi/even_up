import 'package:flutter/cupertino.dart';

class GroupListScreen extends StatelessWidget {
  const GroupListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Groups'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.add),
          onPressed: () {
            // TODO: Create group
          },
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              header: const Text('Your Groups'),
              children: [
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.group,
                    color: CupertinoColors.systemOrange,
                  ),
                  title: const Text('Trip to Paris'),
                  subtitle: const Text('You are owed ₹120.00'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {},
                ),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.house_fill,
                    color: CupertinoColors.systemGreen,
                  ),
                  title: const Text('Roommates'),
                  subtitle: const Text('You owe ₹45.50'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
