import 'package:flutter/material.dart';

// 图标数据类，包含图标名称和对应的IconData
class IconDataItem {
  final String name;
  final IconData icon;

  const IconDataItem({
    required this.name,
    required this.icon,
  });
}

// 图标常量类，包含所有可用图标和映射逻辑
class IconConstants {
  // 购物相关图标
  static const List<IconDataItem> shoppingIcons = [
    IconDataItem(name: 'shopping_cart', icon: Icons.shopping_cart),
    IconDataItem(name: 'shopping_bag', icon: Icons.shopping_bag),
    IconDataItem(name: 'store', icon: Icons.store),
    IconDataItem(name: 'local_grocery_store', icon: Icons.local_grocery_store),
    IconDataItem(name: 'store_mall_directory', icon: Icons.store_mall_directory),
  ];

  // 餐饮相关图标
  static const List<IconDataItem> foodIcons = [
    IconDataItem(name: 'restaurant', icon: Icons.restaurant),
    IconDataItem(name: 'local_cafe', icon: Icons.local_cafe),
    IconDataItem(name: 'fastfood', icon: Icons.fastfood),
    IconDataItem(name: 'wine_bar', icon: Icons.wine_bar),
    IconDataItem(name: 'cake', icon: Icons.cake),
    IconDataItem(name: 'lunch_dining', icon: Icons.lunch_dining),
    IconDataItem(name: 'dinner_dining', icon: Icons.dinner_dining),
    IconDataItem(name: 'bakery_dining', icon: Icons.bakery_dining),
    IconDataItem(name: 'icecream', icon: Icons.icecream),
  ];

  // 交通相关图标
  static const List<IconDataItem> transportIcons = [
    IconDataItem(name: 'directions_car', icon: Icons.directions_car),
    IconDataItem(name: 'directions_bus', icon: Icons.directions_bus),
    IconDataItem(name: 'train', icon: Icons.train),
    IconDataItem(name: 'subway', icon: Icons.subway),
    IconDataItem(name: 'directions_bike', icon: Icons.directions_bike),
    IconDataItem(name: 'local_gas_station', icon: Icons.local_gas_station),
    IconDataItem(name: 'flight', icon: Icons.flight),
    IconDataItem(name: 'local_taxi', icon: Icons.local_taxi),
    IconDataItem(name: 'directions_boat', icon: Icons.directions_boat),
    IconDataItem(name: 'two_wheeler', icon: Icons.two_wheeler),
  ];

  // 生活服务图标
  static const List<IconDataItem> lifeServiceIcons = [
    IconDataItem(name: 'home', icon: Icons.home),
    IconDataItem(name: 'local_laundry_service', icon: Icons.local_laundry_service),
    IconDataItem(name: 'cut', icon: Icons.content_cut),
    IconDataItem(name: 'spa', icon: Icons.spa),
    IconDataItem(name: 'pets', icon: Icons.pets),
    IconDataItem(name: 'child_care', icon: Icons.child_care),
    IconDataItem(name: 'cleaning_services', icon: Icons.cleaning_services),
    IconDataItem(name: 'dry_cleaning', icon: Icons.dry_cleaning),
    IconDataItem(name: 'water_drop', icon: Icons.water_drop),
    IconDataItem(name: 'electric_bolt', icon: Icons.electric_bolt),
    IconDataItem(name: 'wifi', icon: Icons.wifi),
    IconDataItem(name: 'phone', icon: Icons.phone),
  ];

  // 娱乐相关图标
  static const List<IconDataItem> entertainmentIcons = [
    IconDataItem(name: 'movie', icon: Icons.movie),
    IconDataItem(name: 'music_note', icon: Icons.music_note),
    IconDataItem(name: 'sports_esports', icon: Icons.sports_esports),
    IconDataItem(name: 'sports_soccer', icon: Icons.sports_soccer),
    IconDataItem(name: 'fitness_center', icon: Icons.fitness_center),
    IconDataItem(name: 'games', icon: Icons.games),
    IconDataItem(name: 'theater_comedy', icon: Icons.theater_comedy),
    IconDataItem(name: 'sports_basketball', icon: Icons.sports_basketball),
    IconDataItem(name: 'pool', icon: Icons.pool),
    IconDataItem(name: 'golf_course', icon: Icons.golf_course),
  ];

  // 医疗健康图标
  static const List<IconDataItem> medicalIcons = [
    IconDataItem(name: 'local_hospital', icon: Icons.local_hospital),
    IconDataItem(name: 'medical_services', icon: Icons.medical_services),
    IconDataItem(name: 'medication', icon: Icons.medication),
    IconDataItem(name: 'favorite', icon: Icons.favorite),
    IconDataItem(name: 'healing', icon: Icons.healing),
    IconDataItem(name: 'vaccines', icon: Icons.vaccines),
  ];

  // 教育图标
  static const List<IconDataItem> educationIcons = [
    IconDataItem(name: 'school', icon: Icons.school),
    IconDataItem(name: 'menu_book', icon: Icons.menu_book),
    IconDataItem(name: 'library_books', icon: Icons.library_books),
    IconDataItem(name: 'auto_stories', icon: Icons.auto_stories),
    IconDataItem(name: 'psychology', icon: Icons.psychology),
  ];

  // 金融相关图标
  static const List<IconDataItem> financeIcons = [
    IconDataItem(name: 'account_balance', icon: Icons.account_balance),
    IconDataItem(name: 'payments', icon: Icons.payments),
    IconDataItem(name: 'credit_card', icon: Icons.credit_card),
    IconDataItem(name: 'attach_money', icon: Icons.attach_money),
    IconDataItem(name: 'savings', icon: Icons.savings),
    IconDataItem(name: 'trending_up', icon: Icons.trending_up),
    IconDataItem(name: 'receipt', icon: Icons.receipt),
    IconDataItem(name: 'account_balance_wallet', icon: Icons.account_balance_wallet),
    IconDataItem(name: 'monetization_on', icon: Icons.monetization_on),
    IconDataItem(name: 'currency_exchange', icon: Icons.currency_exchange),
  ];

  // 工作相关图标
  static const List<IconDataItem> workIcons = [
    IconDataItem(name: 'work', icon: Icons.work),
    IconDataItem(name: 'business', icon: Icons.business),
    IconDataItem(name: 'computer', icon: Icons.computer),
    IconDataItem(name: 'laptop', icon: Icons.laptop),
    IconDataItem(name: 'print', icon: Icons.print),
  ];

  // 通讯设备图标
  static const List<IconDataItem> communicationIcons = [
    IconDataItem(name: 'phone_android', icon: Icons.phone_android),
    IconDataItem(name: 'phone_iphone', icon: Icons.phone_iphone),
    IconDataItem(name: 'tablet', icon: Icons.tablet),
    IconDataItem(name: 'watch', icon: Icons.watch),
    IconDataItem(name: 'headphones', icon: Icons.headphones),
  ];

  // 服装配饰图标
  static const List<IconDataItem> clothingIcons = [
    IconDataItem(name: 'checkroom', icon: Icons.checkroom),
    IconDataItem(name: 'diamond', icon: Icons.diamond),
  ];

  // 其他图标
  static const List<IconDataItem> otherIcons = [
    IconDataItem(name: 'gift', icon: Icons.card_giftcard),
    IconDataItem(name: 'travel_explore', icon: Icons.travel_explore),
    IconDataItem(name: 'category', icon: Icons.category),
    IconDataItem(name: 'more_horiz', icon: Icons.more_horiz),
    IconDataItem(name: 'beach_access', icon: Icons.beach_access),
    IconDataItem(name: 'outdoor_grill', icon: Icons.outdoor_grill),
    IconDataItem(name: 'hotel', icon: Icons.hotel),
    IconDataItem(name: 'luggage', icon: Icons.luggage),
    IconDataItem(name: 'stars', icon: Icons.stars),
  ];

  // 所有图标的列表
  static List<IconDataItem> get allIcons {
    return [
      ...shoppingIcons,
      ...foodIcons,
      ...transportIcons,
      ...lifeServiceIcons,
      ...entertainmentIcons,
      ...medicalIcons,
      ...educationIcons,
      ...financeIcons,
      ...workIcons,
      ...communicationIcons,
      ...clothingIcons,
      ...otherIcons,
    ];
  }

  // 图标名称到IconData的映射
  static IconData getIconFromString(String iconName) {
    final iconMap = <String, IconData>{
      for (var icon in allIcons) icon.name: icon.icon,
    };
    return iconMap[iconName] ?? Icons.category;
  }

  // 图标分类数据，用于UI显示
  static const Map<String, List<IconDataItem>> iconCategories = {
    '购物': shoppingIcons,
    '餐饮': foodIcons,
    '交通': transportIcons,
    '生活服务': lifeServiceIcons,
    '娱乐': entertainmentIcons,
    '医疗健康': medicalIcons,
    '教育': educationIcons,
    '金融': financeIcons,
    '工作': workIcons,
    '通讯设备': communicationIcons,
    '服装配饰': clothingIcons,
    '其他': otherIcons,
  };
}
