// lib/l10n/app_localizations.dart
import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  bool get isRtl => locale.languageCode == 'fa';

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'app_title': 'FamilyTrack',
      'missing_config_title': 'Supabase Configuration Missing',
      'missing_config_body':
          'SUPABASE_URL or SUPABASE_ANON_KEY was not provided at compile time (or contains placeholder values). '
          'Create config/env.json and build with --dart-define-from-file=config/env.json.',
      'consent_title': 'Background Location Sharing',
      'consent_body':
          'FamilyTrack shares your phone\'s current location in the background with members of your group. '
          'Locations are never tracked as a history trail—only your single latest position is stored and '
          'only shown when a group member explicitly requests an update.',
      'consent_permissions_note':
          'In the next step, we will ask for "When In Use" and then "Always" location permission so your '
          'family can see a recent timestamp even when the app is closed.',
      'consent_oem_note':
          'On Xiaomi (MIUI), Samsung, or Huawei phones, please set Battery Saver to "No restrictions" '
          'so background heartbeats are not paused by the system.',
      'consent_accept': 'I Understand & Accept',
      'login_title': 'Join or Log In to a Group',
      'login_subtitle':
          'Enter your 12-character group code (XXXX-XXXX-XXXX) and your role label.',
      'code_label': 'Group Code',
      'code_hint': 'XXXX-XXXX-XXXX',
      'role_label': 'Your Role in Group',
      'role_hint': 'e.g. Mother, Brother, Father',
      'join_button': 'Join or Log In to Group',
      'login_existing_button': 'Check My Existing Role',
      'login_existing_hint':
          'Already joined this group on this phone before? Tap "Check My Existing Role" to restore your session.',
      'resume_saved_group': 'Continue as {role}',
      'joining': 'Connecting...',
      'refresh': 'Refresh',
      'people': 'People',
      'map_style': 'Map Style',
      'exit_group': 'Exit Group',
      'style_positron': 'Positron (Light)',
      'style_bright': 'Bright',
      'style_dark': 'Dark',
      'people_sheet_title': 'Choose Members to Follow',
      'people_sheet_subtitle':
          'Only selected members are requested from the server and shown on the map.',
      'updated_just_now': 'updated just now',
      'updated_min_ago': 'updated {min} min ago',
      'open_in_maps': 'Open in maps',
      'open_in_system_geo': 'System maps app',
      'map_unavailable':
          'Map unavailable. Member chips and external map links below remain active.',
      'retry': 'Retry',
      'location_off_notice':
          'Location permission or GPS is off. Background sharing is paused until re-enabled.',
      'no_followed_members':
          'Select at least one member in People to view locations.',
      'wait_cooldown': 'Please wait {time}',
      // Exact localized error codes from join_group & fetch_locations
      'err_invalid_name':
          'Please enter a valid role label (between 1 and 32 characters).',
      'err_too_many_attempts':
          'Too many failed attempts. Please wait 2 minutes and try again.',
      'err_too_many_attempts_cooldown':
          'Too many failed attempts. Please wait {time} before trying again.',
      'err_invalid_code':
          'Invalid group code. Please check the 12-character code and try again.',
      'err_group_expired':
          'This group has expired. Please enter a new active group code.',
      'err_group_full':
          'This group has reached its maximum number of member devices.',
      'err_name_taken':
          'This role label is already taken in this group. Please choose another name (e.g. Dad 2, Mom Phone).',
      'err_unauthorized':
          'Session authorization failed. Please try again.',
      'err_bad_request':
          'Invalid request. Please check the group code and role label, then try again.',
      'err_server_error':
          'Server error occurred. Please try again in a moment.',
      'err_not_a_member':
          'You are no longer a member of this group.',
      'err_not_authenticated':
          'Authentication session expired. Returning to login screen.',
      'err_invalid_target':
          'One or more selected members are no longer in this group.',
    },
    'fa': {
      'app_title': 'همراه خانواده',
      'missing_config_title': 'تنظیمات سوپابیس یافت نشد',
      'missing_config_body':
          'مقادیر SUPABASE_URL یا SUPABASE_ANON_KEY در زمان ساخت برنامه وارد نشده‌اند. '
          'فایل config/env.json را ایجاد کرده و برنامه را با --dart-define-from-file=config/env.json بسازید.',
      'consent_title': 'اشتراک‌گذاری موقعیت مکانی در پس‌زمینه',
      'consent_body':
          'این برنامه موقعیت فعلی تلفن شما را در پس‌زمینه با اعضای گروهتان به اشتراک می‌گذارد. '
          'هیچ سابقه و تاریخچه‌ای از مسیر شما ذخیره نمی‌شود؛ فقط آخرین نقطه مکانی شما نگهداری شده '
          'و تنها زمانی که یکی از اعضای گروه درخواست بروزرسانی کند نمایش داده می‌شود.',
      'consent_permissions_note':
          'در مرحله بعد، ابتدا دسترسی «هنگام استفاده» و سپس دسترسی «همیشه» (Always) درخواست می‌شود '
          'تا حتی هنگام بسته بودن برنامه نیز موقعیت شما بروز بماند.',
      'consent_oem_note':
          'در گوشی‌های شیائومی، سامسونگ و هوآوی، لطفاً بهینه‌سازی باتری را برای این برنامه روی '
          '«بدون محدودیت» قرار دهید تا ارسال موقعیت در پس‌زمینه متوقف نشود.',
      'consent_accept': 'متوجه شدم و می‌پذیرم',
      'login_title': 'ورود یا عضویت در گروه',
      'login_subtitle':
          'کد ۱۲ کاراکتری گروه (XXXX-XXXX-XXXX) و عنوان خود را وارد کنید.',
      'code_label': 'کد گروه',
      'code_hint': 'XXXX-XXXX-XXXX',
      'role_label': 'عنوان شما در گروه',
      'role_hint': 'مثال: مادر، برادر، پدر',
      'join_button': 'عضویت یا ورود به گروه',
      'login_existing_button': 'بررسی عنوان قبلی من',
      'login_existing_hint':
          'اگر قبلاً در این گوشی به این گروه متصل بودید، دکمه «بررسی عنوان قبلی من» را بزنید.',
      'resume_saved_group': 'ادامه با عنوان {role}',
      'joining': 'در حال اتصال...',
      'refresh': 'بروزرسانی',
      'people': 'اعضا',
      'map_style': 'نمای نقشه',
      'exit_group': 'خروج از گروه',
      'style_positron': 'پوزیترون (روشن)',
      'style_bright': 'شفاف (Bright)',
      'style_dark': 'تیره (Dark)',
      'people_sheet_title': 'انتخاب اعضا برای نمایش',
      'people_sheet_subtitle':
          'فقط موقعیت اعضای انتخاب‌شده از سرور دریافت و روی نقشه نمایش داده می‌شود.',
      'updated_just_now': 'بروزرسانی: همین الان',
      'updated_min_ago': 'بروزرسانی {min} دقیقه پیش',
      'open_in_maps': 'باز کردن در نقشه',
      'open_in_system_geo': 'برنامه نقشه گوشی',
      'map_unavailable':
          'نقشه در دسترس نیست. لیست اعضا و لینک باز کردن در نقشه همچنان فعال هستند.',
      'retry': 'تلاش مجدد',
      'location_off_notice':
          'دسترسی مکان یا GPS خاموش است. ارسال موقعیت تا زمان فعال‌سازی متوقف است.',
      'no_followed_members':
          'از بخش «اعضا» حداقل یک نفر را برای مشاهده انتخاب کنید.',
      'wait_cooldown': 'لطفاً صبر کنید ({time})',
      // Exact localized error codes from join_group & fetch_locations
      'err_invalid_name':
          'لطفاً یک عنوان معتبر وارد کنید (بین ۱ تا ۳۲ کاراکتر).',
      'err_too_many_attempts':
          'تعداد تلاش‌های ناموفق بیش از حد مجاز است. لطفاً ۲ دقیقه صبر کرده و دوباره تلاش کنید.',
      'err_too_many_attempts_cooldown':
          'تعداد تلاش‌های ناموفق بیش از حد مجاز است. لطفاً {time} صبر کرده و سپس دوباره تلاش کنید.',
      'err_invalid_code':
          'کد گروه نامعتبر است. لطفاً کد ۱۲ کاراکتری را بررسی کرده و دوباره تلاش کنید.',
      'err_group_expired':
          'اعتبار این گروه به پایان رسیده است. لطفاً یک کد گروه معتبر وارد کنید.',
      'err_group_full':
          'ظرفیت تعداد اعضای این گروه تکمیل شده است.',
      'err_name_taken':
          'این عنوان قبلاً در این گروه انتخاب شده است. لطفاً عنوان دیگری وارد کنید (مثال: پدر ۲).',
      'err_unauthorized':
          'خطا در احراز هویت نشست. لطفاً دوباره تلاش کنید.',
      'err_bad_request':
          'درخواست نامعتبر است. کد گروه و عنوان خود را بررسی کرده و مجدداً تلاش کنید.',
      'err_server_error':
          'خطای سرور رخ داد. لطفاً لحظاتی دیگر دوباره تلاش کنید.',
      'err_not_a_member':
          'شما دیگر عضو این گروه نیستید.',
      'err_not_authenticated':
          'نشست کاربری منقضی شده است. لطفاً دوباره وارد شوید.',
      'err_invalid_target':
          'یک یا چند نفر از اعضای انتخاب‌شده دیگر در این گروه حضور ندارند.',
    },
  };

  String tr(String key, {Map<String, String>? params}) {
    final lang = _localizedValues.containsKey(locale.languageCode)
        ? locale.languageCode
        : 'en';
    String text = _localizedValues[lang]?[key] ??
        _localizedValues['en']?[key] ??
        key;

    if (params != null) {
      params.forEach((paramKey, value) {
        text = text.replaceAll('{$paramKey}', value);
      });
    }
    return text;
  }

  String translateErrorCode(String? code, {String? cooldownTime}) {
    if (code == null) return '';
    if (code == 'too_many_attempts' && cooldownTime != null) {
      return tr('err_too_many_attempts_cooldown', params: {'time': cooldownTime});
    }
    final key = 'err_$code';
    final translated = tr(key);
    return translated != key ? translated : tr('err_server_error');
  }

  String formatUpdatedAgo(DateTime? time) {
    if (time == null) return tr('updated_just_now');
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return tr('updated_just_now');
    return tr('updated_min_ago', params: {'min': diff.inMinutes.toString()});
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'fa'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
