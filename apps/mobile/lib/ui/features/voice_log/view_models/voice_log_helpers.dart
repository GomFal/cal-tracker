import '../../../../domain/models/nutrition_models.dart';

/// Normalize a text value for case-insensitive comparison.
String normalizedText(String value) => value.trim().toLowerCase();

/// Returns true if [a] and [b] represent the same meal item by identity or
/// by structural equality.
bool sameMealItem(MealItem a, MealItem b) {
  if (a.externalId != null && b.externalId != null) {
    return a.externalId == b.externalId &&
        a.externalSource == b.externalSource;
  }
  return a.name == b.name &&
      a.source == b.source &&
      a.quantity == b.quantity &&
      a.unit == b.unit;
}

bool sameNumber(double a, double b) => (a - b).abs() < 0.05;

/// Returns true if two [MealProposal]s are materially equal — same title
/// text, same nutrition, same items.
bool mealProposalsMateriallyEqual(MealProposal a, MealProposal b) {
  return normalizedText(a.title) == normalizedText(b.title) &&
      a.nutrition.calories == b.nutrition.calories &&
      sameNumber(a.nutrition.proteinGrams, b.nutrition.proteinGrams) &&
      sameNumber(a.nutrition.carbsGrams, b.nutrition.carbsGrams) &&
      sameNumber(a.nutrition.fatGrams, b.nutrition.fatGrams) &&
      mealItemListsMateriallyEqual(a.items, b.items);
}

bool mealItemListsMateriallyEqual(List<MealItem> a, List<MealItem> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (!mealItemsMateriallyEqual(a[index], b[index])) return false;
  }
  return true;
}

bool mealItemsMateriallyEqual(MealItem a, MealItem b) {
  final hasExternalIdentity = a.externalId != null ||
      b.externalId != null ||
      a.externalSource != null ||
      b.externalSource != null;
  if (hasExternalIdentity &&
      (a.externalId != b.externalId ||
          a.externalSource != b.externalSource)) {
    return false;
  }
  return normalizedText(a.name) == normalizedText(b.name) &&
      normalizedText(a.unit) == normalizedText(b.unit) &&
      sameNumber(a.quantity, b.quantity) &&
      a.calories == b.calories &&
      sameNumber(a.proteinGrams, b.proteinGrams) &&
      sameNumber(a.carbsGrams, b.carbsGrams) &&
      sameNumber(a.fatGrams, b.fatGrams);
}

/// Builds a human-readable phrase from a list of [items] for submitting to
/// the proposal creation endpoint.
String manualFoodPhrase(List<MealItem> items) {
  return items
      .map(
        (item) =>
            '${formatQuantityForPhrase(item.quantity)} ${item.unit} ${item.name}',
      )
      .join(', ');
}

String formatQuantityForPhrase(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}

/// Merges two lists of candidate groups, keeping the latest per
/// [candidateGroupKey]. Later groups replace earlier ones with the same key.
List<FoodCandidateGroup>? mergeCandidateGroups(
  List<FoodCandidateGroup>? existing,
  List<FoodCandidateGroup>? incoming,
) {
  if (existing == null || existing.isEmpty) return incoming;
  if (incoming == null || incoming.isEmpty) return existing;
  final merged = <String, FoodCandidateGroup>{
    for (final group in existing) candidateGroupKey(group): group,
  };
  for (final group in incoming) {
    merged[candidateGroupKey(group)] = group;
  }
  return merged.values.toList(growable: false);
}

/// Builds a stable key for a candidate group over its mention fields.
String candidateGroupKey(FoodCandidateGroup group) {
  final mention = group.mention;
  return [
    mention.originalText,
    mention.canonicalName,
    mention.quantity.toStringAsFixed(3),
    mention.unit,
  ].join('|');
}

/// Builds the default candidate selections map by matching resolved items
/// against the candidates available in each group.
Map<String, MealItem> defaultCandidateSelections({
  required List<FoodCandidateGroup>? groups,
  required List<MealItem>? resolvedItems,
}) {
  if (groups == null || resolvedItems == null) return const {};
  final selections = <String, MealItem>{};
  for (final group in groups) {
    final resolvedItem = resolvedItemForGroup(group, resolvedItems);
    if (resolvedItem == null) continue;
    final candidate = matchingCandidateForResolvedItem(group, resolvedItem);
    if (candidate != null) {
      selections[candidateGroupKey(group)] = candidate;
    }
  }
  return selections;
}

/// Returns a synthesized item list where resolved items are replaced by their
/// candidate selections, and any group without a corresponding resolved item
/// is appended.
List<MealItem> itemsWithCandidateSelections({
  required List<FoodCandidateGroup> groups,
  required Map<String, MealItem> selections,
  required List<MealItem> resolvedItems,
}) {
  final selectedItems = <MealItem>[];
  final representedGroupKeys = <String>{};

  for (final item in resolvedItems) {
    final group = groupForResolvedItem(item, groups);
    if (group == null) {
      selectedItems.add(item);
      continue;
    }

    final key = candidateGroupKey(group);
    representedGroupKeys.add(key);
    selectedItems.add(selections[key] ?? item);
  }

  for (final group in groups) {
    final key = candidateGroupKey(group);
    if (representedGroupKeys.contains(key)) continue;
    final selected = selections[key];
    if (selected != null) selectedItems.add(selected);
  }

  return selectedItems;
}

/// Returns a copy of [proposalItems] with any item that matches a candidate
/// group replaced by its selection in [selections].
List<MealItem> proposalItemsWithCandidateSelections({
  required List<MealItem> proposalItems,
  required List<FoodCandidateGroup> groups,
  required Map<String, MealItem> selections,
}) {
  final items = [...proposalItems];
  for (final group in groups) {
    final selected = selections[candidateGroupKey(group)];
    if (selected == null) continue;
    final index = items.indexWhere(
      (item) => resolvedItemMatchesGroup(item, group),
    );
    if (index >= 0) {
      items[index] = selected;
    } else if (!items.any((item) => sameMealItem(item, selected))) {
      items.add(selected);
    }
  }
  return items;
}

/// Returns true if [group] needs a candidate selection — either it has no
/// candidates or no resolved item matches it.
bool needsCandidateSelection(
  FoodCandidateGroup group,
  List<MealItem> resolvedItems,
) {
  if (group.candidates.isEmpty) return true;
  return resolvedItemForGroup(group, resolvedItems) == null;
}

/// Finds the first resolved item whose mention matches [group].
MealItem? resolvedItemForGroup(
  FoodCandidateGroup group,
  List<MealItem> resolvedItems,
) {
  for (final item in resolvedItems) {
    if (resolvedItemMatchesGroup(item, group)) return item;
  }
  return null;
}

/// Finds the first candidate group that matches [item].
FoodCandidateGroup? groupForResolvedItem(
  MealItem item,
  List<FoodCandidateGroup> groups,
) {
  for (final group in groups) {
    if (resolvedItemMatchesGroup(item, group)) return group;
  }
  return null;
}

/// Returns true if [item]'s mention matches [group] by canonical name,
/// quantity, and unit.
bool resolvedItemMatchesGroup(MealItem item, FoodCandidateGroup group) {
  return item.canonicalName == group.mention.canonicalName &&
      item.quantity == group.mention.quantity &&
      item.unit == group.mention.unit;
}

/// Finds the first candidate in [group] that equals [resolvedItem] by
/// [sameMealItem].
MealItem? matchingCandidateForResolvedItem(
  FoodCandidateGroup group,
  MealItem resolvedItem,
) {
  for (final candidate in group.candidates) {
    if (sameMealItem(candidate, resolvedItem)) return candidate;
  }
  return null;
}
