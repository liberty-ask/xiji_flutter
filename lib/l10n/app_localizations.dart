import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'CN'),
    Locale('zh', 'TW')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'XiJi'**
  String get appTitle;

  /// No description provided for @welcomeSlogan.
  ///
  /// In en, this message translates to:
  /// **'Warm Family, Joint Accounting'**
  String get welcomeSlogan;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @calendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @addTransaction.
  ///
  /// In en, this message translates to:
  /// **'Add Transaction'**
  String get addTransaction;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password'**
  String get forgotPassword;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get fontSize;

  /// No description provided for @familyInvite.
  ///
  /// In en, this message translates to:
  /// **'Family Invite'**
  String get familyInvite;

  /// No description provided for @audit.
  ///
  /// In en, this message translates to:
  /// **'Audit'**
  String get audit;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @importBills.
  ///
  /// In en, this message translates to:
  /// **'Import Bills'**
  String get importBills;

  /// No description provided for @categoryManage.
  ///
  /// In en, this message translates to:
  /// **'Category Manage'**
  String get categoryManage;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get followSystem;

  /// No description provided for @simplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get simplifiedChinese;

  /// No description provided for @traditionalChinese.
  ///
  /// In en, this message translates to:
  /// **'Traditional Chinese'**
  String get traditionalChinese;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// No description provided for @info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get info;

  /// No description provided for @successfullySaved.
  ///
  /// In en, this message translates to:
  /// **'has been saved'**
  String get successfullySaved;

  /// No description provided for @recentActivities.
  ///
  /// In en, this message translates to:
  /// **'Recent Activities'**
  String get recentActivities;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @week.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get week;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get month;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get year;

  /// No description provided for @totalIncome.
  ///
  /// In en, this message translates to:
  /// **'Total Income'**
  String get totalIncome;

  /// No description provided for @totalExpense.
  ///
  /// In en, this message translates to:
  /// **'Total Expense'**
  String get totalExpense;

  /// No description provided for @netIncome.
  ///
  /// In en, this message translates to:
  /// **'Net Income'**
  String get netIncome;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @trend.
  ///
  /// In en, this message translates to:
  /// **'Trend'**
  String get trend;

  /// No description provided for @member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @noData.
  ///
  /// In en, this message translates to:
  /// **'No Data'**
  String get noData;

  /// No description provided for @expenseDetails.
  ///
  /// In en, this message translates to:
  /// **'Expense Details'**
  String get expenseDetails;

  /// No description provided for @incomeDetails.
  ///
  /// In en, this message translates to:
  /// **'Income Details'**
  String get incomeDetails;

  /// No description provided for @expense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expense;

  /// No description provided for @income.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get income;

  /// No description provided for @themeSaved.
  ///
  /// In en, this message translates to:
  /// **'Theme Saved'**
  String get themeSaved;

  /// No description provided for @themePreview.
  ///
  /// In en, this message translates to:
  /// **'Theme Preview'**
  String get themePreview;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get themeMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @selectTheme.
  ///
  /// In en, this message translates to:
  /// **'Select Theme'**
  String get selectTheme;

  /// No description provided for @availableBalance.
  ///
  /// In en, this message translates to:
  /// **'Available Balance'**
  String get availableBalance;

  /// No description provided for @monthlyIncome.
  ///
  /// In en, this message translates to:
  /// **'Monthly Income'**
  String get monthlyIncome;

  /// No description provided for @monthlyExpense.
  ///
  /// In en, this message translates to:
  /// **'Monthly Expense'**
  String get monthlyExpense;

  /// No description provided for @voiceTransaction.
  ///
  /// In en, this message translates to:
  /// **'Voice Transaction'**
  String get voiceTransaction;

  /// No description provided for @manualTransaction.
  ///
  /// In en, this message translates to:
  /// **'Manual Transaction'**
  String get manualTransaction;

  /// No description provided for @budgetProgress.
  ///
  /// In en, this message translates to:
  /// **'Budget Progress'**
  String get budgetProgress;

  /// No description provided for @todayExpense.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Expense'**
  String get todayExpense;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @noTrendData.
  ///
  /// In en, this message translates to:
  /// **'No trend data available'**
  String get noTrendData;

  /// No description provided for @averageIncome.
  ///
  /// In en, this message translates to:
  /// **'Average Income'**
  String get averageIncome;

  /// No description provided for @averageExpense.
  ///
  /// In en, this message translates to:
  /// **'Average Expense'**
  String get averageExpense;

  /// No description provided for @noMemberData.
  ///
  /// In en, this message translates to:
  /// **'No member data available'**
  String get noMemberData;

  /// No description provided for @noDateData.
  ///
  /// In en, this message translates to:
  /// **'No date data available'**
  String get noDateData;

  /// No description provided for @sunday.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get sunday;

  /// No description provided for @monday.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get monday;

  /// No description provided for @tuesday.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get tuesday;

  /// No description provided for @wednesday.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get wednesday;

  /// No description provided for @thursday.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get thursday;

  /// No description provided for @friday.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get friday;

  /// No description provided for @saturday.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get saturday;

  /// No description provided for @transactions.
  ///
  /// In en, this message translates to:
  /// **'transactions'**
  String get transactions;

  /// No description provided for @totalExpenseLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Expense'**
  String get totalExpenseLabel;

  /// No description provided for @totalIncomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Income'**
  String get totalIncomeLabel;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select Date'**
  String get selectDate;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yearLabel.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get yearLabel;

  /// No description provided for @monthLabel.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get monthLabel;

  /// No description provided for @dayLabel.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get dayLabel;

  /// No description provided for @confirmButton.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmButton;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @net.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get net;

  /// No description provided for @incomeAmount.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get incomeAmount;

  /// No description provided for @expenseAmount.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expenseAmount;

  /// No description provided for @transactionDetail.
  ///
  /// In en, this message translates to:
  /// **'Transaction Detail'**
  String get transactionDetail;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @counterparty.
  ///
  /// In en, this message translates to:
  /// **'Counterparty'**
  String get counterparty;

  /// No description provided for @note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @monthlySurplus.
  ///
  /// In en, this message translates to:
  /// **'Monthly Surplus'**
  String get monthlySurplus;

  /// No description provided for @selectDateToViewTransactions.
  ///
  /// In en, this message translates to:
  /// **'Please select a date to view transactions'**
  String get selectDateToViewTransactions;

  /// No description provided for @noTransactionRecords.
  ///
  /// In en, this message translates to:
  /// **'No transaction records'**
  String get noTransactionRecords;

  /// No description provided for @noNicknameSet.
  ///
  /// In en, this message translates to:
  /// **'No nickname set'**
  String get noNicknameSet;

  /// No description provided for @financialManagement.
  ///
  /// In en, this message translates to:
  /// **'FINANCIAL MANAGEMENT'**
  String get financialManagement;

  /// No description provided for @billImport.
  ///
  /// In en, this message translates to:
  /// **'Bill Import'**
  String get billImport;

  /// No description provided for @billImportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Supports WeChat/Alipay bill CSV'**
  String get billImportSubtitle;

  /// No description provided for @monthlyBudget.
  ///
  /// In en, this message translates to:
  /// **'Monthly Budget'**
  String get monthlyBudget;

  /// No description provided for @monthlyBudgetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set financial goals'**
  String get monthlyBudgetSubtitle;

  /// No description provided for @categoryManagement.
  ///
  /// In en, this message translates to:
  /// **'Category Management'**
  String get categoryManagement;

  /// No description provided for @categoryManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage income and expense categories'**
  String get categoryManagementSubtitle;

  /// No description provided for @familySettings.
  ///
  /// In en, this message translates to:
  /// **'FAMILY SETTINGS'**
  String get familySettings;

  /// No description provided for @memberManagement.
  ///
  /// In en, this message translates to:
  /// **'Member Management'**
  String get memberManagement;

  /// No description provided for @memberManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions and nickname management'**
  String get memberManagementSubtitle;

  /// No description provided for @joinAudit.
  ///
  /// In en, this message translates to:
  /// **'Join Audit'**
  String get joinAudit;

  /// No description provided for @appearanceSettings.
  ///
  /// In en, this message translates to:
  /// **'APPEARANCE SETTINGS'**
  String get appearanceSettings;

  /// No description provided for @themeSettings.
  ///
  /// In en, this message translates to:
  /// **'Theme Settings'**
  String get themeSettings;

  /// No description provided for @themeSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose theme color'**
  String get themeSettingsSubtitle;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get themeColor;

  /// No description provided for @themeColorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select app theme color'**
  String get themeColorSubtitle;

  /// No description provided for @themeGreen.
  ///
  /// In en, this message translates to:
  /// **'Fresh Green'**
  String get themeGreen;

  /// No description provided for @themeBlue.
  ///
  /// In en, this message translates to:
  /// **'Sky Blue'**
  String get themeBlue;

  /// No description provided for @themePurple.
  ///
  /// In en, this message translates to:
  /// **'Elegant Purple'**
  String get themePurple;

  /// No description provided for @themeOrange.
  ///
  /// In en, this message translates to:
  /// **'Warm Orange'**
  String get themeOrange;

  /// No description provided for @themePink.
  ///
  /// In en, this message translates to:
  /// **'Romantic Pink'**
  String get themePink;

  /// No description provided for @themeCyan.
  ///
  /// In en, this message translates to:
  /// **'Ocean Cyan'**
  String get themeCyan;

  /// No description provided for @languageSettings.
  ///
  /// In en, this message translates to:
  /// **'Language Settings'**
  String get languageSettings;

  /// No description provided for @languageSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select app language'**
  String get languageSettingsSubtitle;

  /// No description provided for @fontSizeSettings.
  ///
  /// In en, this message translates to:
  /// **'Font Size Settings'**
  String get fontSizeSettings;

  /// No description provided for @fontSizeSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust text size'**
  String get fontSizeSettingsSubtitle;

  /// No description provided for @securityCenter.
  ///
  /// In en, this message translates to:
  /// **'SECURITY CENTER'**
  String get securityCenter;

  /// No description provided for @changeLoginPassword.
  ///
  /// In en, this message translates to:
  /// **'Change Login Password'**
  String get changeLoginPassword;

  /// No description provided for @exitCurrentFamily.
  ///
  /// In en, this message translates to:
  /// **'Exit Current Family'**
  String get exitCurrentFamily;

  /// No description provided for @confirmLogout.
  ///
  /// In en, this message translates to:
  /// **'Confirm Logout'**
  String get confirmLogout;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get logoutConfirmMessage;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @logoutButton.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logoutButton;

  /// No description provided for @selectDateRange.
  ///
  /// In en, this message translates to:
  /// **'Select Date Range'**
  String get selectDateRange;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'Start Date'**
  String get startDate;

  /// No description provided for @endDate.
  ///
  /// In en, this message translates to:
  /// **'End Date'**
  String get endDate;

  /// No description provided for @clearDate.
  ///
  /// In en, this message translates to:
  /// **'Clear Date'**
  String get clearDate;

  /// No description provided for @searchKeyword.
  ///
  /// In en, this message translates to:
  /// **'Search keywords...'**
  String get searchKeyword;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTime;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get confirmDelete;

  /// No description provided for @confirmDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this transaction record? This operation cannot be undone.'**
  String get confirmDeleteMessage;

  /// No description provided for @deleteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Delete successful'**
  String get deleteSuccess;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed'**
  String get deleteFailed;

  /// No description provided for @editTransaction.
  ///
  /// In en, this message translates to:
  /// **'Edit Transaction'**
  String get editTransaction;

  /// No description provided for @pleaseEnterAmount.
  ///
  /// In en, this message translates to:
  /// **'Please enter amount'**
  String get pleaseEnterAmount;

  /// No description provided for @pleaseEnterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get pleaseEnterValidAmount;

  /// No description provided for @amountMustBeGreaterThanZero.
  ///
  /// In en, this message translates to:
  /// **'Amount must be greater than 0'**
  String get amountMustBeGreaterThanZero;

  /// No description provided for @noteOptional.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get noteOptional;

  /// No description provided for @pleaseSelectCategory.
  ///
  /// In en, this message translates to:
  /// **'Please select a category'**
  String get pleaseSelectCategory;

  /// No description provided for @editSuccess.
  ///
  /// In en, this message translates to:
  /// **'Edit successful'**
  String get editSuccess;

  /// No description provided for @editFailed.
  ///
  /// In en, this message translates to:
  /// **'Edit failed'**
  String get editFailed;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'to'**
  String get to;

  /// No description provided for @pressAndHoldToSpeak.
  ///
  /// In en, this message translates to:
  /// **'Press and hold to speak'**
  String get pressAndHoldToSpeak;

  /// No description provided for @releaseToStop.
  ///
  /// In en, this message translates to:
  /// **'Release to stop'**
  String get releaseToStop;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processing;

  /// No description provided for @editRecognizedText.
  ///
  /// In en, this message translates to:
  /// **'Edit Recognized Text'**
  String get editRecognizedText;

  /// No description provided for @pleaseEnterOrEditText.
  ///
  /// In en, this message translates to:
  /// **'Please enter or edit recognized text'**
  String get pleaseEnterOrEditText;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @voiceRecognitionFailed.
  ///
  /// In en, this message translates to:
  /// **'Voice recognition failed'**
  String get voiceRecognitionFailed;

  /// No description provided for @networkConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Network connection error, please check network and retry'**
  String get networkConnectionError;

  /// No description provided for @recognitionTextEmpty.
  ///
  /// In en, this message translates to:
  /// **'Recognition text is empty, please re-enter'**
  String get recognitionTextEmpty;

  /// No description provided for @recordingCanceled.
  ///
  /// In en, this message translates to:
  /// **'Recording canceled'**
  String get recordingCanceled;

  /// No description provided for @enterEditMode.
  ///
  /// In en, this message translates to:
  /// **'Enter edit mode'**
  String get enterEditMode;

  /// No description provided for @voiceRecognitionServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Voice Recognition Service Unavailable'**
  String get voiceRecognitionServiceUnavailable;

  /// No description provided for @pleaseCheckTheFollowing.
  ///
  /// In en, this message translates to:
  /// **'Please check the following:'**
  String get pleaseCheckTheFollowing;

  /// No description provided for @microphonePermission.
  ///
  /// In en, this message translates to:
  /// **'Whether microphone permission is granted'**
  String get microphonePermission;

  /// No description provided for @speechRecognitionService.
  ///
  /// In en, this message translates to:
  /// **'Whether speech recognition service is installed'**
  String get speechRecognitionService;

  /// No description provided for @tryRestartingApp.
  ///
  /// In en, this message translates to:
  /// **'Try restarting the app'**
  String get tryRestartingApp;

  /// No description provided for @checkSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Check speech recognition service in system settings'**
  String get checkSystemSettings;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @selectCategory.
  ///
  /// In en, this message translates to:
  /// **'Select Category'**
  String get selectCategory;

  /// No description provided for @confirmAdd.
  ///
  /// In en, this message translates to:
  /// **'Confirm Add'**
  String get confirmAdd;

  /// No description provided for @addSuccess.
  ///
  /// In en, this message translates to:
  /// **'Add successful'**
  String get addSuccess;

  /// No description provided for @addFailed.
  ///
  /// In en, this message translates to:
  /// **'Add failed'**
  String get addFailed;

  /// No description provided for @needMicrophonePermission.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required to use voice transaction'**
  String get needMicrophonePermission;

  /// No description provided for @browserDoesNotSupportSpeechRecognition.
  ///
  /// In en, this message translates to:
  /// **'Browser does not support speech recognition or microphone permission not granted'**
  String get browserDoesNotSupportSpeechRecognition;

  /// No description provided for @speechRecognitionServiceInitializationFailed.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition service initialization failed\nError: {error}\nPlease check system settings or restart the app'**
  String speechRecognitionServiceInitializationFailed(Object error);

  /// No description provided for @speechRecognitionServiceInUse.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition service is in use, please try again later'**
  String get speechRecognitionServiceInUse;

  /// No description provided for @speechRecognitionFailed.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition failed'**
  String get speechRecognitionFailed;

  /// No description provided for @noVoiceContentRecognized.
  ///
  /// In en, this message translates to:
  /// **'No voice content recognized, please try again'**
  String get noVoiceContentRecognized;

  /// No description provided for @transactionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Transaction successful'**
  String get transactionSuccess;

  /// No description provided for @transactionFailed.
  ///
  /// In en, this message translates to:
  /// **'Transaction failed, please try again'**
  String get transactionFailed;

  /// No description provided for @pressAndHoldToSpeakSlideToCancel.
  ///
  /// In en, this message translates to:
  /// **'Press and hold the button to speak, slide to cancel button to stop recording, slide to edit text button to edit'**
  String get pressAndHoldToSpeakSlideToCancel;

  /// No description provided for @diagnosticInformation.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic Information'**
  String get diagnosticInformation;

  /// No description provided for @textCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Text cannot be empty, please enter content'**
  String get textCannotBeEmpty;

  /// No description provided for @xiaomiHuaweiCheckGoogleApp.
  ///
  /// In en, this message translates to:
  /// **'   • Xiaomi/Huawei, etc.: Check if Google app is installed'**
  String get xiaomiHuaweiCheckGoogleApp;

  /// No description provided for @orInstallGoogleVoiceService.
  ///
  /// In en, this message translates to:
  /// **'   • Or install Google Voice Service'**
  String get orInstallGoogleVoiceService;

  /// No description provided for @loadCategoryFailed.
  ///
  /// In en, this message translates to:
  /// **'Load category failed: {error}'**
  String loadCategoryFailed(Object error);

  /// No description provided for @phoneOrUsername.
  ///
  /// In en, this message translates to:
  /// **'Phone/Username'**
  String get phoneOrUsername;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @pleaseEnterPhoneOrUsername.
  ///
  /// In en, this message translates to:
  /// **'Please enter phone or username'**
  String get pleaseEnterPhoneOrUsername;

  /// No description provided for @pleaseEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter password'**
  String get pleaseEnterPassword;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get loginFailed;

  /// No description provided for @forgotPasswordQuestion.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPasswordQuestion;

  /// No description provided for @noAccountRegister.
  ///
  /// In en, this message translates to:
  /// **'No account? Register'**
  String get noAccountRegister;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @verificationCode.
  ///
  /// In en, this message translates to:
  /// **'Verification Code'**
  String get verificationCode;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @pleaseEnterPhone.
  ///
  /// In en, this message translates to:
  /// **'Please enter phone'**
  String get pleaseEnterPhone;

  /// No description provided for @pleaseEnterCorrectPhone.
  ///
  /// In en, this message translates to:
  /// **'Please enter correct phone'**
  String get pleaseEnterCorrectPhone;

  /// No description provided for @pleaseEnterVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Please enter verification code'**
  String get pleaseEnterVerificationCode;

  /// No description provided for @pleaseEnterNickname.
  ///
  /// In en, this message translates to:
  /// **'Please enter nickname'**
  String get pleaseEnterNickname;

  /// No description provided for @passwordAtLeast6Chars.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordAtLeast6Chars;

  /// No description provided for @registerFailed.
  ///
  /// In en, this message translates to:
  /// **'Register failed'**
  String get registerFailed;

  /// No description provided for @haveAccountLogin.
  ///
  /// In en, this message translates to:
  /// **'Have account? Login'**
  String get haveAccountLogin;

  /// No description provided for @getVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Get Code'**
  String get getVerificationCode;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @pleaseEnterNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter new password'**
  String get pleaseEnterNewPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @verificationCodeSentSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Verification code sent successfully'**
  String get verificationCodeSentSuccessfully;

  /// No description provided for @passwordResetSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Password reset successfully'**
  String get passwordResetSuccessfully;

  /// No description provided for @resetFailed.
  ///
  /// In en, this message translates to:
  /// **'Reset failed'**
  String get resetFailed;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to Login'**
  String get backToLogin;

  /// No description provided for @sendVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Send Code'**
  String get sendVerificationCode;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPassword;

  /// No description provided for @pleaseEnterCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter current password'**
  String get pleaseEnterCurrentPassword;

  /// No description provided for @pleaseConfirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Please confirm new password'**
  String get pleaseConfirmNewPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @newPasswordCannotBeSame.
  ///
  /// In en, this message translates to:
  /// **'New password cannot be same as current password'**
  String get newPasswordCannotBeSame;

  /// No description provided for @confirmChange.
  ///
  /// In en, this message translates to:
  /// **'Confirm Change'**
  String get confirmChange;

  /// No description provided for @changeSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Changed successfully'**
  String get changeSuccessfully;

  /// No description provided for @changeFailed.
  ///
  /// In en, this message translates to:
  /// **'Change failed'**
  String get changeFailed;

  /// No description provided for @selectImage.
  ///
  /// In en, this message translates to:
  /// **'Select Image'**
  String get selectImage;

  /// No description provided for @avatarPreview.
  ///
  /// In en, this message translates to:
  /// **'Avatar Preview'**
  String get avatarPreview;

  /// No description provided for @max20Chars.
  ///
  /// In en, this message translates to:
  /// **'Max 20 characters'**
  String get max20Chars;

  /// No description provided for @enterEmailOptional.
  ///
  /// In en, this message translates to:
  /// **'Enter email address (optional)'**
  String get enterEmailOptional;

  /// No description provided for @pleaseEnterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter valid email address'**
  String get pleaseEnterValidEmail;

  /// No description provided for @emailOptionalInfo.
  ///
  /// In en, this message translates to:
  /// **'Email address is used for receiving notifications and important information (optional)'**
  String get emailOptionalInfo;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @tip.
  ///
  /// In en, this message translates to:
  /// **'Tip'**
  String get tip;

  /// No description provided for @profileUpdateInfo.
  ///
  /// In en, this message translates to:
  /// **'After updating your profile, all family members can see your updates. For best display effect, use clear square images for your avatar.'**
  String get profileUpdateInfo;

  /// No description provided for @imageSizeCannotExceed5MB.
  ///
  /// In en, this message translates to:
  /// **'Image size cannot exceed 5MB'**
  String get imageSizeCannotExceed5MB;

  /// No description provided for @processingImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Processing image file failed: {error}'**
  String processingImageFailed(Object error);

  /// No description provided for @selectImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to select image'**
  String get selectImageFailed;

  /// No description provided for @needGalleryPermission.
  ///
  /// In en, this message translates to:
  /// **'Gallery access permission is required, please enable it in settings'**
  String get needGalleryPermission;

  /// No description provided for @saveSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Saved successfully'**
  String get saveSuccessfully;

  /// No description provided for @approved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approved;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed'**
  String get operationFailed;

  /// No description provided for @noPendingApplications.
  ///
  /// In en, this message translates to:
  /// **'No pending applications'**
  String get noPendingApplications;

  /// No description provided for @exitFamilyWarning.
  ///
  /// In en, this message translates to:
  /// **'Exit Family Warning'**
  String get exitFamilyWarning;

  /// No description provided for @exitFamilySuccess.
  ///
  /// In en, this message translates to:
  /// **'Exit family successfully'**
  String get exitFamilySuccess;

  /// No description provided for @exitFamilyConsequences.
  ///
  /// In en, this message translates to:
  /// **'Exit consequences'**
  String get exitFamilyConsequences;

  /// No description provided for @cannotViewFamilyData.
  ///
  /// In en, this message translates to:
  /// **'Cannot view family data'**
  String get cannotViewFamilyData;

  /// No description provided for @cannotViewMemberInfo.
  ///
  /// In en, this message translates to:
  /// **'Cannot view member information'**
  String get cannotViewMemberInfo;

  /// No description provided for @cannotAddTransactions.
  ///
  /// In en, this message translates to:
  /// **'Cannot add transactions'**
  String get cannotAddTransactions;

  /// No description provided for @needReapplyToJoin.
  ///
  /// In en, this message translates to:
  /// **'Need to reapply to join'**
  String get needReapplyToJoin;

  /// No description provided for @scan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scan;

  /// No description provided for @scanQrCodeToJoin.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code to join'**
  String get scanQrCodeToJoin;

  /// No description provided for @family.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get family;

  /// No description provided for @clickScanButton.
  ///
  /// In en, this message translates to:
  /// **'Click scan button'**
  String get clickScanButton;

  /// No description provided for @scanFamilyQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan family QR code'**
  String get scanFamilyQrCode;

  /// No description provided for @enterRemarkAndSubmit.
  ///
  /// In en, this message translates to:
  /// **'Enter remark and submit'**
  String get enterRemarkAndSubmit;

  /// No description provided for @waitAdminApproval.
  ///
  /// In en, this message translates to:
  /// **'Wait for admin approval'**
  String get waitAdminApproval;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @platform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get platform;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @totalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total amount'**
  String get totalAmount;

  /// No description provided for @row.
  ///
  /// In en, this message translates to:
  /// **'Row'**
  String get row;

  /// No description provided for @small.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get small;

  /// No description provided for @standard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get standard;

  /// No description provided for @large.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get large;

  /// No description provided for @fontSizeTiny.
  ///
  /// In en, this message translates to:
  /// **'Very Small'**
  String get fontSizeTiny;

  /// No description provided for @fontSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get fontSizeSmall;

  /// No description provided for @fontSizeStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get fontSizeStandard;

  /// No description provided for @fontSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get fontSizeLarge;

  /// No description provided for @fontSizeExtraLarge.
  ///
  /// In en, this message translates to:
  /// **'Extra Large'**
  String get fontSizeExtraLarge;

  /// No description provided for @fontSizeHuge.
  ///
  /// In en, this message translates to:
  /// **'Huge'**
  String get fontSizeHuge;

  /// No description provided for @budget.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get budget;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newLabel;

  /// No description provided for @cannotGetFileData.
  ///
  /// In en, this message translates to:
  /// **'Cannot get file data, please retry'**
  String get cannotGetFileData;

  /// No description provided for @fileSelectionFailed.
  ///
  /// In en, this message translates to:
  /// **'File selection failed'**
  String get fileSelectionFailed;

  /// No description provided for @fileSelectionFailedPleaseRetry.
  ///
  /// In en, this message translates to:
  /// **'File selection failed, please retry'**
  String get fileSelectionFailedPleaseRetry;

  /// No description provided for @fileSelectionFailedPleaseReselect.
  ///
  /// In en, this message translates to:
  /// **'File selection failed, please try reselecting file'**
  String get fileSelectionFailedPleaseReselect;

  /// No description provided for @fileSelectionNotSupported.
  ///
  /// In en, this message translates to:
  /// **'File selection feature is not supported, please use other methods to upload'**
  String get fileSelectionNotSupported;

  /// No description provided for @needFileAccessPermission.
  ///
  /// In en, this message translates to:
  /// **'File access permission is required, please enable it in settings'**
  String get needFileAccessPermission;

  /// No description provided for @filePathUnavailable.
  ///
  /// In en, this message translates to:
  /// **'File path unavailable'**
  String get filePathUnavailable;

  /// No description provided for @fileDataUnavailable.
  ///
  /// In en, this message translates to:
  /// **'File data unavailable'**
  String get fileDataUnavailable;

  /// No description provided for @billUploadIdCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Bill upload record ID cannot be empty'**
  String get billUploadIdCannotBeEmpty;

  /// No description provided for @processingTimeout.
  ///
  /// In en, this message translates to:
  /// **'Processing timeout'**
  String get processingTimeout;

  /// No description provided for @processingTimeoutPleaseRetry.
  ///
  /// In en, this message translates to:
  /// **'Processing timeout, please try again later'**
  String get processingTimeoutPleaseRetry;

  /// No description provided for @processingFailed.
  ///
  /// In en, this message translates to:
  /// **'Processing failed'**
  String get processingFailed;

  /// No description provided for @queryTaskStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to query task status'**
  String get queryTaskStatusFailed;

  /// No description provided for @getPreviewDataFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to get preview data'**
  String get getPreviewDataFailed;

  /// No description provided for @importCompleted.
  ///
  /// In en, this message translates to:
  /// **'Import completed!'**
  String get importCompleted;

  /// No description provided for @getImportResultFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to get import result'**
  String get getImportResultFailed;

  /// No description provided for @initializingTask.
  ///
  /// In en, this message translates to:
  /// **'Initializing task...'**
  String get initializingTask;

  /// No description provided for @parsingBillFile.
  ///
  /// In en, this message translates to:
  /// **'Parsing bill file...'**
  String get parsingBillFile;

  /// No description provided for @previewData.
  ///
  /// In en, this message translates to:
  /// **'Preview data'**
  String get previewData;

  /// No description provided for @confirmImport.
  ///
  /// In en, this message translates to:
  /// **'Confirm Import'**
  String get confirmImport;

  /// No description provided for @importingTransactions.
  ///
  /// In en, this message translates to:
  /// **'Importing transactions...'**
  String get importingTransactions;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailed;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// No description provided for @importResult.
  ///
  /// In en, this message translates to:
  /// **'Import Result'**
  String get importResult;

  /// No description provided for @totalRecords.
  ///
  /// In en, this message translates to:
  /// **'Total records'**
  String get totalRecords;

  /// No description provided for @successfullyImported.
  ///
  /// In en, this message translates to:
  /// **'Successfully imported'**
  String get successfullyImported;

  /// No description provided for @skippedDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Skipped (duplicate)'**
  String get skippedDuplicate;

  /// No description provided for @importFailedReason.
  ///
  /// In en, this message translates to:
  /// **'Import failure reasons'**
  String get importFailedReason;

  /// No description provided for @rawData.
  ///
  /// In en, this message translates to:
  /// **'Raw data'**
  String get rawData;

  /// No description provided for @showingFirst10.
  ///
  /// In en, this message translates to:
  /// **'Showing first 10, total {count} failure records'**
  String showingFirst10(Object count);

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'in progress'**
  String get inProgress;

  /// No description provided for @processed.
  ///
  /// In en, this message translates to:
  /// **'Processed'**
  String get processed;

  /// No description provided for @fail.
  ///
  /// In en, this message translates to:
  /// **'Fail'**
  String get fail;

  /// No description provided for @supportedFormats.
  ///
  /// In en, this message translates to:
  /// **'Supported formats:'**
  String get supportedFormats;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'items'**
  String get items;

  /// No description provided for @viewTransactions.
  ///
  /// In en, this message translates to:
  /// **'View transactions'**
  String get viewTransactions;

  /// No description provided for @continueImport.
  ///
  /// In en, this message translates to:
  /// **'Continue import'**
  String get continueImport;

  /// No description provided for @addCategory.
  ///
  /// In en, this message translates to:
  /// **'Add Category'**
  String get addCategory;

  /// No description provided for @confirmDeleteCategoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete category \"{name}\"? This operation cannot be undone.'**
  String confirmDeleteCategoryMessage(Object name);

  /// No description provided for @addCategoryDialog.
  ///
  /// In en, this message translates to:
  /// **'Add Category'**
  String get addCategoryDialog;

  /// No description provided for @categoryName.
  ///
  /// In en, this message translates to:
  /// **'Category Name'**
  String get categoryName;

  /// No description provided for @pleaseEnterCategoryName.
  ///
  /// In en, this message translates to:
  /// **'Please enter category name'**
  String get pleaseEnterCategoryName;

  /// No description provided for @selectIcon.
  ///
  /// In en, this message translates to:
  /// **'Select Icon'**
  String get selectIcon;

  /// No description provided for @editCategory.
  ///
  /// In en, this message translates to:
  /// **'Edit Category'**
  String get editCategory;

  /// No description provided for @updateSuccess.
  ///
  /// In en, this message translates to:
  /// **'Update successful'**
  String get updateSuccess;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed'**
  String get updateFailed;

  /// No description provided for @noCategories.
  ///
  /// In en, this message translates to:
  /// **'No categories'**
  String get noCategories;

  /// No description provided for @tooltipAddCategory.
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get tooltipAddCategory;

  /// No description provided for @tooltipEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get tooltipEdit;

  /// No description provided for @tooltipDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get tooltipDelete;

  /// No description provided for @applyToJoinFamily.
  ///
  /// In en, this message translates to:
  /// **'Apply to Join Family'**
  String get applyToJoinFamily;

  /// No description provided for @invalidFamilyInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid family invitation code'**
  String get invalidFamilyInviteCode;

  /// No description provided for @pleaseEnterApplicationNote.
  ///
  /// In en, this message translates to:
  /// **'Please enter application note'**
  String get pleaseEnterApplicationNote;

  /// No description provided for @applicationNote.
  ///
  /// In en, this message translates to:
  /// **'Application Note'**
  String get applicationNote;

  /// No description provided for @pleaseEnterReasonForJoining.
  ///
  /// In en, this message translates to:
  /// **'Please enter reason for joining family (required)'**
  String get pleaseEnterReasonForJoining;

  /// No description provided for @submitApplication.
  ///
  /// In en, this message translates to:
  /// **'Submit Application'**
  String get submitApplication;

  /// No description provided for @applicationSubmittedWaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Application submitted, waiting for approval'**
  String get applicationSubmittedWaitingApproval;

  /// No description provided for @familyIdCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Family ID cannot be empty'**
  String get familyIdCannotBeEmpty;

  /// No description provided for @submitFailed.
  ///
  /// In en, this message translates to:
  /// **'Submission failed'**
  String get submitFailed;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCode;

  /// No description provided for @alignQrCodeInFrame.
  ///
  /// In en, this message translates to:
  /// **'Align QR code within the frame for automatic scanning'**
  String get alignQrCodeInFrame;

  /// No description provided for @ensureQrCodeClear.
  ///
  /// In en, this message translates to:
  /// **'Please ensure the QR code is clear and complete'**
  String get ensureQrCodeClear;

  /// No description provided for @requestTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request timeout, please check network connection'**
  String get requestTimeout;

  /// No description provided for @networkConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Network connection failed, please check network settings'**
  String get networkConnectionFailed;

  /// No description provided for @requestFailed.
  ///
  /// In en, this message translates to:
  /// **'Request failed'**
  String get requestFailed;

  /// No description provided for @unauthorized.
  ///
  /// In en, this message translates to:
  /// **'Unauthorized, please login again'**
  String get unauthorized;

  /// No description provided for @permissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get permissionDenied;

  /// No description provided for @resourceNotFound.
  ///
  /// In en, this message translates to:
  /// **'Requested resource not found'**
  String get resourceNotFound;

  /// No description provided for @serverError.
  ///
  /// In en, this message translates to:
  /// **'Server error, please try again later'**
  String get serverError;

  /// No description provided for @requestCanceled.
  ///
  /// In en, this message translates to:
  /// **'Request canceled'**
  String get requestCanceled;

  /// No description provided for @certificateError.
  ///
  /// In en, this message translates to:
  /// **'Certificate verification failed'**
  String get certificateError;

  /// No description provided for @unsupportedFileType.
  ///
  /// In en, this message translates to:
  /// **'Unsupported file type'**
  String get unsupportedFileType;

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get uploadFailed;

  /// No description provided for @uploadFailedFormatError.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: Invalid return format'**
  String get uploadFailedFormatError;

  /// No description provided for @themePreviewDescription.
  ///
  /// In en, this message translates to:
  /// **'After selecting a theme, you can preview the effect in real-time and save it after confirmation. Theme settings are saved locally and will be retained even after logging out.'**
  String get themePreviewDescription;

  /// No description provided for @previewingTheme.
  ///
  /// In en, this message translates to:
  /// **'Previewing: {themeName}'**
  String previewingTheme(Object themeName);

  /// No description provided for @previewingThemeDescription.
  ///
  /// In en, this message translates to:
  /// **'Click the button below to confirm saving, or return to cancel'**
  String get previewingThemeDescription;

  /// No description provided for @confirmAndSave.
  ///
  /// In en, this message translates to:
  /// **'Confirm and Save'**
  String get confirmAndSave;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
