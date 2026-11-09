import 'package:flutter/material.dart';
import '../models/defense.dart';
import '../services/planning_store.dart';

class DefenseFormScreen extends StatefulWidget {
  const DefenseFormScreen({super.key});

  @override
  State<DefenseFormScreen> createState() => _DefenseFormScreenState();
}

class _DefenseFormScreenState extends State<DefenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _studentController = TextEditingController();
  final _subjectController = TextEditingController();
  final _juryController = TextEditingController();

  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;
  String? _room;
  bool _checking = false;

  @override
  void dispose() {
    _studentController.dispose();
    _subjectController.dispose();
    _juryController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return '';
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _pickTime({required bool start}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start
          ? const TimeOfDay(hour: 9, minute: 0)
          : const TimeOfDay(hour: 10, minute: 0),
    );
    if (selected != null) {
      setState(() {
        if (start) {
          _start = selected;
        } else {
          _end = selected;
        }
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null || _start == null || _end == null || _room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complétez la date, les heures et la salle.')),
      );
      return;
    }

    final startText = _formatTime(_start);
    final endText = _formatTime(_end);
    final startMinutes = _start!.hour * 60 + _start!.minute;
    final endMinutes = _end!.hour * 60 + _end!.minute;
    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('L’heure de fin doit être après l’heure de début.')),
      );
      return;
    }

    final candidate = Defense(
      id: PlanningStore.nextId,
      studentName: _studentController.text.trim(),
      subject: _subjectController.text.trim(),
      date: '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-'
          '${_date!.day.toString().padLeft(2, '0')}',
      startTime: startText,
      endTime: endText,
      roomName: _room!,
      juryName: _juryController.text.trim(),
      status: 'En attente',
    );

    final conflicts = PlanningStore.findConflicts(candidate);
    if (conflicts.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Conflit de planning'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: conflicts.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• $item'),
            )).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Modifier'),
            ),
          ],
        ),
      );
      return;
    }

    PlanningStore.nextId++;
    PlanningStore.addDefense(candidate);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    const ink = Color(0xFF171717);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        title: const Text('Nouvelle soutenance'),
        backgroundColor: ink,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Informations de la soutenance',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            _field(_studentController, 'Nom de l’étudiant', Icons.person),
            _field(_subjectController, 'Sujet de soutenance', Icons.book),
            const SizedBox(height: 12),
            _pickerTile(
              icon: Icons.calendar_month,
              title: _date == null
                  ? 'Choisir la date'
                  : '${_date!.day.toString().padLeft(2, '0')}/'
                    '${_date!.month.toString().padLeft(2, '0')}/${_date!.year}',
              onTap: _pickDate,
            ),
            Row(
              children: [
                Expanded(
                  child: _pickerTile(
                    icon: Icons.access_time,
                    title: _start == null ? 'Début' : _formatTime(_start),
                    onTap: () => _pickTime(start: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _pickerTile(
                    icon: Icons.timer_off,
                    title: _end == null ? 'Fin' : _formatTime(_end),
                    onTap: () => _pickTime(start: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _room,
              decoration: const InputDecoration(
                labelText: 'Salle',
                prefixIcon: Icon(Icons.meeting_room),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              items: PlanningStore.rooms
                  .map((room) => DropdownMenuItem(value: room, child: Text(room)))
                  .toList(),
              onChanged: (value) => setState(() => _room = value),
              validator: (value) => value == null ? 'Choisissez une salle' : null,
            ),
            const SizedBox(height: 14),
            _field(
              _juryController,
              'Membres du jury (séparés par des virgules)',
              Icons.groups,
              hint: 'Ex. M. Diallo, Mme Coulibaly',
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save, color: ink),
                label: const Text(
                  'Enregistrer la soutenance',
                  style: TextStyle(color: ink, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Les conflits de salle et de jury sont vérifiés avant l’enregistrement.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Champ obligatoire' : null,
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFD4AF37)),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        trailing: const Icon(Icons.edit_calendar),
        onTap: onTap,
      ),
    );
  }
}
