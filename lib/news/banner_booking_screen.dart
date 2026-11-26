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
      _show('The image did not open — try again.', error: true);
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
      _show('Choose the banner image first.', error: true);
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
          'Booking received — it is in REVIEW right now. '
          'As soon as it is approved the banner will go live; if rejected, '
          '${booking.priceCoins} coins will return automatically.',
        );
      } else {
        final starts = booking.startsAt.toLocal();
        final now = DateTime.now();
        _show(
          starts.isAfter(now)
              ? 'Booking done! The slot is taken right now — your '
                  'banner ${starts.hour}:${starts.minute.toString().padLeft(2, '0')} '
                  'will stay live for ${booking.durationHours} hours from '
              : 'Booking done! Your banner is now live — '
                  '${booking.durationHours} hours, then '
                  'the owner\'s banner will come back by itself.',
        );
      }
      return;
    }
    switch (attempt.error) {
      case 'moderation_rejected':
        final reasons =
            attempt.moderation?.reasons.join(' ') ?? 'Banner was not approved.';
        _show('Booking refused: $reasons Coins were not charged.', error: true);
      case 'insufficient_balance':
        _show(
          'Not enough coins — watch rewarded ads in the Earn tab to '
          'earn coins, then book.',
          error: true,
        );
      case 'not_signed_in':
        _show('Log in first to book.', error: true);
      default:
        _show(
          'Booking could not be completed (${attempt.error ?? 'error'}) — '
          'try again. Coins were not charged.',
          error: true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final durations = BannerBookingService.durations;
    return Scaffold(
      appBar: AppBar(title: const Text('Place your banner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Place your advertising on the Home hero banner. '
              'When the time ends, the booked banner removes itself '
              'and the owner\'s banner comes back.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 14),
            const Text(
              'Choose a slot',
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
                        slot == 1 ? 'Banner 1 (first)' : 'Banner 2 (second)',
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
              'Choose the duration',
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
                        '${durations[i].hours} hours\n'
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
                            Text('Tap to choose an image'),
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
                hintText: 'For example: your shop / channel name',
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
                    ? 'In progress…'
                    : 'Book — '
                        '${durations[_durationIndex].coins} coins',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: every banner first passes an automatic check (moderation) '
              'passes. A wrong/dirty thing is refused '
              'it is; a suspicious thing does not go live until the owner\'s review '
              'happens. On rejection, the coins return automatically.',
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
              'My bookings',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final b in mine.take(10))
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.campaign_outlined, size: 20),
                  title: Text(
                    'Banner ${b.slot} — ${b.durationHours} hours '
                    '(${b.priceCoins} coins)',
                  ),
                  subtitle: Text(
                    b.status == BannerBooking.statusApproved
                        ? 'Live/queue — ${b.startsAt.toLocal()} se '
                            '${b.endsAt.toLocal()} tak'
                        : b.status == BannerBooking.statusPendingReview
                            ? 'In review — not live'
                            : 'Rejected'
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
