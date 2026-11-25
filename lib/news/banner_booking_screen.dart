/// Build 9 (v1.7.0, fix-list point #6A) — BANNER BOOKING screen.
///
/// In-app self-service booking for the Home hero banners. BOTH
/// slots are bookable (user's correction, 2026-11-25); the
/// owner's own banners remain the saved default on each slot
/// and return automatically when a booking's time ends.
///
/// Flow (the money rules live in banner_booking_service.dart):
/// pick a slot -> pick a duration (100/200/300 coins for
/// 1/2/4 hours) -> pick the banner image -> optional ad text
/// and link -> auto-moderation runs FIRST -> clean bookings go
/// live (or queue behind the slot's current booking), doubtful
/// ones wait as pending_review and never go live on their own,
/// hard violations are refused before any coin moves. Rejected
/// bookings are refunded automatically (see the service).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/banner_booking_service.dart';
import '../services/coin_service.dart';

class BannerBookingScreen extends StatefulWidget {
  const BannerBookingScreen({super.key});

  @override
  State<BannerBookingScreen> createState() => _BannerBookingScreenState();
}

class _BannerBookingScreenState extends State<BannerBookingScreen> {
  int _slot = 2;
  int _durationIndex = 0;
  File? _image;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    BannerBookingService.instance.refresh();
  }

  @override
  void dispose() {
    _textController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (picked == null) return;
      setState(() => _image = File(picked.path));
    } catch (_) {
      _show('Image nahi khuli — dobara try karein.', error: true);
    }
  }

  void _show(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  Future<void> _book() async {
    if (_busy) return;
    final image = _image;
    if (image == null) {
      _show('Pehle banner ki image chunein.', error: true);
      return;
    }
    final duration = BannerBookingService.durations[_durationIndex];
    setState(() {
      _busy = true;
      _message = null;
    });
    final attempt = await BannerBookingService.instance.createBooking(
      slot: _slot,
      imageFile: image,
      text: _textController.text,
      link: _linkController.text,
      hours: duration.hours,
      priceCoins: duration.coins,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (attempt.ok) {
      final booking = attempt.booking!;
      if (booking.status == BannerBooking.statusPendingReview) {
        _show(
          'Booking mil gayi hai — ye abhi REVIEW mein hai. '
          'Approve hote hi banner live hoga; reject hua to '
          '${booking.priceCoins} coins khud wapas aa jayenge.',
        );
      } else {
        final starts = booking.startsAt.toLocal();
        final now = DateTime.now();
        _show(
          starts.isAfter(now)
              ? 'Booking ho gayi! Slot abhi bhara hai — aap ka '
                  'banner ${starts.hour}:${starts.minute.toString().padLeft(2, '0')} '
                  'se ${booking.durationHours} ghante live rahe ga.'
              : 'Booking ho gayi! Aap ka banner ab live hai — '
                  '${booking.durationHours} ghante rahe ga, phir '
                  'owner ka banner khud wapas aa jaye ga.',
        );
      }
      return;
    }
    switch (attempt.error) {
      case 'moderation_rejected':
        final reasons =
            attempt.moderation?.reasons.join(' ') ?? 'Banner manzoor nahi hua.';
        _show('Booking refuse ho gayi: $reasons Coins nahi kate.', error: true);
      case 'insufficient_balance':
        _show(
          'Coins kam hain — Earn tab mein rewarded ads dekh kar '
          'coins kamayein, phir booking karein.',
          error: true,
        );
      case 'not_signed_in':
        _show('Booking ke liye pehle login karein.', error: true);
      default:
        _show(
          'Booking nahi ho saki (${attempt.error ?? 'error'}) — '
          'dobara try karein. Coins nahi kate.',
          error: true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final durations = BannerBookingService.durations;
    return Scaffold(
      appBar: AppBar(title: const Text('Apna banner lagwayein')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Home ke hero banner par apni advertising lagayein. '
              'Waqt khatam hote hi booked banner khud hat jata hai '
              'aur owner ka banner wapas aa jata hai.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 14),
            const Text(
              'Slot chunein',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final slot in <int>[1, 2]) ...[
                  Expanded(
                    child: ChoiceChip(
                      key: Key('bookingSlot$slot'),
                      label: Text(
                        slot == 1 ? 'Banner 1 (pehla)' : 'Banner 2 (dusra)',
                      ),
                      selected: _slot == slot,
                      onSelected: (_) => setState(() => _slot = slot),
                    ),
                  ),
                  if (slot == 1) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Waqt chunein',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < durations.length; i++) ...[
                  Expanded(
                    child: ChoiceChip(
                      key: Key('bookingDuration$i'),
                      label: Text(
                        '${durations[i].hours} ghante\n'
                        '${durations[i].coins} coins',
                        textAlign: TextAlign.center,
                      ),
                      selected: _durationIndex == i,
                      onSelected: (_) => setState(() => _durationIndex = i),
                    ),
                  ),
                  if (i < durations.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Banner image',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 170,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _image == null
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.image_outlined, size: 32),
                            SizedBox(height: 6),
                            Text('Image chunne ke liye tap karein'),
                          ],
                        ),
                      )
                    : Image.file(_image!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _textController,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Ad text (ikhtiyari)',
                hintText: 'Masalan: apni dukaan / channel ka naam',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _linkController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link (ikhtiyari)',
                hintText: 'https://…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<int>(
              valueListenable: CoinService.instance.balance,
              builder: (context, balance, _) {
                return Text(
                  'Aap ka balance: $balance coins',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                );
              },
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(
                _message!,
                style: TextStyle(
                  color: _messageIsError ? Colors.redAccent : Colors.green,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              key: const Key('bookingSubmitButton'),
              onPressed: _busy ? null : _book,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.campaign_outlined, size: 18),
              label: Text(
                _busy
                    ? 'Ho raha hai…'
                    : 'Book karein — '
                        '${durations[_durationIndex].coins} coins',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: har banner pehle khud-kar jaanch (moderation) '
              'se guzarta hai. Ghalat/gandi cheez refuse ho jati '
              'hai; mashkook cheez owner ke review tak live nahi '
              'hoti. Reject hone par coins khud wapas aa jate hain.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 20),
            _myBookings(),
          ],
        ),
      ),
    );
  }

  Widget _myBookings() {
    return ValueListenableBuilder<int>(
      valueListenable: BannerBookingService.instance.revision,
      builder: (context, _, _) {
        final mine = BannerBookingService.instance.myBookings;
        if (mine.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Meri bookings',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final b in mine.take(10))
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.campaign_outlined, size: 20),
                  title: Text(
                    'Banner ${b.slot} — ${b.durationHours} ghante '
                    '(${b.priceCoins} coins)',
                  ),
                  subtitle: Text(
                    b.status == BannerBooking.statusApproved
                        ? 'Live/queue — ${b.startsAt.toLocal()} se '
                            '${b.endsAt.toLocal()} tak'
                        : b.status == BannerBooking.statusPendingReview
                            ? 'Review mein hai — live nahi'
                            : 'Reject ho gayi'
                                '${b.refundedAt != null ? ' — coins wapas ho gaye' : ''}',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
