/*
 * ============================================================================
 * ONE-TIME SUPABASE SETUP — owner runs this ONCE in the Supabase
 * Dashboard -> SQL Editor (project used by TJ Pro). Nothing in the
 * app creates the table; until this SQL has run, the app silently
 * keeps the remote-config / bundled banner (by design).
 *
 * Admin identity in this app: the signed-in user's email, checked
 * server-side by the `tjpro-is-admin` Edge Function against its
 * admin list (mirrored for DISPLAY in SupabaseService.adminEmails).
 * The write policies below use the SAME three admin emails via
 * auth.jwt(), so only those signed-in accounts can write; everyone
 * (including signed-out users, via the anon key) can READ, because
 * the banner is public content shown to all users.
 *
 * ----------------------------------------------------------------------------
 * create table if not exists public.tjpro_admin_banner (
 *   id         int primary key,
 *   image_url  text not null default '',
 *   link_url   text not null default '',
 *   enabled    boolean not null default true,
 *   updated_at timestamptz not null default now()
 * );
 *
 * insert into public.tjpro_admin_banner (id, image_url, link_url, enabled)
 * values (1, '', '', true)
 * on conflict (id) do nothing;
 *
 * alter table public.tjpro_admin_banner enable row level security;
 *
 * drop policy if exists tjpro_admin_banner_public_read
 *   on public.tjpro_admin_banner;
 * create policy tjpro_admin_banner_public_read
 *   on public.tjpro_admin_banner
 *   for select
 *   using (true);
 *
 * drop policy if exists tjpro_admin_banner_admin_insert
 *   on public.tjpro_admin_banner;
 * create policy tjpro_admin_banner_admin_insert
 *   on public.tjpro_admin_banner
 *   for insert
 *   with check (
 *     (auth.jwt() ->> 'email') in (
 *       'mithubhattijani@gmail.com',
 *       'ghulamjillani019@gmail.com',
 *       'jaanirecords2@gmail.com'
 *     )
 *   );
 *
 * drop policy if exists tjpro_admin_banner_admin_update
 *   on public.tjpro_admin_banner;
 * create policy tjpro_admin_banner_admin_update
 *   on public.tjpro_admin_banner
 *   for update
 *   using (
 *     (auth.jwt() ->> 'email') in (
 *       'mithubhattijani@gmail.com',
 *       'ghulamjillani019@gmail.com',
 *       'jaanirecords2@gmail.com'
 *     )
 *   )
 *   with check (
 *     (auth.jwt() ->> 'email') in (
 *       'mithubhattijani@gmail.com',
 *       'ghulamjillani019@gmail.com',
 *       'jaanirecords2@gmail.com'
 *     )
 *   );
 * ----------------------------------------------------------------------------
 * NOTE: if the admin list ever changes, update BOTH the
 * `tjpro-is-admin` Edge Function AND these two write policies —
 * they must stay in step.
 * ============================================================================
 */

/// Admin banner editor — sets/changes the Advertise page's house-ad
/// banner (image + link) in Supabase, live with NO new build.
///
/// Reached only from the admin-only "Edit banner" button on the
/// Advertise screen, and this screen re-checks the same server-fed
/// flag itself ([AuthService.isAdmin], fed solely by
/// [SupabaseService.checkIsAdmin] -> the `tjpro-is-admin` Edge
/// Function; fail closed). Saving upserts the single row (id = 1) of
/// `tjpro_admin_banner`; [RemoteConfigService] reads that row after
/// its remote-JSON config resolves and lets it override the banner
/// image + link. The one-time CREATE TABLE + RLS SQL the owner must
/// run first is in the comment block at the top of this file.
///
/// Preview rule (same as the Advertise page): [BoxFit.contain] on a
/// neutral background — any image, portrait or landscape, fits
/// FULLY inside the banner box, never cropped.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';

class AdminBannerScreen extends StatefulWidget {
  const AdminBannerScreen({super.key});

  @override
  State<AdminBannerScreen> createState() => _AdminBannerScreenState();
}

class _AdminBannerScreenState extends State<AdminBannerScreen> {
  final TextEditingController _imageController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();

  bool _enabled = true;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    // Prefill with the values the app is CURRENTLY showing (the
    // Supabase override when one is active, otherwise the
    // remote-config / bundled banner + link).
    final config = RemoteConfigService.instance.config;
    _imageController.text = config.advertisingBannerImageUrl;
    _linkController.text = config.advertisingBannerLinkUrl;
    _enabled = true;
    // Live preview follows the text fields as the admin types.
    _imageController.addListener(_onTextChanged);
    _linkController.addListener(_onTextChanged);
    // Re-confirm admin status from the server while the screen is
    // open (the flag may still have been loading at startup).
    unawaited(AuthService.refreshAdminStatus());
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _imageController.removeListener(_onTextChanged);
    _linkController.removeListener(_onTextChanged);
    _imageController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    // Admin check (real API): the server-fed flag only — never a
    // local email list. Fail closed with a plain message.
    if (!AuthService.isAdmin.value) {
      setState(() {
        _error = 'Cannot save: this account is not an admin '
            '(server check fail).';
        _success = null;
      });
      return;
    }
    if (!SupabaseService.isInitialized) {
      setState(() {
        _error = 'Cannot save: Supabase is not connected right now '
            'it is. Check the internet and try again.';
        _success = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    final imageUrl = _imageController.text.trim();
    final linkUrl = _linkController.text.trim();
    try {
      await SupabaseService.client
          .from(RemoteConfigService.adminBannerTable)
          .upsert(<String, dynamic>{
            'id': RemoteConfigService.adminBannerRowId,
            'image_url': imageUrl,
            'link_url': linkUrl,
            'enabled': _enabled,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      // Show the failure plainly — no silent swallow here (unlike
      // the read path): the admin must know the save did not land,
      // e.g. because the one-time table/RLS SQL has not been run.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Save failed: $e';
      });
      return;
    }
    // Reflect the saved banner in this session at once; every other
    // install picks it up on its next config resolution.
    RemoteConfigService.instance.applyAdminBannerOverride(
      enabled: _enabled,
      imageUrl: imageUrl,
      linkUrl: linkUrl,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _success = _enabled && imageUrl.isNotEmpty
          ? 'Banner saved — this banner is now live in the app '
              'it is, without any new build.'
          : 'Saved — the override is OFF, so the app has returned '
              'to the remote-config banner.';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Banner saved.')),
    );
  }

  Widget _buildPreview() {
    final url = _imageController.text.trim();
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? const Center(
              child: Text(
                'Image URL daalein — preview yahan aayega.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : url.startsWith('assets/')
              ? Image.asset(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(
                    child: Text(
                      'Preview did not load.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(
                    child: Text(
                      'Preview did not load.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Banner (Admin)')),
      body: ValueListenableBuilder<bool>(
        valueListenable: AuthService.isAdmin,
        builder: (context, isAdmin, _) {
          if (!isAdmin) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This page is for admins only.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Live preview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Any image — portrait or landscape — will fit fully '
                  'will fit, never cropped.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 8),
                _buildPreview(),
                const SizedBox(height: 16),
                TextField(
                  controller: _imageController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Banner image URL',
                    hintText: 'https://…/banner.jpg',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _linkController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Banner link URL (tap par khulega)',
                    hintText: 'https://… (empty = no link)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _enabled,
                  onChanged: (value) =>
                      setState(() => _enabled = value),
                  title: const Text('Banner override ON'),
                  subtitle: const Text(
                    'Turning it OFF returns the app to the remote-config / default '
                    'banner.',
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  key: const Key('adminBannerSaveButton'),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save banner'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.red,
                    ),
                  ),
                ],
                if (_success != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _success!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
