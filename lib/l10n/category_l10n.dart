import '../models/category.dart' as model;
import '../data/local/app_database.dart' show Category;
import '../data/local/builtin_categories.dart';
import 'app_localizations.dart';

/// 分类显示名解析：只认 `nameKey` 或分类 ID，绝不按名称字符串猜语言。
///
/// - 内置分类：库内 `name_key` 非空，按 key 取当前语言词条；
/// - 自建分类：`name_key` 为 NULL，显示用户录入的原文；
/// - key 未知（旧数据/降级）同样回落原文，保证不崩、不空白。
///
/// 所有页面渲染分类名都必须经过这里，禁止直接使用 `category.name`。
class CategoryL10n {
  CategoryL10n._();

  static String display(
    AppLocalizations l10n, {
    String? nameKey,
    required String fallbackName,
  }) {
    switch (nameKey) {
      case 'categoryDining':
        return l10n.categoryDining;
      case 'categoryDaily':
        return l10n.categoryDaily;
      case 'categoryShopping':
        return l10n.categoryShopping;
      case 'categoryOnlineShopping':
        return l10n.categoryOnlineShopping;
      case 'categoryTransport':
        return l10n.categoryTransport;
      case 'categoryHousing':
        return l10n.categoryHousing;
      case 'categoryUtilities':
        return l10n.categoryUtilities;
      case 'categoryTelecom':
        return l10n.categoryTelecom;
      case 'categoryEntertainment':
        return l10n.categoryEntertainment;
      case 'categoryMedical':
        return l10n.categoryMedical;
      case 'categoryInsurance':
        return l10n.categoryInsurance;
      case 'categoryEducation':
        return l10n.categoryEducation;
      case 'categoryTravel':
        return l10n.categoryTravel;
      case 'categoryServices':
        return l10n.categoryServices;
      case 'categoryChildcare':
        return l10n.categoryChildcare;
      case 'categoryPets':
        return l10n.categoryPets;
      case 'categorySocial':
        return l10n.categorySocial;
      case 'categorySalary':
        return l10n.categorySalary;
      case 'categoryBonus':
        return l10n.categoryBonus;
      case 'categoryPartTime':
        return l10n.categoryPartTime;
      case 'categoryRedPacket':
        return l10n.categoryRedPacket;
      case 'categoryGiftMoney':
        return l10n.categoryGiftMoney;
      case 'categoryReimbursement':
        return l10n.categoryReimbursement;
      case 'categoryOther':
        return l10n.categoryOther;
      case 'categoryUncategorized':
        return l10n.categoryUncategorized;
      default:
        return fallbackName;
    }
  }

  /// 传输层 DTO（models.Category）
  static String ofModel(AppLocalizations l10n, model.Category category) =>
      display(l10n, nameKey: category.nameKey, fallbackName: category.name);

  /// 本地表行（drift Category）
  static String ofRow(AppLocalizations l10n, Category category) =>
      display(l10n, nameKey: category.nameKey, fallbackName: category.name);

  /// 仅有 ID 的场景：内置分类按固定常量反查 nameKey，自建分类回落原文
  static String ofId(
    AppLocalizations l10n,
    String categoryId, {
    required String fallbackName,
  }) {
    final nameKey = BuiltinCategories.byId(categoryId)?.nameKey;
    return display(l10n, nameKey: nameKey, fallbackName: fallbackName);
  }
}
