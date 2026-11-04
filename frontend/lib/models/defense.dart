class Defense {
final int id;
final String studentName;
final String subject;
final String date;
final String startTime;
final String endTime;
final String roomName;
final String juryName;
final String status;

Defense({
required this.id,
required this.studentName,
required this.subject,
required this.date,
required this.startTime,
required this.endTime,
required this.roomName,
required this.juryName,
required this.status,
});

factory Defense.fromJson(Map<String, dynamic> json) {
return Defense(
id: json['id'],
studentName: json['student_name'] ?? '',
subject: json['subject'] ?? '',
date: json['date'] ?? '',
startTime: json['start_time'] ?? '',
endTime: json['end_time'] ?? '',
roomName: json['room_name'] ?? '',
juryName: json['jury_name'] ?? '',
status: json['status'] ?? '',
);
}
}
