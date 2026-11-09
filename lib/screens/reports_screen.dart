import 'package:flutter/material.dart';

import '../models/inventory_models.dart';
import '../state/inventory_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import 'departments_screen.dart';
import 'screen_helpers.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.controller});

  final InventoryController controller;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  UsagePeriod? _period = UsagePeriod.today;
  DateTime? _from = _day(DateTime.now());
  DateTime _through = _day(DateTime.now());
  HotelDepartment? _department;
  bool _submitting = false;

  InventoryController get controller => widget.controller;
  bool get _singleDay => _from != null && _from == _through;

  String get _rangeLabel {
    final from = _from;
    if (from == null) {
      return 'All usage through ${AppFormatters.date(_through)}';
    }
    if (_singleDay) return AppFormatters.date(from, includeWeekday: true);
    return '${AppFormatters.date(from)} – ${AppFormatters.date(_through)}';
  }

  void _setPeriod(UsagePeriod period) {
    if (_submitting) return;
    final today = _day(controller.currentTime.toLocal());
    setState(() {
      _period = period;
      _through = today;
      final count = period.days;
      _from = count == null
          ? null
          : DateTime(today.year, today.month, today.day - count + 1);
    });
  }

  Future<void> _pickDay() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _through,
      firstDate: DateTime(1970),
      lastDate: controller.currentTime.toLocal(),
      helpText: 'Choose a usage report day',
    );
    if (selected != null && mounted) {
      setState(() {
        _period = null;
        _from = _day(selected);
        _through = _day(selected);
      });
    }
  }

  Future<void> _pickRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: controller.currentTime.toLocal(),
      initialDateRange: DateTimeRange(start: _from ?? _through, end: _through),
      helpText: 'Choose a usage date range',
    );
    if (selected != null && mounted) {
      setState(() {
        _period = null;
        _from = _day(selected.start);
        _through = _day(selected.end);
      });
    }
  }

  Future<void> _submitReport() async {
    if (_submitting || !_singleDay) return;
    final reportDay = _from!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit daily usage report?'),
        content: Text(
          'Close ${AppFormatters.date(reportDay)} for all departments? After submission, no more usage can be recorded for this day.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit report'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await controller.submitDailyReport(day: reportDay);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Usage report for ${AppFormatters.date(reportDay)} submitted.',
            ),
          ),
        );
      }
    } on InventoryException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final endExclusive = DateTime(
        _through.year,
        _through.month,
        _through.day + 1,
      );
      final issues = controller.departmentIssues.where((issue) {
        final date = issue.issuedAt.toLocal();
        return (_from == null || !date.isBefore(_from!)) &&
            date.isBefore(endExclusive) &&
            (_department == null || issue.department == _department);
      }).toList()..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
      final summaries = summarizeUsage(issues);
      final units = issues.fold<int>(0, (sum, issue) => sum + issue.quantity);
      final value = issues.fold<int>(0, (sum, issue) => sum + issue.valueMinor);
      final submitted = _singleDay && controller.isDailyReportSubmitted(_from!);
      final departments = _department == null
          ? HotelDepartment.values
          : [_department!];
      final reports = controller.dailyReports.toList()
        ..sort((a, b) => b.day.compareTo(a.day));
      final horizontal = context.pagePadding.horizontal / 2;
      return SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: context.pagePadding.copyWith(bottom: 16),
              sliver: const SliverToBoxAdapter(
                child: PageHeader(
                  eyebrow: 'Management overview',
                  title: 'Usage reports',
                  subtitle:
                      'See how much Kitchen and each department use, with product quantities, costs and dated records.',
                ),
              ),
            ),
            _section(
              horizontal,
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Usage date & department',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    UsagePeriodSelector(
                      selected: _period,
                      onSelected: _setPeriod,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _submitting ? null : _pickDay,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: const Text('Choose day'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _submitting ? null : _pickRange,
                          icon: const Icon(Icons.date_range_outlined),
                          label: const Text('Date range'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _rangeLabel,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<HotelDepartment>(
                      key: ValueKey(_department),
                      initialValue: _department,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Department',
                        prefixIcon: Icon(Icons.account_tree_outlined),
                      ),
                      items: [
                        const DropdownMenuItem<HotelDepartment>(
                          value: null,
                          child: Text('All departments'),
                        ),
                        ...HotelDepartment.values.map(
                          (department) => DropdownMenuItem(
                            value: department,
                            child: Text(department.label),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _department = value),
                    ),
                  ],
                ),
              ),
              top: 0,
            ),
            if (_singleDay)
              _section(
                horizontal,
                SectionCard(
                  backgroundColor: submitted
                      ? context.semanticColors.successContainer
                      : context.semanticColors.warningContainer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            submitted
                                ? Icons.verified_outlined
                                : Icons.pending_actions,
                            color: submitted
                                ? context.semanticColors.onSuccessContainer
                                : context.semanticColors.onWarningContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              submitted
                                  ? 'This day’s report is submitted. Usage for this date is closed.'
                                  : 'This day’s report is open. Submit after every department finishes recording usage.',
                            ),
                          ),
                        ],
                      ),
                      if (!submitted) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Submission includes all departments, even when this view is filtered.',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: _submitting ? null : _submitReport,
                          icon: _submitting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.fact_check_outlined),
                          label: Text(
                            _submitting ? 'Submitting…' : 'Submit daily report',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                top: 0,
              )
            else
              _section(
                horizontal,
                const Text(
                  'Select a single day to submit its daily report. Date ranges are for reviewing usage.',
                ),
                top: 0,
              ),
            _section(
              horizontal,
              UsageMetrics(
                children: [
                  MetricCard(
                    label: 'Units used (aggregate)',
                    value: AppFormatters.quantity(units),
                    icon: Icons.restaurant_outlined,
                    helperText: _department?.label ?? 'All departments',
                  ),
                  MetricCard(
                    label: 'Usage cost',
                    value: formatMoney(controller, value, compact: true),
                    icon: Icons.payments_outlined,
                    helperText: '${issues.length} usage records',
                  ),
                ],
              ),
              top: 0,
            ),
            _section(
              horizontal,
              Text(
                'Usage by department',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              top: 8,
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              sliver: SliverList.separated(
                itemCount: departments.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final department = departments[index];
                  final usage = issues.where(
                    (issue) => issue.department == department,
                  );
                  final usedUnits = usage.fold<int>(
                    0,
                    (sum, issue) => sum + issue.quantity,
                  );
                  final usedValue = usage.fold<int>(
                    0,
                    (sum, issue) => sum + issue.valueMinor,
                  );
                  return SectionCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(departmentIcon(department), size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                department.label,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 16,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    '${AppFormatters.quantity(usedUnits)} units used',
                                  ),
                                  Text(
                                    '${formatMoney(controller, usedValue)} cost',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${usage.length} usage records',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (issues.isNotEmpty) ...[
              _section(
                horizontal,
                Text(
                  'Usage by product',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                sliver: SliverList.separated(
                  itemCount: summaries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => UsageProductTile(
                    summary: summaries[index],
                    controller: controller,
                  ),
                ),
              ),
              _section(
                horizontal,
                Text(
                  'Dated usage details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                sliver: SliverList.separated(
                  itemCount: issues.length,
                  separatorBuilder: (_, _) => const Divider(height: 20),
                  itemBuilder: (context, index) => UsageHistoryTile(
                    issue: issues[index],
                    controller: controller,
                  ),
                ),
              ),
            ] else
              _section(
                horizontal,
                const EmptyState(
                  compact: true,
                  icon: Icons.analytics_outlined,
                  title: 'No usage for this selection',
                  message:
                      'Try another date or department, or record department usage to see it here.',
                ),
                top: 0,
              ),
            _section(
              horizontal,
              Text(
                'Submitted daily reports',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (reports.isEmpty)
              _section(
                horizontal,
                const EmptyState(
                  compact: true,
                  icon: Icons.fact_check_outlined,
                  title: 'No submitted reports yet',
                  message:
                      'Choose a single day above and submit its report after recording all usage.',
                ),
                top: 0,
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                sliver: SliverList.separated(
                  itemCount: reports.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    return SectionCard(
                      padding: const EdgeInsets.all(14),
                      onTap: _submitting
                          ? null
                          : () => setState(() {
                              _period = null;
                              _from = _day(report.day.toLocal());
                              _through = _from!;
                              _department = null;
                            }),
                      semanticLabel:
                          'Review report for ${AppFormatters.date(report.day.toLocal())}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.verified_outlined,
                                color: context.semanticColors.success,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  AppFormatters.date(report.day.toLocal()),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              const Icon(Icons.chevron_right, size: 22),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${AppFormatters.quantity(report.totalUnits)} units used',
                              ),
                              Text(
                                '${formatMoney(controller, report.totalValueMinor)} cost',
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Submitted ${AppFormatters.dateTime(report.submittedAt.toLocal())} · All departments',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (report.note != null &&
                              report.note!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              report.note!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      );
    },
  );

  Widget _section(double horizontal, Widget child, {double top = 24}) =>
      SliverPadding(
        padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, 16),
        sliver: SliverToBoxAdapter(child: child),
      );
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
