import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class ProfileBlockedUsersScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const ProfileBlockedUsersScreen({
    super.key,
    required this.userData,
  });

  @override
  State<ProfileBlockedUsersScreen> createState() => _ProfileBlockedUsersScreenState();
}

class _ProfileBlockedUsersScreenState extends State<ProfileBlockedUsersScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _blocked = <Map<String, dynamic>>[];

  final TextEditingController _searchCtrl = TextEditingController();
  bool _searching = false;
  String? _searchError;
  List<Map<String, dynamic>> _searchResults = <Map<String, dynamic>>[];

  int? get _userId {
    final v = widget.userData['id'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  Future<void> _searchUsers() async {
    final userId = _userId;
    if (userId == null) return;
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _searching = false;
        _searchError = null;
        _searchResults = <Map<String, dynamic>>[];
      });
      return;
    }

    setState(() {
      _searching = true;
      _searchError = null;
    });

    try {
      final res = await ApiService.searchUsersToBlock(userId: userId, query: q);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchResults = res;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = e.toString();
        _searchResults = <Map<String, dynamic>>[];
      });
    }
  }

  Future<void> _block(int blockedUserId) async {
    final userId = _userId;
    if (userId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await ApiService.blockUser(userId: userId, blockedUserId: blockedUserId);
    if (!mounted) return;

    if (res['success'] == true) {
      _searchCtrl.clear();
      setState(() {
        _searchResults = <Map<String, dynamic>>[];
        _searchError = null;
      });
      await _load();
    } else {
      setState(() {
        _loading = false;
        _error = (res['error'] ?? 'Failed to block user').toString();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'User ID not found';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await ApiService.getBlockedUsers(userId: userId);
      if (!mounted) return;
      setState(() {
        _blocked = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _unblock(int blockedUserId) async {
    final userId = _userId;
    if (userId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await ApiService.unblockUser(
      userId: userId,
      blockedUserId: blockedUserId,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      await _load();
    } else {
      setState(() {
        _loading = false;
        _error = (res['error'] ?? 'Failed to unblock user').toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Users'),
        backgroundColor: const Color(0xFF00897B),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchUsers(),
              decoration: InputDecoration(
                hintText: 'Search users to block (name / username / email / phone)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _searchResults = <Map<String, dynamic>>[];
                            _searchError = null;
                          });
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: (_) {
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _searching ? null : _searchUsers,
                icon: _searching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.person_search, color: Colors.white),
                label: const Text('Search'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (_searchError != null) ...[
              const SizedBox(height: 10),
              Text(_searchError!, style: const TextStyle(color: Colors.red)),
            ],
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Results', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ..._searchResults.map((u) {
                final id = u['id'];
                final uid = id is int ? id : int.tryParse(id?.toString() ?? '');
                final name = (u['name'] ?? 'User').toString();
                final username = (u['username'] ?? '').toString();
                final email = (u['email'] ?? '').toString();
                final phone = (u['phone_no'] ?? '').toString();
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(name),
                    subtitle: Text([
                      if (username.isNotEmpty) '@$username',
                      if (email.isNotEmpty) email,
                      if (phone.isNotEmpty) phone,
                    ].join('\n')),
                    trailing: ElevatedButton(
                      onPressed: uid == null ? null : () => _block(uid),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
                      child: const Text('Block', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 18),
            const Text('Blocked users', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (!_loading && _error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(_error!),
              ),
            if (!_loading && _error == null && _blocked.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('No blocked users.')),
              ),
            if (!_loading && _error == null && _blocked.isNotEmpty)
              ..._blocked.map((item) {
                final blockedUser = item['blocked_user'] is Map
                    ? Map<String, dynamic>.from(item['blocked_user'] as Map)
                    : <String, dynamic>{};
                final id = blockedUser['id'];
                final blockedUserId = id is int ? id : int.tryParse(id?.toString() ?? '');
                final name = (blockedUser['name'] ?? 'User').toString();
                final username = (blockedUser['username'] ?? '').toString();
                final reason = (item['reason'] ?? '').toString();

                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(name),
                    subtitle: Text(
                      [
                        if (username.isNotEmpty) '@$username',
                        if (reason.isNotEmpty) 'Reason: $reason',
                      ].join('\n'),
                    ),
                    isThreeLine: reason.isNotEmpty,
                    trailing: ElevatedButton(
                      onPressed: blockedUserId == null ? null : () => _unblock(blockedUserId),
                      child: const Text('Unblock'),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
