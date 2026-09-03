import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../widgets/app_ui.dart';

class RegisterPage extends StatefulWidget {
  final AppDatabase db;

  const RegisterPage({super.key, required this.db});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  List<String> _offices = [];
  String? _selectedOffice;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadOffices();
  }

  Future<void> _loadOffices() async {
    final list = await widget.db.getOfficeNames();
    setState(() {
      _offices = list;
      if (list.isNotEmpty) {
        _selectedOffice = list.first;
      }
    });
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate() || _selectedOffice == null) {
      _formKey.currentState?.validate();
      return;
    }

    setState(() => _loading = true);
    final existing = await widget.db.getUserByUsername(
      _usernameController.text.trim(),
    );

    if (!mounted) return;
    if (existing != null) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("اسم المستخدم موجود مسبقًا")),
      );
      return;
    }

    try {
      await widget.db.insertUser(
        UsersCompanion.insert(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          branch: _selectedOffice!,
          role: const drift.Value("user"),
        ),
      );

      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم إرسال طلب إنشاء الحساب وحفظه محليًا")),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("تعذر إنشاء الحساب: $e")));
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: timaMaybeAppBar(
        context,
        title: "إنشاء حساب",
        onBack: () => Navigator.pop(context),
      ),
      body: TimaPageBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: TimaPanel(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const TimaSectionTitle(
                        icon: Icons.person_add_alt_1_rounded,
                        title: "حساب موظف جديد",
                        subtitle: "إضافة بيانات الدخول والفرع المخصص",
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: "اسم المستخدم",
                          prefixIcon: Icon(Icons.person_rounded),
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? "";
                          if (text.isEmpty) return "مطلوب";
                          if (text.length < 3) return "الاسم قصير جدًا";
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: "كلمة المرور",
                          prefixIcon: Icon(Icons.lock_rounded),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return "مطلوب";
                          if (value.length < 4) return "كلمة المرور قصيرة جدًا";
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedOffice,
                        decoration: const InputDecoration(
                          labelText: "فرع / مكتب العمل",
                          prefixIcon: Icon(Icons.storefront_rounded),
                        ),
                        items: _offices
                            .map(
                              (office) => DropdownMenuItem(
                                value: office,
                                child: Text(office),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedOffice = value),
                        validator: (value) =>
                            value == null ? "الرجاء اختيار المكتب" : null,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _loading ? null : _register,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: const Text("طلب إنشاء حساب"),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text("العودة لتسجيل الدخول"),
                      ),
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
}
