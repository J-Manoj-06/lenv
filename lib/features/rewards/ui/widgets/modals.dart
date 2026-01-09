import 'package:flutter/material.dart';
import '../../utils/points_calculator.dart';

/// Modal for confirming delivery of a reward
class DeliveryConfirmModal extends StatefulWidget {
  final String productName;
  final double pointsToRelease;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool isLoading;

  const DeliveryConfirmModal({
    super.key,
    required this.productName,
    required this.pointsToRelease,
    required this.onConfirm,
    required this.onCancel,
    this.isLoading = false,
  });

  @override
  State<DeliveryConfirmModal> createState() => _DeliveryConfirmModalState();
}

class _DeliveryConfirmModalState extends State<DeliveryConfirmModal> {
  final _photoController = TextEditingController();
  final _receiptController = TextEditingController();

  @override
  void dispose() {
    _photoController.dispose();
    _receiptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusCode = PointsCalculator.getPointsStatusCode(
      widget.pointsToRelease.toInt(),
      widget.pointsToRelease.toInt(),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.local_shipping,
                    color: Colors.orange[700],
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Confirm Delivery',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (!widget.isLoading)
                    IconButton(
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.close),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Product Details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Product',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.productName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Points to Release',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.pointsToRelease.toStringAsFixed(0)} pts',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange[700],
                                  ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Status',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 4),
                            Chip(
                              label: Text(statusCode.toString()),
                              backgroundColor: statusCode >= 100
                                  ? Colors.green[100]
                                  : Colors.orange[100],
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: statusCode >= 100
                                    ? Colors.green[700]
                                    : Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Confirmation Checkboxes
              Text(
                'Confirmation',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Item has been delivered to the student',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: _photoController.text.isNotEmpty,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _photoController.text = 'confirmed';
                    } else {
                      _photoController.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Receipt/invoice has been verified',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: _receiptController.text.isNotEmpty,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _receiptController.text = 'confirmed';
                    } else {
                      _receiptController.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 20),
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: widget.isLoading ? null : widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          (_photoController.text.isNotEmpty &&
                              _receiptController.text.isNotEmpty &&
                              !widget.isLoading)
                          ? widget.onConfirm
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF2800D),
                      ),
                      child: widget.isLoading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('Confirm Delivery'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal for blocking a student from accessing rewards
class BlockingModal extends StatefulWidget {
  final String studentName;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool isLoading;
  final String? reason;

  const BlockingModal({
    super.key,
    required this.studentName,
    required this.onConfirm,
    required this.onCancel,
    this.isLoading = false,
    this.reason,
  });

  @override
  State<BlockingModal> createState() => _BlockingModalState();
}

class _BlockingModalState extends State<BlockingModal> {
  late TextEditingController _reasonController;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController(text: widget.reason);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header - Warning Style
              Row(
                children: [
                  Icon(Icons.block, color: Colors.red[700], size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Block Student',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (!widget.isLoading)
                    IconButton(
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.close),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Warning Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Warning: This action cannot be undone immediately',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.red[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Student ${widget.studentName} will be blocked from accessing the rewards catalog and creating new requests. An administrator can unblock later.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.red[900]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Student Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Student: ${widget.studentName}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 20),
              // Reason Field
              Text(
                'Reason for Blocking',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonController,
                enabled: !widget.isLoading,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter reason (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: widget.isLoading ? null : widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.isLoading ? null : widget.onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                      ),
                      child: widget.isLoading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('Block Student'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal for manual purchase confirmation
class ManualPurchaseModal extends StatefulWidget {
  final String productName;
  final double price;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool isLoading;

  const ManualPurchaseModal({
    super.key,
    required this.productName,
    required this.price,
    required this.onConfirm,
    required this.onCancel,
    this.isLoading = false,
  });

  @override
  State<ManualPurchaseModal> createState() => _ManualPurchaseModalState();
}

class _ManualPurchaseModalState extends State<ManualPurchaseModal> {
  late TextEditingController _priceController;
  late TextEditingController _noteController;
  bool _priceConfirmed = false;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.price.toStringAsFixed(2),
    );
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _priceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.shopping_cart,
                    color: Colors.orange[700],
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Manual Purchase',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (!widget.isLoading)
                    IconButton(
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.close),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Product Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Product',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.productName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Price Field
              Text(
                'Price (₹)',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _priceController,
                enabled: !widget.isLoading,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Notes Field
              Text(
                'Purchase Notes',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                enabled: !widget.isLoading,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Receipt details, invoice number, etc.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Price Confirmation Checkbox
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'I confirm the price is correct (₹${_priceController.text})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: _priceConfirmed,
                onChanged: !widget.isLoading
                    ? (value) {
                        setState(() {
                          _priceConfirmed = value ?? false;
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 20),
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: widget.isLoading ? null : widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_priceConfirmed && !widget.isLoading)
                          ? widget.onConfirm
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF2800D),
                      ),
                      child: widget.isLoading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('Confirm Purchase'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
