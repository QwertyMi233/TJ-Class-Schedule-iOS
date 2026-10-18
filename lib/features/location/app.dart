import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain.dart';
import 'location.dart';
import 'store.dart';

const accent = Color(0xff28a86b);
const placeColors = [0xff28a86b, 0xff4386ef, 0xffe89c35, 0xff9b70df];

class LocationPage extends ConsumerWidget {
  const LocationPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(placeStoreProvider)
      .when(
        data: (_) => const LocationHomePage(),
        loading: () => Scaffold(
          appBar: AppBar(title: const Text('定位')),
          body: const Center(child: Text('正在读取本机定位点')),
        ),
        error: (_, _) => Scaffold(
          appBar: AppBar(title: const Text('定位')),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('定位点读取失败，请重试'),
                TextButton(
                  onPressed: () => ref.invalidate(placeStoreProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
}

Color muted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;
Color panel(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xff1c211e)
    : Colors.white;
String stamp(DateTime time) {
  final t = time.toLocal();
  return '${t.month}月${t.day}日 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

void message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<bool> deletePlace(
  BuildContext context,
  WidgetRef ref,
  Place place,
) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('删除这个定位点？'),
      content: Text('“${place.name}”的位置和备注将从本机删除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('删除', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (yes != true || !context.mounted) return false;
  try {
    await ref.read(storeProvider).delete(place.id);
    ref.invalidate(placesProvider);
    return true;
  } catch (_) {
    if (context.mounted) message(context, '删除失败，请重试');
    return false;
  }
}

class LocationHomePage extends ConsumerWidget {
  const LocationHomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(placesProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 24, 16, 12),
                  child: Row(
                    children: [
                      if (Navigator.canPop(context))
                        IconButton(
                          tooltip: '返回课表',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      const Expanded(
                        child: Text(
                          '定位',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '使用说明',
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('记住位置，随时寻找'),
                            content: const SingleChildScrollView(
                              child: Text(
                                '在想记住的地方，点击“记住当前位置”。\n\n需要返回时，点开定位点，可选择箭头或方向高亮。手机平放时顶部朝前，正常竖握时背面朝前；转动手机，方向会跟随更新。\n\n主界面长按定位点可以删除。每个点独立保存，名称和备注可修改。\n\n定位误差较大或进入误差范围时，以附近实物和备注为准。\n\n位置仅保存在本机，无账号、无广告、无云同步。只有保存或寻找时使用前台定位；退出这些页面或切到后台即停止。卸载或清除数据会删除定位点。',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: const Text('知道了'),
                              ),
                            ],
                          ),
                        ),
                        icon: const Icon(Icons.info_outline_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  child: Text(
                    '我的定位点',
                    style: TextStyle(color: muted(context), fontSize: 15),
                  ),
                ),
                Expanded(
                  child: places.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: accent),
                    ),
                    error: (_, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('定位点暂时无法读取'),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => ref.invalidate(placesProvider),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                    data: (items) => items.isEmpty
                        ? const EmptyPlaces()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (c, index) {
                              final place = items[index];
                              return Material(
                                color: panel(context),
                                borderRadius: BorderRadius.circular(23),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(23),
                                  onLongPress: () =>
                                      deletePlace(context, ref, place),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          TrackingPage(place: place),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            color: Color(place.color)
                                                .withValues(alpha: .12),
                                            borderRadius: BorderRadius.circular(
                                              17,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.location_on_rounded,
                                            color: Color(place.color),
                                            size: 28,
                                          ),
                                        ),
                                        const SizedBox(width: 15),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                place.name,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                place.note.isEmpty
                                                    ? '保存于 ${stamp(place.createdAt)}'
                                                    : place.note,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: muted(context),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          color: muted(context),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                  child: FilledButton.icon(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: panel(context),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(30),
                        ),
                      ),
                      builder: (_) => const PlaceEditor(),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text(
                      '记住当前位置',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text(
                    '位置留在手机里',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: muted(context)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyPlaces extends StatelessWidget {
  const EmptyPlaces({super.key});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 124,
            height: 124,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .09),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_rounded,
              size: 64,
              color: accent,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '记住这里',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            '在这里存一个点\n需要时，跟着方向找到它',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted(context), fontSize: 16, height: 1.7),
          ),
        ],
      ),
    ),
  );
}

// 系统定位和传感器由 Android 生命周期负责暂停；页面返回后终止整个会话。
mixin LocationSession<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, WidgetsBindingObserver {
  bool get usesLocation => true;
  late LocationController locator;
  @override
  void initState() {
    super.initState();
    locator = ref.read(locationProvider.notifier);
    if (usesLocation) {
      WidgetsBinding.instance.addObserver(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(locator.start());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(locator.start(requestPermission: false));
    } else {
      locator.suspend();
    }
  }

  @override
  void dispose() {
    if (usesLocation) {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(locator.stop());
    }
    super.dispose();
  }
}

class LocationNotice extends ConsumerWidget {
  const LocationNotice({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(locationProvider);
    final fix = state.fix;
    final poor = fix != null && fix.accuracy > 50;
    final text = fix != null
        ? (poor
              ? '精度约 ±${fix.accuracy.ceil()} 米，请到开阔处再保存'
              : '定位精度约 ±${fix.accuracy.ceil()} 米')
        : statusText(state.status);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              fix != null && !poor
                  ? Icons.check_circle_outline_rounded
                  : Icons.location_searching_rounded,
              color: fix != null && !poor ? accent : muted(context),
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: muted(context)),
              ),
            ),
          ],
        ),
        if (fix == null &&
            [
              'denied',
              'deniedForever',
              'disabled',
              'error',
              'stale',
            ].contains(state.status))
          TextButton(
            onPressed: () async {
              final controller = ref.read(locationProvider.notifier);
              try {
                if (state.status == 'deniedForever' ||
                    state.status == 'disabled') {
                  await controller.settings(
                    location: state.status == 'disabled',
                  );
                } else {
                  await controller.start();
                }
              } catch (_) {
                if (context.mounted) message(context, '无法打开设置，请手动检查定位权限');
              }
            },
            child: Text(
              state.status == 'deniedForever' || state.status == 'disabled'
                  ? '打开设置'
                  : '重新定位',
            ),
          ),
      ],
    );
  }
}

class PlaceEditor extends ConsumerStatefulWidget {
  final Place? place;
  const PlaceEditor({super.key, this.place});
  @override
  ConsumerState<PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends ConsumerState<PlaceEditor>
    with WidgetsBindingObserver, LocationSession<PlaceEditor> {
  @override
  bool get usesLocation => widget.place == null;
  late final name = TextEditingController(text: widget.place?.name ?? '新定位点');
  late final note = TextEditingController(text: widget.place?.note ?? '');
  late int color = widget.place?.color ?? placeColors.first;
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    final title = name.text.trim(), memo = note.text.trim();
    if (title.isEmpty) {
      message(context, '给这个定位点起个名字');
      return;
    }
    final fix = ref.read(locationProvider).fix;
    if (usesLocation && (fix == null || !fix.canSaveAt(DateTime.now()))) {
      message(context, '请等待新鲜且误差不超过 50 米的定位');
      return;
    }
    setState(() => saving = true);
    try {
      final store = ref.read(storeProvider);
      if (widget.place != null) {
        await store.edit(widget.place!.renamed(title, memo));
      } else {
        await store.insert(
          Place(
            id: newId(),
            name: title,
            note: memo,
            color: color,
            fix: fix!,
            createdAt: DateTime.now(),
          ),
        );
      }
      ref.invalidate(placesProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        message(context, '保存失败，请检查手机空间后重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fix = ref.watch(locationProvider).fix;
    final canSave =
        !saving &&
        (!usesLocation || (fix != null && fix.canSaveAt(DateTime.now())));
    return PopScope(
      canPop: !saving,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: muted(context).withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  usesLocation ? '记住当前位置' : '编辑定位点',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '例如：宿舍入口',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  maxLength: 160,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    hintText: '例如：图书馆东门，靠近台阶',
                  ),
                ),
                if (usesLocation) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: placeColors
                        .map(
                          (c) => IconButton(
                            tooltip: '标记颜色 ${placeColors.indexOf(c) + 1}',
                            style: IconButton.styleFrom(
                              backgroundColor: Color(c).withValues(alpha: .12),
                            ),
                            onPressed: () => setState(() => color = c),
                            icon: Icon(
                              color == c ? Icons.check_circle : Icons.circle,
                              color: Color(c),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  const LocationNotice(),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    '只修改名称和备注，保留原来的位置。',
                    style: TextStyle(fontSize: 13, color: muted(context)),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: canSave ? save : null,
                  child: Text(
                    saving
                        ? '正在保存…'
                        : usesLocation
                        ? '保存这个位置'
                        : '保存修改',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TrackingPage extends ConsumerStatefulWidget {
  final Place place;
  const TrackingPage({super.key, required this.place});
  @override
  ConsumerState<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends ConsumerState<TrackingPage>
    with WidgetsBindingObserver, LocationSession<TrackingPage> {
  bool deleting = false;
  Future<void> remove(Place place) async {
    setState(() => deleting = true);
    final removed = await deletePlace(context, ref, place);
    if (mounted) {
      if (removed) {
        Navigator.pop(context);
      } else {
        setState(() => deleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(placesProvider).asData?.value;
    final place =
        items?.where((p) => p.id == widget.place.id).firstOrNull ??
        widget.place;
    final location = ref.watch(locationProvider);
    final now = DateTime.now();
    final fix = location.fix;
    final guidance = fix != null && fix.freshAt(now)
        ? Guidance(fix, place)
        : null;
    final directional =
        guidance != null &&
        !guidance.nearby &&
        !guidance.poor &&
        location.headingFresh(now);
    final angle = directional
        ? turnAngle(guidance.bearing, location.heading!)
        : 0.0;
    final color = Color(place.color);
    final style = ref.watch(directionStyleProvider);
    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 8, 26, 14),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 508),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: deleting ? null : () => Navigator.pop(context),
                  child: const Text('结束寻找', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ),
        ),
      ),
      appBar: AppBar(
        title: const Text('寻找定位点', style: TextStyle(fontSize: 17)),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            tooltip: '管理定位点',
            enabled: !deleting,
            onSelected: (action) {
              if (action == 'delete') {
                unawaited(remove(place));
              } else {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: panel(context),
                  builder: (_) => PlaceEditor(place: place),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑名称和备注')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('删除定位点', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LayoutBuilder(
              builder: (c, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(26, 12, 26, 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          place.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '保存于 ${stamp(place.createdAt)}',
                          style: TextStyle(color: muted(context), fontSize: 13),
                        ),
                        const SizedBox(height: 18),
                        SegmentedButton<DirectionStyle>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: DirectionStyle.arrow,
                              label: Text('箭头'),
                            ),
                            ButtonSegment(
                              value: DirectionStyle.highlight,
                              label: Text('方向高亮'),
                            ),
                          ],
                          selected: {style},
                          onSelectionChanged: (values) async {
                            try {
                              await ref
                                  .read(directionStyleProvider.notifier)
                                  .choose(values.single);
                            } catch (_) {
                              if (context.mounted) {
                                message(context, '显示方式本次已切换，偏好保存失败');
                              }
                            }
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: math.min(240, constraints.maxWidth - 64),
                          height: math.min(240, constraints.maxWidth - 64),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: color.withValues(alpha: .12),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: .86,
                                heightFactor: .86,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: color.withValues(alpha: .09),
                                  ),
                                ),
                              ),
                              if (guidance?.nearby == true)
                                Icon(
                                  Icons.radar_rounded,
                                  size: 110,
                                  color: color,
                                )
                              else if (directional)
                                DynamicDirection(
                                  angle: angle,
                                  color: color,
                                  style: style,
                                )
                              else
                                Icon(
                                  guidance == null
                                      ? Icons.location_searching_rounded
                                      : Icons.explore_outlined,
                                  size: 92,
                                  color: color.withValues(alpha: .6),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        if (guidance != null) ...[
                          Text(
                            guidance.distance.round().toString(),
                            style: const TextStyle(
                              fontSize: 68,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -3,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '米 · 直线距离',
                            style: TextStyle(
                              fontSize: 15,
                              color: muted(context),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            guidance.poor
                                ? '定位精度较低'
                                : guidance.nearby
                                ? '已进入定位点附近'
                                : directional
                                ? turnLabel(angle)
                                : '目标在${cardinal(guidance.bearing)}方',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 23,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            guidance.poor
                                ? '到开阔处等待定位改善'
                                : guidance.nearby
                                ? '已进入误差范围，请结合备注找一找'
                                : directional
                                ? style == DirectionStyle.arrow
                                      ? '转动手机，跟随箭头方向'
                                      : '朝向高亮区域，正对目标时圆环亮起'
                                : '请正常握持并远离金属，或按地理方位寻找',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: muted(context),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '当前位置 ±${fix!.accuracy.ceil()} 米 · 保存位置 ±${place.fix.accuracy.ceil()} 米',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: muted(context),
                            ),
                          ),
                        ] else ...[
                          const Text(
                            '等待定位',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const LocationNotice(),
                        ],
                        const SizedBox(height: 30),
                        if (place.note.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: panel(context),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.notes_rounded,
                                  size: 20,
                                  color: muted(context),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(place.note)),
                              ],
                            ),
                          ),
                      ],
                    ),
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

class DynamicDirection extends StatefulWidget {
  final double angle;
  final Color color;
  final DirectionStyle style;
  const DynamicDirection({
    super.key,
    required this.angle,
    required this.color,
    required this.style,
  });
  @override
  State<DynamicDirection> createState() => _DynamicDirectionState();
}

class _DynamicDirectionState extends State<DynamicDirection> {
  late double continuous = widget.angle;
  @override
  void didUpdateWidget(DynamicDirection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 跨越北向的 359° / 0° 时沿最短路径旋转。
    continuous += turnAngle(widget.angle, continuous);
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: continuous, end: continuous),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 85),
    builder: (_, value, _) => widget.style == DirectionStyle.arrow
        ? Transform.rotate(
            angle: value * math.pi / 180,
            child: Icon(
              Icons.arrow_upward_rounded,
              color: widget.color,
              size: 132,
            ),
          )
        : SizedBox.expand(
            child: CustomPaint(
              painter: DirectionHighlightPainter(value, widget.color),
              child: Center(
                child: Icon(
                  turnAngle(value, 0).abs() <= 18
                      ? Icons.check_rounded
                      : Icons.my_location_rounded,
                  size: 70,
                  color: widget.color,
                ),
              ),
            ),
          ),
  );
}

class DirectionHighlightPainter extends CustomPainter {
  final double angle;
  final Color color;
  DirectionHighlightPainter(this.angle, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 9;
    final aligned = turnAngle(angle, 0).abs() <= 18;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    if (aligned) {
      paint.color = color.withValues(alpha: .3);
      canvas.drawCircle(center, radius, paint);
    }
    paint.color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      angle * math.pi / 180 - math.pi / 2 - .38,
      .76,
      false,
      paint,
    );
    paint
      ..strokeWidth = 3
      ..color = color.withValues(alpha: .55);
    canvas.drawLine(
      Offset(center.dx, center.dy - radius + 18),
      Offset(center.dx, center.dy - radius + 30),
      paint,
    );
  }

  @override
  bool shouldRepaint(DirectionHighlightPainter oldDelegate) =>
      angle != oldDelegate.angle || color != oldDelegate.color;
}
