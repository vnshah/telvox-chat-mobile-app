import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Person {
  const Person(
    this.id,
    this.name,
    this.phone,
    this.preview,
    this.time, {
    this.unread = 0,
    this.tags = const [],
    this.assignee = 'You',
    this.favorite = false,
    this.closed = false,
    this.bot = false,
    this.color = const Color(0xFFE4EEE4),
    this.notes = const [],
  });
  final String id, name, phone, preview, time, assignee;
  final int unread;
  final List<String> tags, notes;
  final bool favorite, closed, bot;
  final Color color;
  Person copy({
    String? name,
    String? phone,
    String? preview,
    String? time,
    String? assignee,
    int? unread,
    List<String>? tags,
    List<String>? notes,
    bool? favorite,
    bool? closed,
    bool? bot,
  }) => Person(
    id,
    name ?? this.name,
    phone ?? this.phone,
    preview ?? this.preview,
    time ?? this.time,
    unread: unread ?? this.unread,
    tags: tags ?? this.tags,
    notes: notes ?? this.notes,
    assignee: assignee ?? this.assignee,
    favorite: favorite ?? this.favorite,
    closed: closed ?? this.closed,
    bot: bot ?? this.bot,
    color: color,
  );
}

class Message {
  const Message(
    this.text, {
    this.out = false,
    this.time = '10:24',
    this.type = 'text',
    this.reply,
    this.replyAuthor,
    this.reaction = '',
    this.read = true,
  });
  final String text, time, type, reaction;
  final String? reply, replyAuthor;
  final bool out, read;
}

class TicketItem {
  const TicketItem(
    this.id,
    this.title,
    this.personId, {
    this.status = 'Open',
    this.priority = 'Medium',
    this.department = 'Support',
  });
  final String id, title, personId, status, priority, department;
  TicketItem copy({String? status, String? priority}) => TicketItem(
    id,
    title,
    personId,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    department: department,
  );
}

class TemplateItem {
  const TemplateItem(
    this.id,
    this.name,
    this.title,
    this.body,
    this.category, {
    this.status = 'Approved',
  });
  final String id, name, title, body, category, status;
}

const templates = [
  TemplateItem(
    'order',
    'order_confirmation',
    'Order confirmation',
    'Hi {{1}}, your order {{2}} is confirmed! We’re getting it ready with care. We’ll let you know as soon as it’s on its way.',
    'Utility',
  ),
  TemplateItem(
    'shipping',
    'shipping_update',
    'A little delivery update',
    'Hi {{1}}, good news! Your order {{2}} is on its way. Track your delivery using the button below.',
    'Utility',
  ),
  TemplateItem(
    'welcome',
    'welcome_to_studio',
    'Welcome to Studio North',
    'Hello {{1}}, lovely to have you here. Discover thoughtfully made essentials for your everyday.',
    'Marketing',
  ),
  TemplateItem(
    'followup',
    'support_follow_up',
    'Just checking in',
    'Hi {{1}}, we wanted to check that everything is sorted with your order. Reply here if you need a hand.',
    'Utility',
  ),
  TemplateItem(
    'launch',
    'new_collection',
    'Something new, just for you',
    'Our new collection has arrived. Explore pieces made for slower, better days.',
    'Marketing',
    status: 'In review',
  ),
];

const products = [
  (
    id: 'tote',
    name: 'Everyday canvas tote',
    price: '₹1,290',
    category: 'Bags & carry',
    icon: Icons.shopping_bag_outlined,
    color: Color(0xFFE7E1D5),
  ),
  (
    id: 'journal',
    name: 'The daily journal',
    price: '₹690',
    category: 'Desk essentials',
    icon: Icons.menu_book_outlined,
    color: Color(0xFFDCE5DC),
  ),
  (
    id: 'mug',
    name: 'Morning ceramic mug',
    price: '₹890',
    category: 'Home & living',
    icon: Icons.coffee_outlined,
    color: Color(0xFFE9DAD0),
  ),
  (
    id: 'pouch',
    name: 'Little things pouch',
    price: '₹490',
    category: 'Bags & carry',
    icon: Icons.work_outline_rounded,
    color: Color(0xFFDFDDD1),
  ),
];

class UiState {
  const UiState({
    required this.people,
    required this.messages,
    required this.tickets,
    this.notificationsRead = false,
    this.preferences = const {},
    this.workspace = 'Studio North',
  });
  final List<Person> people;
  final Map<String, List<Message>> messages;
  final List<TicketItem> tickets;
  final bool notificationsRead;
  final Map<String, bool> preferences;
  final String workspace;
  UiState copy({
    List<Person>? people,
    Map<String, List<Message>>? messages,
    List<TicketItem>? tickets,
    bool? notificationsRead,
    Map<String, bool>? preferences,
    String? workspace,
  }) => UiState(
    people: people ?? this.people,
    messages: messages ?? this.messages,
    tickets: tickets ?? this.tickets,
    notificationsRead: notificationsRead ?? this.notificationsRead,
    preferences: preferences ?? this.preferences,
    workspace: workspace ?? this.workspace,
  );
}

final previewProvider = NotifierProvider<PreviewController, UiState>(
  PreviewController.new,
);

class PreviewController extends Notifier<UiState> {
  @override
  UiState build() => UiState(
    people: const [
      Person(
        'ananya',
        'Ananya Shah',
        '+91 98765 43210',
        'That sounds perfect, thank you!',
        '10:42',
        unread: 2,
        tags: ['Customer', 'Order enquiry'],
        favorite: true,
      ),
      Person(
        'rohan',
        'Rohan Mehta',
        '+91 98201 34678',
        'Is the canvas tote back in stock?',
        '10:35',
        unread: 1,
        tags: ['New lead'],
        assignee: 'Unassigned',
        color: Color(0xFFECE1D6),
      ),
      Person(
        'priya',
        'Priya Nair',
        '+91 99470 12890',
        'You: Your order is on its way 🌿',
        '10:18',
        tags: ['VIP', 'Repeat customer'],
        color: Color(0xFFE2DEE9),
      ),
      Person(
        'arjun',
        'Arjun Patel',
        '+91 98980 56723',
        'Document · Invoice #ST-2048',
        '09:56',
        tags: ['Wholesale'],
        assignee: 'Meera',
        color: Color(0xFFDDE7EC),
      ),
      Person(
        'ishita',
        'Ishita Rao',
        '+91 99012 34567',
        'Can I change the delivery address?',
        '09:40',
        unread: 3,
        tags: ['Support'],
        color: Color(0xFFECDDD7),
      ),
      Person(
        'kabir',
        'Kabir Kapoor',
        '+91 98100 45678',
        'Thanks for helping me choose.',
        'Yesterday',
        tags: ['Customer'],
        assignee: 'Meera',
        color: Color(0xFFE7E5D8),
      ),
      Person(
        'maya',
        'Maya Fernandes',
        '+91 98204 98123',
        'Looking for a gift for a friend.',
        'Yesterday',
        tags: ['New lead'],
        bot: true,
        assignee: 'Studio assistant',
        color: Color(0xFFDCE6DF),
      ),
      Person(
        'dev',
        'Dev Malhotra',
        '+91 98110 76543',
        'All sorted. Have a lovely day!',
        'Mon',
        tags: ['Resolved'],
        closed: true,
        color: Color(0xFFE6E0D9),
      ),
    ],
    messages: const {
      'ananya': [
        Message(
          'Hi! I placed an order for the everyday tote yesterday. Could you help me with an update?',
          time: '10:24',
        ),
        Message(
          'Hello Ananya! Of course. Let me look that up for you. 🌿',
          out: true,
          time: '10:25',
        ),
        Message(
          'Your order #ST-2048 is packed and ready. It should reach you by Friday.',
          out: true,
          time: '10:26',
        ),
        Message(
          'Order summary · ST-2048',
          type: 'order',
          out: true,
          time: '10:26',
        ),
        Message('Lovely! Could you share the invoice too?', time: '10:28'),
        Message(
          'Invoice_ST2048.pdf',
          type: 'document',
          out: true,
          time: '10:29',
        ),
        Message(
          'That sounds perfect, thank you!',
          time: '10:42',
          reaction: '🤍',
        ),
      ],
      'rohan': [
        Message('Hello! I saw your new collection on Instagram.'),
        Message(
          'Welcome, Rohan! What caught your eye?',
          out: true,
          time: '10:33',
        ),
        Message('Is the canvas tote back in stock?', time: '10:35'),
      ],
      'priya': [
        Message('Hi, could you confirm when my order will ship?'),
        Message('Your order is on its way 🌿', out: true, time: '10:18'),
      ],
    },
    tickets: const [
      TicketItem('1042', 'Delivery address update', 'ishita', priority: 'High'),
      TicketItem('1041', 'Order status enquiry', 'ananya'),
      TicketItem(
        '1040',
        'Wholesale pricing request',
        'arjun',
        status: 'Pending',
        department: 'Sales',
      ),
      TicketItem(
        '1039',
        'Return request',
        'dev',
        status: 'Resolved',
        priority: 'Low',
      ),
    ],
  );

  void updatePerson(String id, Person Function(Person) update) => state = state
      .copy(people: [for (final p in state.people) p.id == id ? update(p) : p]);
  void read(String id) => updatePerson(id, (p) => p.copy(unread: 0));
  void favorite(String id) =>
      updatePerson(id, (p) => p.copy(favorite: !p.favorite));
  void close(String id) => updatePerson(id, (p) => p.copy(closed: !p.closed));
  void assign(String id, String name) => updatePerson(
    id,
    (p) => p.copy(assignee: name, bot: name == 'Studio assistant'),
  );
  void note(String id, String note) =>
      updatePerson(id, (p) => p.copy(notes: [...p.notes, note]));
  void tags(String id, List<String> tags) =>
      updatePerson(id, (p) => p.copy(tags: tags));
  void send(
    String id,
    String text, {
    String type = 'text',
    String? reply,
    String? replyAuthor,
  }) {
    if (text.trim().isEmpty) return;
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    state = state.copy(
      messages: {
        ...state.messages,
        id: [
          ...state.messages[id] ?? [],
          Message(
            text.trim(),
            out: true,
            time: time,
            type: type,
            reply: reply,
            replyAuthor: replyAuthor,
            read: false,
          ),
        ],
      },
    );
    updatePerson(
      id,
      (p) => p.copy(preview: 'You: $text', time: 'Now', unread: 0),
    );
  }

  void contact(String name, String phone, {String? id}) {
    if (id != null) {
      updatePerson(id, (p) => p.copy(name: name, phone: phone));
      return;
    }
    state = state.copy(
      people: [
        Person(
          'contact${state.people.length}',
          name,
          phone,
          'Start a conversation',
          'New',
          assignee: 'Unassigned',
        ),
        ...state.people,
      ],
    );
  }

  void ticket(String title, String personId, String priority) =>
      state = state.copy(
        tickets: [
          TicketItem(
            '${1043 + state.tickets.length - 4}',
            title,
            personId,
            priority: priority,
          ),
          ...state.tickets,
        ],
      );
  void ticketStatus(String id, String status) => state = state.copy(
    tickets: [
      for (final t in state.tickets) t.id == id ? t.copy(status: status) : t,
    ],
  );
  void preference(String key, bool value) =>
      state = state.copy(preferences: {...state.preferences, key: value});
  void notificationsRead() => state = state.copy(notificationsRead: true);
  void workspace(String name) => state = state.copy(workspace: name);
}

Person person(UiState state, String id) => state.people.firstWhere(
  (p) => p.id == id,
  orElse: () => state.people.first,
);
