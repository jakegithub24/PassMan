import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vault_item.dart';
import '../providers/vault_providers.dart';
import '../theme/app_theme.dart';
import '../utils/password_generator.dart';

/// Form screen / dialog for creating or updating an encrypted vault entry
class AddEditEntryScreen extends ConsumerStatefulWidget {
  final VaultItem? initialItem;
  final ValueChanged<VaultItem>? onSaved;
  final ValueChanged<VaultItem>? onDeleted;

  const AddEditEntryScreen({
    super.key,
    this.initialItem,
    this.onSaved,
    this.onDeleted,
  });

  @override
  ConsumerState<AddEditEntryScreen> createState() => _AddEditEntryScreenState();
}

class _AddEditEntryScreenState extends ConsumerState<AddEditEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _urlController;
  late final TextEditingController _notesController;

  late String _selectedCategory;
  bool _obscurePassword = true;
  bool _isSaving = false;
  double _passwordStrength = 0.0;

  bool get isEditing => widget.initialItem != null;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;

    _titleController = TextEditingController(text: item?.title ?? '');
    _usernameController = TextEditingController(text: item?.username ?? '');
    _passwordController = TextEditingController(text: item?.password ?? '');
    _urlController = TextEditingController(text: item?.url ?? '');
    _notesController = TextEditingController(text: item?.notes ?? '');
    _selectedCategory = item?.category ?? 'logins';

    _passwordStrength = PasswordGenerator.calculateStrength(_passwordController.text);
    _passwordController.addListener(_updatePasswordStrength);
  }

  void _updatePasswordStrength() {
    setState(() {
      _passwordStrength = PasswordGenerator.calculateStrength(_passwordController.text);
    });
  }

  @override
  void dispose() {
    _passwordController.removeListener(_updatePasswordStrength);
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _generatePassword() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PasswordGeneratorSheet(
        onPasswordGenerated: (generated) {
          _passwordController.text = generated;
          setState(() {
            _obscurePassword = false;
          });
        },
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final notifier = ref.read(vaultStateProvider.notifier);

    if (isEditing) {
      final updated = widget.initialItem!.copyWith(
        title: _titleController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        url: _urlController.text.trim().isNotEmpty ? _urlController.text.trim() : null,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        category: _selectedCategory,
      );

      final success = await notifier.updateEntry(updated);
      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        if (success) {
          if (widget.onSaved != null) {
            widget.onSaved!(updated);
          }
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(updated);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text('Failed to update entry. Please try again.'),
                ],
              ),
              backgroundColor: Colors.red.shade800,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } else {
      final newItem = await notifier.addEntry(
        title: _titleController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        url: _urlController.text.trim().isNotEmpty ? _urlController.text.trim() : null,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        category: _selectedCategory,
      );

      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        if (newItem != null) {
          if (widget.onSaved != null) {
            widget.onSaved!(newItem);
          }
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(newItem);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text('Failed to add entry. Please try again.'),
                ],
              ),
              backgroundColor: Colors.red.shade800,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      {'id': 'logins', 'label': 'Login', 'icon': Icons.lock_outline_rounded},
      {'id': 'cards', 'label': 'Card', 'icon': Icons.credit_card_rounded},
      {'id': 'notes', 'label': 'Note', 'icon': Icons.note_alt_outlined},
    ];

    return Scaffold(
      backgroundColor: AppColors.frameBg,
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Item' : 'New Item',
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.ink),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _isSaving ? null : _submit,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy),
                    )
                  : const Icon(Icons.check_rounded, color: AppColors.navy, size: 20),
              label: Text(
                'Save',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _isSaving ? AppColors.inkLight : AppColors.navy,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFEEF3F1),
              Color(0xFFDBE9F6),
              Color(0xFFE4EEFA),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Category Selector Chips
                      SizedBox(
                        height: 44,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: categories.length,
                          itemBuilder: (context, index) {
                            final cat = categories[index];
                            final isSelected = _selectedCategory == cat['id'];

                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: ChoiceChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      cat['icon'] as IconData,
                                      size: 16,
                                      color: isSelected ? Colors.white : AppColors.inkSoft,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(cat['label'] as String),
                                  ],
                                ),
                                selected: isSelected,
                                onSelected: (val) {
                                  if (val) {
                                    setState(() {
                                      _selectedCategory = cat['id'] as String;
                                    });
                                  }
                                },
                                selectedColor: AppColors.navy,
                                backgroundColor: AppColors.glassWhite,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.ink,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: isSelected ? AppColors.navy : AppColors.glassBorderStrong,
                                  ),
                                ),
                                showCheckmark: false,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Card Section 1: Item Details
                      AppGlassCard(
                        padding: const EdgeInsets.all(20),
                        borderRadius: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title
                            _buildInputField(
                              controller: _titleController,
                              label: 'Title',
                              hint: 'e.g. Google Account, Netflix',
                              icon: Icons.title_rounded,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Title is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Username / Email
                            _buildInputField(
                              controller: _usernameController,
                              label: 'Username / Email',
                              hint: 'user@example.com',
                              icon: Icons.person_outline_rounded,
                              showCopyButton: true,
                            ),
                            const SizedBox(height: 16),

                            // Password
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Password',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: _generatePassword,
                                      borderRadius: BorderRadius.circular(8),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        child: Row(
                                          children: [
                                            Icon(Icons.auto_fix_high_rounded, size: 14, color: AppColors.navy),
                                            SizedBox(width: 4),
                                            Text(
                                              'Generate',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.navy,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.inputBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.inputBorder),
                                  ),
                                  child: TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    validator: (val) {
                                      if (val == null || val.isEmpty) {
                                        return 'Password is required';
                                      }
                                      return null;
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'Enter secure password',
                                      hintStyle: const TextStyle(fontSize: 14, color: AppColors.inkLight),
                                      prefixIcon: const Icon(Icons.key_rounded, size: 20, color: AppColors.inkSoft),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                              size: 20,
                                              color: AppColors.inkSoft,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _obscurePassword = !_obscurePassword;
                                              });
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.navy),
                                            onPressed: () {
                                              if (_passwordController.text.isNotEmpty) {
                                                Clipboard.setData(ClipboardData(text: _passwordController.text));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('Password copied to clipboard'),
                                                    duration: Duration(seconds: 1),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Password Strength Meter Bar
                                if (_passwordController.text.isNotEmpty) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: _passwordStrength,
                                      backgroundColor: Colors.black12,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _getStrengthColor(_passwordStrength),
                                      ),
                                      minHeight: 4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _getStrengthLabel(_passwordStrength),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _getStrengthColor(_passwordStrength),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Card Section 2: URL & Notes
                      AppGlassCard(
                        padding: const EdgeInsets.all(20),
                        borderRadius: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Website / URL
                            _buildInputField(
                              controller: _urlController,
                              label: 'Website URL',
                              hint: 'https://example.com',
                              icon: Icons.link_rounded,
                              keyboardType: TextInputType.url,
                              showCopyButton: true,
                            ),
                            const SizedBox(height: 16),

                            // Notes
                            _buildInputField(
                              controller: _notesController,
                              label: 'Notes',
                              hint: 'Recovery keys, security questions, notes...',
                              icon: Icons.notes_rounded,
                              maxLines: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Submit Button
                      ElevatedButton(
                        onPressed: _isSaving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                isEditing ? 'Save Changes' : 'Add Item',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),

                      if (isEditing) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _isSaving ? null : _confirmDeleteCurrentItem,
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 18),
                          label: const Text(
                            'Delete Entry',
                            style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0x33DC2626)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool showCopyButton = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: TextFormField(
            controller: controller,
            validator: validator,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 14, color: AppColors.inkLight),
              prefixIcon: Icon(icon, size: 20, color: AppColors.inkSoft),
              suffixIcon: showCopyButton
                  ? IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.navy),
                      onPressed: () {
                        if (controller.text.isNotEmpty) {
                          Clipboard.setData(ClipboardData(text: controller.text));
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$label copied to clipboard'),
                              backgroundColor: AppColors.navyDark,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Color _getStrengthColor(double strength) {
    if (strength < 0.4) return AppColors.red;
    if (strength < 0.7) return const Color(0xFFD97706);
    return AppColors.pillGreen;
  }

  String _getStrengthLabel(double strength) {
    if (strength < 0.4) return 'Weak password';
    if (strength < 0.7) return 'Medium password';
    return 'Strong password';
  }

  void _confirmDeleteCurrentItem() {
    final item = widget.initialItem;
    if (item == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 24),
            SizedBox(width: 10),
            Text('Delete Entry?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${item.title}"? This item will be removed from your encrypted vault.',
          style: const TextStyle(fontSize: 14, color: AppColors.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.inkSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(vaultStateProvider.notifier).deleteEntry(item.id);
              if (widget.onDeleted != null) {
                widget.onDeleted!(item);
              }
              if (mounted) {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              }
            },
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// Bottom Sheet for generating secure customizable passwords
class _PasswordGeneratorSheet extends StatefulWidget {
  final ValueChanged<String> onPasswordGenerated;

  const _PasswordGeneratorSheet({required this.onPasswordGenerated});

  @override
  State<_PasswordGeneratorSheet> createState() => _PasswordGeneratorSheetState();
}

class _PasswordGeneratorSheetState extends State<_PasswordGeneratorSheet> {
  double _length = 18;
  bool _includeUpper = true;
  bool _includeLower = true;
  bool _includeDigits = true;
  bool _includeSymbols = true;
  String _generated = '';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  void _regenerate() {
    setState(() {
      _generated = PasswordGenerator.generate(
        length: _length.toInt(),
        includeUpper: _includeUpper,
        includeLower: _includeLower,
        includeDigits: _includeDigits,
        includeSymbols: _includeSymbols,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_fix_high_rounded, color: AppColors.navy),
              const SizedBox(width: 10),
              const Text(
                'Password Generator',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Generated Password Display Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.frameBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _generated,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Regenerate',
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.navy),
                  onPressed: _regenerate,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Length Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Length', style: TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${_length.toInt()} characters',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy),
              ),
            ],
          ),
          Slider(
            value: _length,
            min: 8,
            max: 64,
            divisions: 56,
            activeColor: AppColors.navy,
            onChanged: (val) {
              setState(() {
                _length = val;
                _regenerate();
              });
            },
          ),
          const SizedBox(height: 12),

          // Option Checkboxes
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildOptionChip('A-Z (Uppercase)', _includeUpper, (val) {
                setState(() {
                  _includeUpper = val;
                  _regenerate();
                });
              }),
              _buildOptionChip('a-z (Lowercase)', _includeLower, (val) {
                setState(() {
                  _includeLower = val;
                  _regenerate();
                });
              }),
              _buildOptionChip('0-9 (Numbers)', _includeDigits, (val) {
                setState(() {
                  _includeDigits = val;
                  _regenerate();
                });
              }),
              _buildOptionChip('!@# (Symbols)', _includeSymbols, (val) {
                setState(() {
                  _includeSymbols = val;
                  _regenerate();
                });
              }),
            ],
          ),
          const SizedBox(height: 24),

          // Use Password Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onPasswordGenerated(_generated);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Use This Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionChip(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      selectedColor: AppColors.navy.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 12,
        color: value ? AppColors.navy : AppColors.inkSoft,
        fontWeight: value ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: value ? AppColors.navy : AppColors.glassBorderStrong,
        ),
      ),
    );
  }
}
