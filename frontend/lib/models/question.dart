class Question {
  final String id;
  final String text;
  final String optionA;
  final String optionB;

  Question({
    required this.id,
    required this.text,
    required this.optionA,
    required this.optionB,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'],
      text: json['text'],
      optionA: json['option_a'],
      optionB: json['option_b'],
    );
  }
}
