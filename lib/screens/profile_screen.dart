import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/cloudinary_service.dart';
import '../services/user_service.dart';
import '../widgets/avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _about = TextEditingController();
  String _uid = '', _email = '';
  String? _photoUrl;
  bool _loaded = false, _saving = false, _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Future<void> _load() async {
    final me = FirebaseAuth.instance.currentUser!;
    _uid = me.uid;
    _email = me.email ?? '';
    final snap = await FirebaseFirestore.instance.collection('users').doc(me.uid).get();
    final data = snap.data();
    final user = data == null ? null : AppUser.fromMap(data);
    _name.text = user?.name ?? me.displayName ?? '';
    _about.text = user?.about ?? '';
    _photoUrl = user?.photoUrl;
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _pickPhoto() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null || picked.path == null) return;
    setState(() => _uploading = true);
    try {
      final url = await CloudinaryService.upload(File(picked.path!), name: picked.name);
      await UserService.instance.setPhoto(url);
      if (mounted) setState(() => _photoUrl = url);
    } catch (_) {
      if (mounted) _toast('Could not upload the photo.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await UserService.instance.updateProfile(name: _name.text, about: _about.text);
      if (mounted) {
        _toast('Profile updated');
        Navigator.of(context).maybePop();
      }
    } catch (_) {
      if (mounted) _toast('Could not save. Check your connection.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: !_loaded
            ? const Center(key: ValueKey('loading'), child: CircularProgressIndicator())
            : SingleChildScrollView(
                key: const ValueKey('form'),
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _uploading ? null : _pickPhoto,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            UserAvatar(
                              uid: _uid,
                              name: _name.text,
                              photoUrl: _photoUrl,
                              radius: 62,
                              hero: false,
                            ),
                            if (_uploading)
                              const SizedBox(
                                width: 124,
                                height: 124,
                                child: CircularProgressIndicator(strokeWidth: 3),
                              ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: cs.primary,
                                child: Icon(Icons.camera_alt_rounded, size: 20, color: cs.onPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _about,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'About',
                          prefixIcon: Icon(Icons.info_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        initialValue: _email,
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                          suffixIcon: Icon(Icons.lock_outline_rounded),
                          helperText: "Your email can't be changed",
                        ),
                      ),
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _saving
                              ? const SizedBox(
                                  key: ValueKey('spin'),
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                )
                              : const Text('Save', key: ValueKey('save')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
