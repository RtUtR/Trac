import React, { useState, useEffect, useRef, useMemo } from 'react';
import {
  RefreshCw,
  Users,
  Layers,
  LogOut,
  ExternalLink,
  ShieldCheck,
  AlertCircle,
  Check,
  Plus,
  FastForward,
  WifiOff,
  Wifi,
} from 'lucide-react';

export type MapStyleOption = 'positron' | 'bright' | 'dark';
export type AppLang = 'en' | 'fa';

export type BackendErrorCode =
  | 'invalid_name'
  | 'too_many_attempts'
  | 'invalid_code'
  | 'group_expired'
  | 'group_full'
  | 'name_taken'
  | 'unauthorized'
  | 'bad_request'
  | 'server_error'
  | 'not_a_member'
  | 'not_authenticated'
  | 'invalid_target';

interface SimGroup {
  id: string;
  plainCodeHint: string;
  codeHash: string;
  maxDevices: 4 | 7;
  expiresAt: number;
}

interface SimMember {
  groupId: string;
  userId: string;
  displayName: string;
  color: string;
}

interface SimLocation {
  userId: string;
  lat: number;
  lng: number;
  accuracy: number;
  updatedAt: number; // Set by the server on upsert, never sent by client
}

const FIXED_PALETTE = [
  '#2563EB', // Cobalt Blue
  '#DC2626', // Crimson Red
  '#059669', // Emerald Green
  '#D97706', // Amber Ochre
  '#7C3AED', // Deep Violet
  '#DB2777', // Magenta Rose
  '#0891B2', // Cyan Teal
  '#4F46E5', // Indigo
];

// Exact 12-character alphabet specified: "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const ALLOWED_CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const WAYMORPHIC_STYLES: Record<MapStyleOption, string> = {
  positron: 'https://tiles.waymorphic.com/styles/positron',
  bright: 'https://tiles.waymorphic.com/styles/bright',
  dark: 'https://tiles.waymorphic.com/styles/dark',
};

const TRANSLATIONS: Record<AppLang, Record<string, string>> = {
  en: {
    app_title: 'FamilyTrack',
    missing_config_title: 'Supabase Configuration Missing',
    missing_config_body:
      'SUPABASE_URL or SUPABASE_ANON_KEY was not provided at compile time. Create config/env.json and run the app with --dart-define-from-file=config/env.json.',
    consent_title: 'Background Location Sharing',
    consent_body:
      "FamilyTrack shares your phone's current location in the background with members of your group. Locations are never tracked as a history trail—only your single latest position is stored and only shown when a group member explicitly requests an update.",
    consent_permissions_note:
      'Next, we request "When In Use" and then "Always" location permission so your family can see a recent timestamp even when the app is closed.',
    consent_oem_note:
      'On Xiaomi (MIUI), Samsung, or Huawei phones, set Battery Saver to "No restrictions" so background heartbeats are not paused.',
    consent_accept: 'I Understand & Accept',
    login_title: 'Join a Group',
    login_subtitle:
      'Enter your 12-character group code (XXXX-XXXX-XXXX) and your role label.',
    code_label: 'Group Code',
    code_hint: 'XXXX-XXXX-XXXX',
    role_label: 'Your Role in Group',
    role_hint: 'e.g. Mother, Brother, Father',
    join_button: 'Join',
    joining: 'Joining...',
    refresh: 'Refresh',
    people: 'People',
    map_style: 'Map Style',
    exit_group: 'Exit',
    style_positron: 'Positron (Light)',
    style_bright: 'Bright',
    style_dark: 'Dark',
    people_sheet_title: 'Choose Members to Follow',
    people_sheet_subtitle:
      'Only selected members are requested from the server and shown on the map.',
    updated_just_now: 'updated just now',
    updated_min_ago: 'updated {min} min ago',
    open_in_maps: 'Open in maps',
    open_in_system_geo: 'System geo:',
    map_unavailable:
      'Map unavailable. Member chips and "Open in maps" links below remain active.',
    retry: 'Retry',
    location_off_notice:
      'Location permission or GPS is off. Background sharing is paused until re-enabled.',
    no_followed_members:
      'Select at least one member in People to view locations.',
    // Exact localized error codes
    err_invalid_name:
      'Please enter a valid role label (between 1 and 32 characters).',
    err_too_many_attempts:
      'Too many failed attempts. Please wait a few minutes and try again.',
    err_invalid_code:
      'Invalid group code. Please check the 12-character code and try again.',
    err_group_expired:
      'This group has expired. Please enter a new active group code.',
    err_group_full:
      'This group has reached its maximum number of member devices.',
    err_name_taken:
      'This role label is already taken in this group. Choose a different label.',
    err_unauthorized: 'Session authorization failed. Please try again.',
    err_bad_request:
      'Invalid request format. Please check your code and role label.',
    err_server_error: 'Server error occurred. Please try again in a moment.',
    err_not_a_member: 'You are no longer a member of this group.',
    err_not_authenticated:
      'Authentication session expired. Returning to login screen.',
    err_invalid_target:
      'One or more selected members are no longer in this group.',
  },
  fa: {
    app_title: 'همراه خانواده',
    missing_config_title: 'تنظیمات سوپابیس یافت نشد',
    missing_config_body:
      'مقادیر SUPABASE_URL یا SUPABASE_ANON_KEY در زمان ساخت برنامه وارد نشده‌اند. فایل config/env.json را ایجاد کرده و برنامه را با --dart-define-from-file=config/env.json اجرا کنید.',
    consent_title: 'اشتراک‌گذاری موقعیت مکانی در پس‌زمینه',
    consent_body:
      'این برنامه موقعیت فعلی تلفن شما را در پس‌زمینه با اعضای گروهتان به اشتراک می‌گذارد. هیچ سابقه و تاریخچه‌ای از مسیر شما ذخیره نمی‌شود؛ فقط آخرین نقطه مکانی شما نگهداری شده و تنها زمانی که یکی از اعضای گروه درخواست بروزرسانی کند نمایش داده می‌شود.',
    consent_permissions_note:
      'در مرحله بعد، ابتدا دسترسی «هنگام استفاده» و سپس دسترسی «همیشه» (Always) درخواست می‌شود تا حتی هنگام بسته بودن برنامه نیز موقعیت شما بروز بماند.',
    consent_oem_note:
      'در گوشی‌های شیائومی، سامسونگ و هوآوی، لطفاً بهینه‌سازی باتری را روی «بدون محدودیت» قرار دهید.',
    consent_accept: 'متوجه شدم و می‌پذیرم',
    login_title: 'ورود به گروه',
    login_subtitle:
      'کد ۱۲ کاراکتری گروه (XXXX-XXXX-XXXX) و عنوان خود را وارد کنید.',
    code_label: 'کد گروه',
    code_hint: 'XXXX-XXXX-XXXX',
    role_label: 'عنوان شما در گروه',
    role_hint: 'مثال: مادر، برادر، پدر',
    join_button: 'ورود به گروه',
    joining: 'در حال بررسی...',
    refresh: 'بروزرسانی',
    people: 'اعضا',
    map_style: 'نمای نقشه',
    exit_group: 'خروج',
    style_positron: 'پوزیترون (روشن)',
    style_bright: 'شفاف (Bright)',
    style_dark: 'تیره (Dark)',
    people_sheet_title: 'انتخاب اعضا برای نمایش',
    people_sheet_subtitle:
      'فقط موقعیت اعضای انتخاب‌شده از سرور دریافت و روی نقشه نمایش داده می‌شود.',
    updated_just_now: 'بروزرسانی: همین الان',
    updated_min_ago: 'بروزرسانی {min} دقیقه پیش',
    open_in_maps: 'باز کردن در نقشه',
    open_in_system_geo: 'برنامه نقشه',
    map_unavailable:
      'نقشه در دسترس نیست. لیست اعضا و لینک باز کردن در نقشه همچنان فعال هستند.',
    retry: 'تلاش مجدد',
    location_off_notice:
      'دسترسی مکان یا GPS خاموش است. ارسال موقعیت تا زمان فعال‌سازی متوقف است.',
    no_followed_members:
      'از بخش «اعضا» حداقل یک نفر را برای مشاهده انتخاب کنید.',
    // Exact localized error codes
    err_invalid_name:
      'لطفاً یک عنوان معتبر وارد کنید (بین ۱ تا ۳۲ کاراکتر).',
    err_too_many_attempts:
      'تعداد تلاش‌های ناموفق بیش از حد مجاز است. لطفاً چند دقیقه صبر کنید و دوباره تلاش کنید.',
    err_invalid_code:
      'کد گروه نامعتبر است. لطفاً کد ۱۲ کاراکتری را بررسی کرده و دوباره تلاش کنید.',
    err_group_expired:
      'اعتبار این گروه به پایان رسیده است. لطفاً یک کد گروه معتبر وارد کنید.',
    err_group_full: 'ظرفیت تعداد اعضای این گروه تکمیل شده است.',
    err_name_taken:
      'این عنوان قبلاً در این گروه انتخاب شده است. لطفاً عنوان دیگری انتخاب کنید.',
    err_unauthorized: 'خطا در احراز هویت نشست. لطفاً دوباره تلاش کنید.',
    err_bad_request:
      'فرمت درخواست نامعتبر است. کد و عنوان خود را بررسی کنید.',
    err_server_error: 'خطای سرور رخ داد. لطفاً لحظاتی دیگر دوباره تلاش کنید.',
    err_not_a_member: 'شما دیگر عضو این گروه نیستید.',
    err_not_authenticated:
      'نشست کاربری منقضی شده است. لطفاً دوباره وارد شوید.',
    err_invalid_target:
      'یک یا چند نفر از اعضای انتخاب‌شده دیگر در این گروه حضور ندارند.',
  },
};

/**
 * Converts Persian (۰-۹) and Arabic-Indic (٠-٩) digits to Latin digits (0-9),
 * uppercases text, and strips spaces and hyphens.
 */
export function normalizeGroupCode(raw: string): string {
  let out = '';
  for (const ch of raw) {
    const code = ch.codePointAt(0) ?? 0;
    if (code >= 0x06f0 && code <= 0x06f9) {
      out += String.fromCharCode(0x30 + (code - 0x06f0));
    } else if (code >= 0x0660 && code <= 0x0669) {
      out += String.fromCharCode(0x30 + (code - 0x0660));
    } else {
      out += ch;
    }
  }
  return out.toUpperCase().replace(/[\s-]/g, '');
}

/**
 * Formats input as XXXX-XXXX-XXXX while converting Persian/Arabic digits and uppercasing.
 */
export function formatGroupCodeDisplay(raw: string): string {
  const cleaned = normalizeGroupCode(raw).slice(0, 12);
  const parts: string[] = [];
  for (let i = 0; i < cleaned.length; i += 4) {
    parts.push(cleaned.slice(i, i + 4));
  }
  return parts.join('-');
}

function isValidGroupCodeAlphabet(normalized: string): boolean {
  if (normalized.length !== 12) return false;
  for (const ch of normalized) {
    if (!ALLOWED_CODE_ALPHABET.includes(ch)) return false;
  }
  return true;
}

function simpleSha256Preview(str: string): string {
  let h1 = 0xdeadbeef ^ str.length;
  let h2 = 0x41c6ce57 ^ str.length;
  for (let i = 0, ch; i < str.length; i++) {
    ch = str.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761);
    h2 = Math.imul(h2 ^ ch, 1597334677);
  }
  h1 =
    Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^
    Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 =
    Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^
    Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  const hex1 = (h1 >>> 0).toString(16).padStart(8, '0');
  const hex2 = (h2 >>> 0).toString(16).padStart(8, '0');
  return `${hex1}${hex2}e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934c`;
}

function haversineMeters(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

interface Props {
  isDark: boolean;
  lang: AppLang;
  onSelectDeliverable: (fileId: string) => void;
}

export const FamilyTrackSimulator: React.FC<Props> = ({
  isDark,
  lang,
  onSelectDeliverable,
}) => {
  const t = (key: string, min?: number) => {
    const raw = TRANSLATIONS[lang][key] ?? TRANSLATIONS.en[key] ?? key;
    return min !== undefined ? raw.replace('{min}', String(min)) : raw;
  };
  const translateError = (errorCode: string) => {
    const key = `err_${errorCode.toLowerCase()}`;
    return TRANSLATIONS[lang][key] ?? TRANSLATIONS.en[key] ?? errorCode;
  };
  const isRtl = lang === 'fa';

  const myUserId = 'anon-user-9f81-4c2a';

  const [groups, setGroups] = useState<SimGroup[]>(() => [
    {
      id: 'grp-tehran-family-01',
      plainCodeHint: '7K9M4P2X8W3Q',
      codeHash: simpleSha256Preview('7K9M4P2X8W3Q'),
      maxDevices: 4,
      expiresAt: Date.now() + 26 * 24 * 3600 * 1000,
    },
    {
      id: 'grp-extended-family-02',
      plainCodeHint: '9H3N6R8T2Y5V',
      codeHash: simpleSha256Preview('9H3N6R8T2Y5V'),
      maxDevices: 7,
      expiresAt: Date.now() + 14 * 24 * 3600 * 1000,
    },
  ]);

  const [members, setMembers] = useState<SimMember[]>(() => [
    {
      groupId: 'grp-tehran-family-01',
      userId: myUserId,
      displayName: 'Daughter',
      color: FIXED_PALETTE[0],
    },
    {
      groupId: 'grp-tehran-family-01',
      userId: 'user-mother-02',
      displayName: 'Mother',
      color: FIXED_PALETTE[1],
    },
    {
      groupId: 'grp-tehran-family-01',
      userId: 'user-father-03',
      displayName: 'Father',
      color: FIXED_PALETTE[2],
    },
    {
      groupId: 'grp-tehran-family-01',
      userId: 'user-brother-04',
      displayName: 'Brother',
      color: FIXED_PALETTE[3],
    },
  ]);

  const [locations, setLocations] = useState<Record<string, SimLocation>>(() => ({
    [myUserId]: {
      userId: myUserId,
      lat: 35.7219,
      lng: 51.3347,
      accuracy: 11.4,
      updatedAt: Date.now() - 2 * 60 * 1000,
    },
    'user-mother-02': {
      userId: 'user-mother-02',
      lat: 35.7575,
      lng: 51.4100,
      accuracy: 8.2,
      updatedAt: Date.now() - 4 * 60 * 1000,
    },
    'user-father-03': {
      userId: 'user-father-03',
      lat: 35.6997,
      lng: 51.3380,
      accuracy: 14.0,
      updatedAt: Date.now() - 9 * 60 * 1000,
    },
    'user-brother-04': {
      userId: 'user-brother-04',
      lat: 35.7448,
      lng: 51.3753,
      accuracy: 10.5,
      updatedAt: Date.now() - 14 * 60 * 1000,
    },
  }));

  // App UI states
  const [simulateMissingConfig, setSimulateMissingConfig] =
    useState<boolean>(false);
  const [consentAccepted, setConsentAccepted] = useState<boolean>(true);
  const [activeGroupId, setActiveGroupId] = useState<string | null>(
    'grp-tehran-family-01'
  );
  const [savedMyDisplayName, setSavedMyDisplayName] =
    useState<string>('Daughter');
  const [savedMyColor, setSavedMyColor] = useState<string>(FIXED_PALETTE[0]);
  const [locationPermissionOn, setLocationPermissionOn] =
    useState<boolean>(true);

  // Login screen state
  const [loginCodeDisplay, setLoginCodeDisplay] =
    useState<string>('9H3N-6R8T-2Y5V');
  const [loginRoleInput, setLoginRoleInput] = useState<string>('Sister');
  const [errorCode, setErrorCode] = useState<BackendErrorCode | null>(null);
  const [failedJoinCount, setFailedJoinCount] = useState<number>(0);

  // Last JSON RPC / Edge Function payload inspector
  const [lastApiCallLog, setLastApiCallLog] = useState<{
    endpoint: string;
    request: unknown;
    response: unknown;
  }>({
    endpoint: "supabase.rpc('fetch_locations')",
    request: {
      p_group_id: 'grp-tehran-family-01',
      p_target_user_ids: [
        myUserId,
        'user-mother-02',
        'user-father-03',
        'user-brother-04',
      ],
    },
    response: {
      ok: true,
      cooldown_seconds: 180,
      locations: [
        {
          user_id: 'user-mother-02',
          display_name: 'Mother',
          color: '#DC2626',
          lat: 35.7575,
          lng: 51.41,
          accuracy: 8.2,
          updated_at: new Date(Date.now() - 4 * 60 * 1000).toISOString(),
        },
      ],
    },
  });

  // Map & style states
  const [userPickedStyle, setUserPickedStyle] = useState<MapStyleOption | null>(
    () => {
      const saved = localStorage.getItem('ft_map_style');
      return saved === 'positron' || saved === 'bright' || saved === 'dark'
        ? saved
        : null;
    }
  );
  const effectiveMapStyle: MapStyleOption =
    userPickedStyle ?? (isDark ? 'dark' : 'positron');

  const [styleMenuOpen, setStyleMenuOpen] = useState<boolean>(false);
  const [peopleSheetOpen, setPeopleSheetOpen] = useState<boolean>(false);

  const [followedByGroup, setFollowedByGroup] = useState<
    Record<string, string[]>
  >(() => ({
    'grp-tehran-family-01': [
      myUserId,
      'user-mother-02',
      'user-father-03',
      'user-brother-04',
    ],
  }));

  const [cachedLocations, setCachedLocations] = useState<
    Array<SimLocation & { displayName: string; color: string }>
  >([]);

  // Server-enforced cooldown (currently 180 seconds; client does NOT send cooldown param)
  const [cooldownSeconds, setCooldownSeconds] = useState<number>(0);

  const [isMapLoading, setIsMapLoading] = useState<boolean>(false);
  const [simulateTileFailure, setSimulateTileFailure] =
    useState<boolean>(false);
  const [mapUnavailable, setMapUnavailable] = useState<boolean>(false);

  const [camera, setCamera] = useState<{
    lat: number;
    lng: number;
    zoom: number;
  }>({
    lat: 35.731,
    lng: 51.364,
    zoom: 12.2,
  });
  const hasFitInitialBoundsRef = useRef<Record<string, boolean>>({});

  // Background Location Service simulation state
  const [bgLastSent, setBgLastSent] = useState<{
    lat: number;
    lng: number;
    sentAt: number;
  }>({
    lat: 35.7219,
    lng: 51.3347,
    sentAt: Date.now() - 2 * 60 * 1000,
  });
  const [bgOfflineMode, setBgOfflineMode] = useState<boolean>(false);
  const [bgPendingQueue, setBgPendingQueue] = useState<{
    user_id: string;
    lat: number;
    lng: number;
    accuracy: number;
  } | null>(null);
  const [bgLastLog, setBgLastLog] = useState<string>(
    "supabase.from('locations').upsert({'user_id': myUserId, 'lat': 35.7219, 'lng': 51.3347, 'accuracy': 11.4}) — updated_at never sent"
  );

  const [inspectorTab, setInspectorTab] = useState<
    'contract' | 'background' | 'config'
  >('contract');

  // Cooldown 1-second decrement timer
  useEffect(() => {
    if (cooldownSeconds <= 0) return;
    const timer = setInterval(() => {
      setCooldownSeconds((prev) => Math.max(0, prev - 1));
    }, 1000);
    return () => clearInterval(timer);
  }, [cooldownSeconds]);

  const triggerMapLoadProgress = () => {
    if (simulateTileFailure) {
      setIsMapLoading(false);
      setMapUnavailable(true);
      return;
    }
    setMapUnavailable(false);
    setIsMapLoading(true);
    setTimeout(() => {
      setIsMapLoading(false);
    }, 600);
  };

  // 4. Fetch others: supabase.rpc('fetch_locations', params: {'p_group_id': groupId, 'p_target_user_ids': [selected member ids]})
  // Do NOT send a cooldown value; server enforces it (180 seconds) and returns JSON {ok: ...}
  const executeFetchLocationsRpc = (
    groupId: string,
    overrideTargets?: string[],
    bypassCooldownCheck = false
  ) => {
    const group = groups.find((g) => g.id === groupId);
    const followedIds =
      overrideTargets ??
      followedByGroup[groupId] ??
      members.filter((m) => m.groupId === groupId).map((m) => m.userId);

    const reqPayload = {
      p_group_id: groupId,
      p_target_user_ids: followedIds,
    };

    if (!group || group.expiresAt <= Date.now()) {
      const failRes = { ok: false, error: 'group_expired' };
      setLastApiCallLog({
        endpoint: "supabase.rpc('fetch_locations')",
        request: reqPayload,
        response: failRes,
      });
      setActiveGroupId(null);
      setErrorCode('group_expired');
      return;
    }

    const callerMember = members.find(
      (m) => m.groupId === groupId && m.userId === myUserId
    );
    if (!callerMember) {
      const failRes = { ok: false, error: 'not_a_member' };
      setLastApiCallLog({
        endpoint: "supabase.rpc('fetch_locations')",
        request: reqPayload,
        response: failRes,
      });
      setActiveGroupId(null);
      setErrorCode('not_a_member');
      return;
    }

    if (!bypassCooldownCheck && cooldownSeconds > 0) {
      const failRes = {
        ok: false,
        error: 'cooldown_active',
        remaining_seconds: cooldownSeconds,
      };
      setLastApiCallLog({
        endpoint: "supabase.rpc('fetch_locations')",
        request: reqPayload,
        response: failRes,
      });
      return;
    }

    const groupMembers = members.filter(
      (m) => m.groupId === groupId && followedIds.includes(m.userId)
    );

    const fetched = groupMembers
      .map((m) => {
        const loc = locations[m.userId];
        if (!loc) return null;
        return {
          ...loc,
          displayName: m.displayName,
          color: m.color,
        };
      })
      .filter(
        (x): x is SimLocation & { displayName: string; color: string } =>
          x !== null
      );

    const successRes = {
      ok: true,
      cooldown_seconds: 180,
      locations: fetched.map((f) => ({
        user_id: f.userId,
        display_name: f.displayName,
        color: f.color,
        lat: f.lat,
        lng: f.lng,
        accuracy: f.accuracy,
        updated_at: new Date(f.updatedAt).toISOString(),
      })),
    };

    setLastApiCallLog({
      endpoint: "supabase.rpc('fetch_locations')",
      request: reqPayload,
      response: successRes,
    });

    setCachedLocations(fetched);
    setCooldownSeconds(180); // 180s enforced by server
    triggerMapLoadProgress();

    if (!hasFitInitialBoundsRef.current[groupId] && fetched.length > 0) {
      hasFitInitialBoundsRef.current[groupId] = true;
      const avgLat =
        fetched.reduce((acc, c) => acc + c.lat, 0) / fetched.length;
      const avgLng =
        fetched.reduce((acc, c) => acc + c.lng, 0) / fetched.length;
      setCamera({
        lat: avgLat,
        lng: avgLng,
        zoom: fetched.length === 1 ? 14.5 : 12.2,
      });
    }
  };

  useEffect(() => {
    if (activeGroupId && cachedLocations.length === 0) {
      executeFetchLocationsRpc(activeGroupId, undefined, true);
    }
  }, [activeGroupId]);

  const activeGroup = useMemo(
    () => groups.find((g) => g.id === activeGroupId) ?? null,
    [groups, activeGroupId]
  );

  const activeGroupMembers = useMemo(
    () => members.filter((m) => m.groupId === activeGroupId),
    [members, activeGroupId]
  );

  const currentFollowedIds = useMemo(
    () =>
      activeGroupId
        ? followedByGroup[activeGroupId] ??
          activeGroupMembers.map((m) => m.userId)
        : [],
    [followedByGroup, activeGroupId, activeGroupMembers]
  );

  const visibleLocations = useMemo(
    () =>
      cachedLocations.filter((loc) => currentFollowedIds.includes(loc.userId)),
    [cachedLocations, currentFollowedIds]
  );

  // 1. Join: call Edge Function "join_group" with body {code, display_name}
  const handleJoinGroup = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorCode(null);

    const normalizedCode = normalizeGroupCode(loginCodeDisplay);
    const displayName = loginRoleInput.trim();

    const reqBody = {
      code: normalizedCode,
      display_name: displayName,
    };

    if (!displayName || displayName.length > 32) {
      const res = { ok: false, error: 'invalid_name' as const };
      setLastApiCallLog({
        endpoint: 'functions.invoke("join_group")',
        request: reqBody,
        response: res,
      });
      setErrorCode('invalid_name');
      return;
    }

    if (failedJoinCount >= 5) {
      const res = { ok: false, error: 'too_many_attempts' as const };
      setLastApiCallLog({
        endpoint: 'functions.invoke("join_group")',
        request: reqBody,
        response: res,
      });
      setErrorCode('too_many_attempts');
      return;
    }

    if (!isValidGroupCodeAlphabet(normalizedCode)) {
      setFailedJoinCount((c) => c + 1);
      const res = { ok: false, error: 'invalid_code' as const };
      setLastApiCallLog({
        endpoint: 'functions.invoke("join_group")',
        request: reqBody,
        response: res,
      });
      setErrorCode('invalid_code');
      return;
    }

    const inputHash = simpleSha256Preview(normalizedCode);
    const matchedGroup = groups.find((g) => g.codeHash === inputHash);

    if (!matchedGroup) {
      setFailedJoinCount((c) => c + 1);
      const res = { ok: false, error: 'invalid_code' as const };
      setLastApiCallLog({
        endpoint: 'functions.invoke("join_group")',
        request: reqBody,
        response: res,
      });
      setErrorCode('invalid_code');
      return;
    }

    if (matchedGroup.expiresAt <= Date.now()) {
      const res = { ok: false, error: 'group_expired' as const };
      setLastApiCallLog({
        endpoint: 'functions.invoke("join_group")',
        request: reqBody,
        response: res,
      });
      setErrorCode('group_expired');
      return;
    }

    const existingGroupMembers = members.filter(
      (m) => m.groupId === matchedGroup.id
    );

    const existingSelf = existingGroupMembers.find(
      (m) => m.userId === myUserId
    );
    if (existingSelf) {
      const successRes = {
        ok: true,
        group_id: matchedGroup.id,
        max_devices: matchedGroup.maxDevices,
        expires_at: new Date(matchedGroup.expiresAt).toISOString(),
        display_name: existingSelf.displayName,
        color: existingSelf.color,
      };
      setLastApiCallLog({
        endpoint: 'functions.invoke("join_group")',
        request: reqBody,
        response: successRes,
      });
      setSavedMyDisplayName(existingSelf.displayName);
      setSavedMyColor(existingSelf.color);
      setActiveGroupId(matchedGroup.id);
      setCooldownSeconds(0);
      executeFetchLocationsRpc(matchedGroup.id, undefined, true);
      return;
    }

    if (existingGroupMembers.length >= matchedGroup.maxDevices) {
      const res = { ok: false, error: 'group_full' as const };
      setLastApiCallLog({
        endpoint: 'functions.invoke("join_group")',
        request: reqBody,
        response: res,
      });
      setErrorCode('group_full');
      return;
    }

    const nameTaken = existingGroupMembers.some(
      (m) => m.displayName.toLowerCase() === displayName.toLowerCase()
    );
    if (nameTaken) {
      const res = { ok: false, error: 'name_taken' as const };
      setLastApiCallLog({
        endpoint: 'functions.invoke("join_group")',
        request: reqBody,
        response: res,
      });
      setErrorCode('name_taken');
      return;
    }

    const usedColors = new Set(existingGroupMembers.map((m) => m.color));
    const assignedColor =
      FIXED_PALETTE.find((c) => !usedColors.has(c)) ??
      FIXED_PALETTE[existingGroupMembers.length % FIXED_PALETTE.length];

    const newMember: SimMember = {
      groupId: matchedGroup.id,
      userId: myUserId,
      displayName,
      color: assignedColor,
    };

    const extraSeedMembers: SimMember[] =
      existingGroupMembers.length === 0
        ? [
            {
              groupId: matchedGroup.id,
              userId: 'user-mother-02',
              displayName: 'Mother',
              color: FIXED_PALETTE[1],
            },
          ]
        : [];

    const updatedMembers = [...members, ...extraSeedMembers, newMember];
    setMembers(updatedMembers);

    const groupMemberIds = updatedMembers
      .filter((m) => m.groupId === matchedGroup.id)
      .map((m) => m.userId);

    setFollowedByGroup((prev) => ({
      ...prev,
      [matchedGroup.id]: groupMemberIds,
    }));

    const successRes = {
      ok: true,
      group_id: matchedGroup.id,
      max_devices: matchedGroup.maxDevices,
      expires_at: new Date(matchedGroup.expiresAt).toISOString(),
      display_name: displayName,
      color: assignedColor,
    };

    setLastApiCallLog({
      endpoint: 'functions.invoke("join_group")',
      request: reqBody,
      response: successRes,
    });

    // Save group_id, my display_name, and color locally
    setSavedMyDisplayName(displayName);
    setSavedMyColor(assignedColor);
    setActiveGroupId(matchedGroup.id);
    setCooldownSeconds(0);
    setTimeout(() => {
      executeFetchLocationsRpc(matchedGroup.id, groupMemberIds, true);
    }, 50);
  };

  // 5. Exit: supabase.rpc('leave_group', params: {'p_group_id': groupId}), clear local data, go to login screen
  const handleExitGroup = () => {
    if (!activeGroupId) return;
    const leavingGroupId = activeGroupId;

    setLastApiCallLog({
      endpoint: "supabase.rpc('leave_group')",
      request: { p_group_id: leavingGroupId },
      response: { ok: true },
    });

    const remainingMembers = members.filter(
      (m) => !(m.groupId === leavingGroupId && m.userId === myUserId)
    );
    setMembers(remainingMembers);

    const myRemainingGroups = remainingMembers.filter(
      (m) => m.userId === myUserId
    );
    if (myRemainingGroups.length === 0) {
      setLocations((prev) => {
        const next = { ...prev };
        delete next[myUserId];
        return next;
      });
    }

    setActiveGroupId(null);
    setCachedLocations([]);
    setCooldownSeconds(0);
    setErrorCode(null);
  };

  // 3. Send my location: supabase.from('locations').upsert({'user_id': myUserId, 'lat': ..., 'lng': ..., 'accuracy': ...})
  // Never send updated_at (the server sets it)
  const simulateBackgroundLocationTick = (
    mode: 'small_move_30m' | 'moving_110m' | 'stationary_20min'
  ) => {
    if (!locationPermissionOn) {
      setBgLastLog(
        'Skipped: Phone location permission / GPS service is currently OFF.'
      );
      return;
    }

    let deltaLat = 0;
    let deltaLng = 0;
    let simulatedElapsedSec = 120;

    if (mode === 'small_move_30m') {
      deltaLat = 0.00022;
      deltaLng = 0.00012;
    } else if (mode === 'moving_110m') {
      deltaLat = 0.00095;
      deltaLng = 0.00065;
    } else if (mode === 'stationary_20min') {
      deltaLat = 0.00004;
      deltaLng = 0.00003;
      simulatedElapsedSec = 1220;
    }

    const candidateLat = Number((bgLastSent.lat + deltaLat).toFixed(6));
    const candidateLng = Number((bgLastSent.lng + deltaLng).toFixed(6));
    const dist = haversineMeters(
      bgLastSent.lat,
      bgLastSent.lng,
      candidateLat,
      candidateLng
    );

    if (dist < 75 && simulatedElapsedSec < 1200) {
      setBgLastLog(
        `Skipped send: moved ${dist.toFixed(1)}m (< 75m threshold) and elapsed ${simulatedElapsedSec}s (< 20m heartbeat).`
      );
      return;
    }

    // Client payload NEVER includes updated_at
    const clientUpsertPayload = {
      user_id: myUserId,
      lat: candidateLat,
      lng: candidateLng,
      accuracy: 9.8,
    };

    if (bgOfflineMode) {
      setBgPendingQueue(clientUpsertPayload);
      setBgLastLog(
        `Offline: Queued ${JSON.stringify(clientUpsertPayload)} in SharedPreferences for retry.`
      );
      return;
    }

    setLocations((prev) => ({
      ...prev,
      [myUserId]: {
        userId: myUserId,
        lat: candidateLat,
        lng: candidateLng,
        accuracy: 9.8,
        updatedAt: Date.now(), // Server sets updated_at
      },
    }));
    setBgLastSent({
      lat: candidateLat,
      lng: candidateLng,
      sentAt: Date.now(),
    });
    setBgPendingQueue(null);
    setLastApiCallLog({
      endpoint: "supabase.from('locations').upsert(...)",
      request: clientUpsertPayload,
      response: { status: 201, note: 'Server sets updated_at = now()' },
    });
    setBgLastLog(
      `Upserted ${JSON.stringify(clientUpsertPayload)} (server set updated_at).`
    );
  };

  const toggleOfflineMode = () => {
    const nextOffline = !bgOfflineMode;
    setBgOfflineMode(nextOffline);
    if (!nextOffline && bgPendingQueue) {
      setLocations((prev) => ({
        ...prev,
        [myUserId]: {
          userId: myUserId,
          lat: bgPendingQueue.lat,
          lng: bgPendingQueue.lng,
          accuracy: bgPendingQueue.accuracy,
          updatedAt: Date.now(),
        },
      }));
      setBgLastSent({
        lat: bgPendingQueue.lat,
        lng: bgPendingQueue.lng,
        sentAt: Date.now(),
      });
      setBgLastLog(
        `Reconnected: Flushed queued payload ${JSON.stringify(bgPendingQueue)}.`
      );
      setBgPendingQueue(null);
    }
  };

  const formatCooldownMmSs = (sec: number) => {
    const m = Math.floor(sec / 60)
      .toString()
      .padStart(2, '0');
    const s = (sec % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
  };

  const formatMinutesAgo = (timestampMs: number) => {
    const mins = Math.max(0, Math.floor((Date.now() - timestampMs) / 60000));
    if (mins < 1) return t('updated_just_now');
    return t('updated_min_ago', mins);
  };

  const mapCanvasTheme = useMemo(() => {
    if (effectiveMapStyle === 'dark') {
      return {
        bg: '#121417',
        grid: '#1E2228',
        roads: '#262B33',
        highway: '#323944',
        park: '#15221B',
        water: '#0F1C2E',
      };
    }
    if (effectiveMapStyle === 'bright') {
      return {
        bg: '#F4F1EA',
        grid: '#E6E1D6',
        roads: '#FFFFFF',
        highway: '#FCD34D',
        park: '#D8F3DC',
        water: '#BAE6FD',
      };
    }
    return {
      bg: '#F2F3F5',
      grid: '#E5E7EB',
      roads: '#FFFFFF',
      highway: '#D1D5DB',
      park: '#E8EFEA',
      water: '#DCE7F3',
    };
  }, [effectiveMapStyle]);

  return (
    <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
      {/* LEFT COLUMN (5 cols): Interactive Mobile App Preview */}
      <div className="lg:col-span-5 flex flex-col items-center">
        <div className="w-full max-w-[410px] rounded-3xl border border-neutral-300 dark:border-neutral-800 bg-white dark:bg-neutral-950 shadow-sm overflow-hidden flex flex-col">
          {/* Device Status Bar */}
          <div className="px-5 py-2.5 border-b border-neutral-200 dark:border-neutral-800 flex items-center justify-between text-[11px] font-mono text-neutral-500 dark:text-neutral-400">
            <span>9:41</span>
            <span className="truncate max-w-[190px]">
              {simulateMissingConfig
                ? 'Missing env.json'
                : WAYMORPHIC_STYLES[effectiveMapStyle].replace('https://', '')}
            </span>
            <span>100%</span>
          </div>

          {/* Mobile App Viewport */}
          <div
            dir={isRtl ? 'rtl' : 'ltr'}
            className="relative h-[660px] flex flex-col bg-white dark:bg-neutral-950 text-neutral-950 dark:text-neutral-100 select-none"
          >
            {/* SCREEN 0: MISSING SUPABASE CONFIG SCREEN */}
            {simulateMissingConfig ? (
              <div className="flex-1 flex flex-col justify-center p-6 space-y-4">
                <AlertCircle className="w-11 h-11" />
                <h2 className="text-xl font-bold tracking-tight">
                  {t('missing_config_title')}
                </h2>
                <p className="text-sm text-neutral-600 dark:text-neutral-300 leading-relaxed">
                  {t('missing_config_body')}
                </p>
                <div
                  dir="ltr"
                  className="p-3.5 rounded-xl border border-neutral-300 dark:border-neutral-700 font-mono text-xs font-semibold"
                >
                  flutter run --dart-define-from-file=config/env.json
                </div>
              </div>
            ) : !consentAccepted ? (
              /* SCREEN 1: FIRST LAUNCH CONSENT & PERMISSIONS */
              <div className="flex-1 flex flex-col justify-between p-6">
                <div className="space-y-4 my-auto">
                  <div className="w-11 h-11 rounded-xl border border-neutral-300 dark:border-neutral-700 flex items-center justify-center">
                    <ShieldCheck className="w-5 h-5" />
                  </div>
                  <h2 className="text-xl font-bold tracking-tight">
                    {t('consent_title')}
                  </h2>
                  <p className="text-sm text-neutral-600 dark:text-neutral-300 leading-relaxed">
                    {t('consent_body')}
                  </p>
                  <div className="p-4 rounded-xl border border-neutral-200 dark:border-neutral-800 bg-neutral-50 dark:bg-neutral-900/60 space-y-2.5 text-xs text-neutral-600 dark:text-neutral-400">
                    <p className="leading-relaxed">
                      {t('consent_permissions_note')}
                    </p>
                    <p className="leading-relaxed border-t border-neutral-200 dark:border-neutral-800 pt-2">
                      {t('consent_oem_note')}
                    </p>
                  </div>
                </div>
                <button
                  onClick={() => {
                    setConsentAccepted(true);
                    setLocationPermissionOn(true);
                  }}
                  className="w-full min-h-[48px] rounded-xl bg-neutral-950 dark:bg-white text-white dark:text-neutral-950 font-semibold text-sm hover:opacity-90 transition-opacity cursor-pointer"
                >
                  {t('consent_accept')}
                </button>
              </div>
            ) : !activeGroup ? (
              /* SCREEN 2: LOGIN SCREEN (XXXX-XXXX-XXXX + Role Label) */
              <div className="flex-1 flex flex-col p-6 overflow-y-auto">
                <div className="mb-6">
                  <span className="text-xs font-mono text-neutral-500">
                    supabase.auth.signInAnonymously() · {myUserId}
                  </span>
                  <h2 className="text-xl font-bold tracking-tight mt-1">
                    {t('login_title')}
                  </h2>
                  <p className="text-xs text-neutral-500 dark:text-neutral-400 mt-1">
                    {t('login_subtitle')}
                  </p>
                </div>

                {errorCode && (
                  <div className="mb-4 p-3.5 rounded-xl border border-neutral-900 dark:border-neutral-200 bg-neutral-100 dark:bg-neutral-900 text-xs font-medium flex items-start gap-2.5">
                    <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
                    <div>
                      <div className="font-mono text-[11px] text-neutral-500">
                        error: &quot;{errorCode}&quot;
                      </div>
                      <div className="mt-0.5">{translateError(errorCode)}</div>
                    </div>
                  </div>
                )}

                <form onSubmit={handleJoinGroup} className="space-y-4">
                  <div>
                    <label className="block text-xs font-medium mb-1.5">
                      {t('code_label')}
                    </label>
                    <div dir="ltr">
                      <input
                        type="text"
                        value={loginCodeDisplay}
                        onChange={(e) =>
                          setLoginCodeDisplay(
                            formatGroupCodeDisplay(e.target.value)
                          )
                        }
                        placeholder={t('code_hint')}
                        className="w-full h-11 px-3.5 rounded-lg border border-neutral-300 dark:border-neutral-700 bg-transparent font-mono text-sm tracking-wider font-semibold focus:outline-none focus:border-neutral-950 dark:focus:border-white"
                      />
                    </div>
                    <div className="mt-1.5 flex flex-wrap gap-2">
                      {groups.map((g) => (
                        <button
                          key={g.id}
                          type="button"
                          onClick={() =>
                            setLoginCodeDisplay(
                              formatGroupCodeDisplay(g.plainCodeHint)
                            )
                          }
                          className="text-[11px] font-mono underline text-neutral-500 hover:text-neutral-900 dark:hover:text-white cursor-pointer"
                        >
                          {formatGroupCodeDisplay(g.plainCodeHint)}
                        </button>
                      ))}
                      <button
                        type="button"
                        onClick={() =>
                          setLoginCodeDisplay(
                            formatGroupCodeDisplay('۹h۳n ۶r۸t ۲y۵v')
                          )
                        }
                        className="text-[11px] underline text-neutral-500 hover:text-neutral-900 dark:hover:text-white cursor-pointer"
                      >
                        Test Persian Digits (۹h۳n...)
                      </button>
                    </div>
                  </div>

                  <div>
                    <label className="block text-xs font-medium mb-1.5">
                      {t('role_label')}
                    </label>
                    <input
                      type="text"
                      value={loginRoleInput}
                      onChange={(e) => setLoginRoleInput(e.target.value)}
                      placeholder={t('role_hint')}
                      maxLength={32}
                      className="w-full h-11 px-3.5 rounded-lg border border-neutral-300 dark:border-neutral-700 bg-transparent text-sm focus:outline-none focus:border-neutral-950 dark:focus:border-white"
                    />
                  </div>

                  <button
                    type="submit"
                    className="w-full min-h-[48px] rounded-xl bg-neutral-950 dark:bg-white text-white dark:text-neutral-950 font-semibold text-sm hover:opacity-90 transition-opacity cursor-pointer"
                  >
                    {t('join_button')}
                  </button>
                </form>

                {/* Quick Error Code Preview Buttons */}
                <div className="mt-6 pt-4 border-t border-neutral-200 dark:border-neutral-800">
                  <div className="text-[11px] font-medium text-neutral-500 mb-2">
                    Preview Localized Error Messages ({lang.toUpperCase()}):
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {(
                      [
                        'invalid_name',
                        'too_many_attempts',
                        'invalid_code',
                        'group_expired',
                        'group_full',
                        'name_taken',
                        'unauthorized',
                        'bad_request',
                        'server_error',
                      ] as BackendErrorCode[]
                    ).map((errKey) => (
                      <button
                        key={errKey}
                        type="button"
                        onClick={() => setErrorCode(errKey)}
                        className={`px-2 py-1 rounded border text-[10px] font-mono cursor-pointer ${
                          errorCode === errKey
                            ? 'border-neutral-950 bg-neutral-950 text-white dark:border-white dark:bg-white dark:text-neutral-950'
                            : 'border-neutral-200 dark:border-neutral-800 text-neutral-600 dark:text-neutral-400'
                        }`}
                      >
                        {errKey}
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            ) : (
              /* SCREEN 3: MAIN MAP SCREEN */
              <div className="flex-1 flex flex-col overflow-hidden relative">
                {/* App Bar */}
                <div className="h-13 px-3 border-b border-neutral-200 dark:border-neutral-800 flex items-center justify-between gap-1 shrink-0 bg-white dark:bg-neutral-950 z-20">
                  <div className="flex items-center gap-2 min-w-0">
                    <span
                      className="w-2.5 h-2.5 rounded-full shrink-0"
                      style={{ backgroundColor: savedMyColor }}
                    />
                    <span className="text-sm font-bold truncate">
                      {savedMyDisplayName}
                    </span>
                  </div>

                  <div className="flex items-center gap-1 shrink-0">
                    {/* 1. Refresh button with server-enforced 180s cooldown countdown */}
                    <button
                      onClick={() => {
                        if (activeGroupId) {
                          executeFetchLocationsRpc(activeGroupId);
                        }
                      }}
                      disabled={cooldownSeconds > 0}
                      title={t('refresh')}
                      className={`min-h-[38px] px-2.5 rounded-lg border text-xs font-medium flex items-center gap-1.5 transition-colors whitespace-nowrap ${
                        cooldownSeconds > 0
                          ? 'border-neutral-200 dark:border-neutral-800 text-neutral-400 dark:text-neutral-500 cursor-not-allowed'
                          : 'border-neutral-900 dark:border-neutral-200 bg-neutral-950 text-white dark:bg-white dark:text-neutral-950 cursor-pointer'
                      }`}
                    >
                      <RefreshCw
                        className={`w-3.5 h-3.5 ${
                          isMapLoading ? 'animate-spin' : ''
                        }`}
                      />
                      <span className="font-mono tabular-nums">
                        {cooldownSeconds > 0
                          ? formatCooldownMmSs(cooldownSeconds)
                          : t('refresh')}
                      </span>
                    </button>

                    {/* 2. People (multi-select bottom sheet trigger) */}
                    <button
                      onClick={() => {
                        setStyleMenuOpen(false);
                        setPeopleSheetOpen((v) => !v);
                      }}
                      title={t('people')}
                      className="min-h-[38px] min-w-[38px] rounded-lg hover:bg-neutral-100 dark:hover:bg-neutral-900 flex items-center justify-center cursor-pointer"
                    >
                      <Users className="w-4 h-4" />
                    </button>

                    {/* 3. Map style switcher */}
                    <div className="relative">
                      <button
                        onClick={() => {
                          setPeopleSheetOpen(false);
                          setStyleMenuOpen((v) => !v);
                        }}
                        title={t('map_style')}
                        className="min-h-[38px] min-w-[38px] rounded-lg hover:bg-neutral-100 dark:hover:bg-neutral-900 flex items-center justify-center cursor-pointer"
                      >
                        <Layers className="w-4 h-4" />
                      </button>

                      {styleMenuOpen && (
                        <div className="absolute top-10 right-0 w-44 rounded-xl border border-neutral-200 dark:border-neutral-800 bg-white dark:bg-neutral-900 shadow-lg py-1 z-40">
                          {(
                            [
                              ['positron', t('style_positron')],
                              ['bright', t('style_bright')],
                              ['dark', t('style_dark')],
                            ] as Array<[MapStyleOption, string]>
                          ).map(([styleKey, label]) => (
                            <button
                              key={styleKey}
                              onClick={() => {
                                localStorage.setItem('ft_map_style', styleKey);
                                setUserPickedStyle(styleKey);
                                setStyleMenuOpen(false);
                                triggerMapLoadProgress();
                              }}
                              className="w-full px-3 py-2 text-xs text-left flex items-center justify-between hover:bg-neutral-100 dark:hover:bg-neutral-800 cursor-pointer"
                            >
                              <span>{label}</span>
                              {effectiveMapStyle === styleKey && (
                                <Check className="w-3.5 h-3.5" />
                              )}
                            </button>
                          ))}
                        </div>
                      )}
                    </div>

                    {/* 4. Exit group */}
                    <button
                      onClick={handleExitGroup}
                      title={t('exit_group')}
                      className="min-h-[38px] min-w-[38px] rounded-lg hover:bg-neutral-100 dark:hover:bg-neutral-900 flex items-center justify-center cursor-pointer"
                    >
                      <LogOut className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                {!locationPermissionOn && (
                  <div className="px-3.5 py-2 bg-neutral-950 text-white dark:bg-white dark:text-neutral-950 text-[11px] font-medium flex items-center justify-between">
                    <span>{t('location_off_notice')}</span>
                    <button
                      onClick={() => setLocationPermissionOn(true)}
                      className="underline font-semibold ms-2 shrink-0 cursor-pointer"
                    >
                      Enable
                    </button>
                  </div>
                )}

                {/* MAP AREA */}
                <div
                  className="relative flex-1 overflow-hidden"
                  style={{ backgroundColor: mapCanvasTheme.bg }}
                >
                  {isMapLoading && (
                    <div className="absolute top-0 left-0 right-0 h-1 bg-neutral-200 dark:bg-neutral-800 overflow-hidden z-30">
                      <div className="h-full w-1/2 bg-neutral-950 dark:bg-white animate-pulse" />
                    </div>
                  )}

                  {!mapUnavailable && (
                    <svg
                      viewBox="0 0 400 360"
                      className="w-full h-full object-cover"
                    >
                      <path
                        d="M 30 40 L 125 35 L 110 115 L 25 95 Z"
                        fill={mapCanvasTheme.park}
                      />
                      <path
                        d="M 270 190 L 380 175 L 390 295 L 285 280 Z"
                        fill={mapCanvasTheme.park}
                      />
                      <path
                        d="M 0 260 Q 140 220, 240 270 T 400 230 L 400 255 Q 250 295, 140 245 T 0 285 Z"
                        fill={mapCanvasTheme.water}
                      />
                      <g stroke={mapCanvasTheme.grid} strokeWidth="1">
                        <line x1="0" y1="60" x2="400" y2="60" />
                        <line x1="0" y1="120" x2="400" y2="120" />
                        <line x1="0" y1="180" x2="400" y2="180" />
                        <line x1="0" y1="240" x2="400" y2="240" />
                        <line x1="0" y1="300" x2="400" y2="300" />
                        <line x1="70" y1="0" x2="70" y2="360" />
                        <line x1="140" y1="0" x2="140" y2="360" />
                        <line x1="210" y1="0" x2="210" y2="360" />
                        <line x1="280" y1="0" x2="280" y2="360" />
                        <line x1="350" y1="0" x2="350" y2="360" />
                      </g>
                      <g
                        stroke={mapCanvasTheme.roads}
                        strokeWidth="4"
                        fill="none"
                      >
                        <path d="M 0 150 Q 190 140, 400 165" />
                        <path d="M 185 0 L 205 360" />
                        <path d="M 45 360 L 340 0" />
                      </g>
                      <path
                        d="M 0 95 Q 200 110, 400 75"
                        stroke={mapCanvasTheme.highway}
                        strokeWidth="5"
                        fill="none"
                      />

                      {visibleLocations.map((loc) => {
                        const scale = Math.pow(2, camera.zoom - 12.2);
                        const x = 200 + (loc.lng - camera.lng) * 2800 * scale;
                        const y = 180 - (loc.lat - camera.lat) * 3200 * scale;
                        return (
                          <g key={loc.userId}>
                            <circle
                              cx={x}
                              cy={y}
                              r={18}
                              fill={loc.color}
                              fillOpacity={0.16}
                            />
                            <circle
                              cx={x}
                              cy={y}
                              r={9}
                              fill={loc.color}
                              stroke="#FFFFFF"
                              strokeWidth={2.5}
                            />
                          </g>
                        );
                      })}
                    </svg>
                  )}

                  {mapUnavailable && (
                    <div className="absolute top-3 left-3 right-3 p-3.5 rounded-xl border border-neutral-300 dark:border-neutral-700 bg-white/95 dark:bg-neutral-900/95 shadow-sm flex items-center justify-between gap-3 z-30">
                      <span className="text-xs leading-snug">
                        {t('map_unavailable')}
                      </span>
                      <button
                        onClick={() => {
                          setSimulateTileFailure(false);
                          setMapUnavailable(false);
                          triggerMapLoadProgress();
                        }}
                        className="px-3 py-1.5 rounded-lg bg-neutral-950 text-white dark:bg-white dark:text-neutral-950 text-xs font-semibold shrink-0 cursor-pointer"
                      >
                        {t('retry')}
                      </button>
                    </div>
                  )}

                  <div className="absolute top-3 left-3 flex flex-col gap-1 z-20">
                    <button
                      onClick={() =>
                        setCamera((c) => ({
                          ...c,
                          zoom: Math.min(18, Number((c.zoom + 1).toFixed(1))),
                        }))
                      }
                      className="w-8 h-8 rounded-lg bg-white/90 dark:bg-neutral-900/90 border border-neutral-300 dark:border-neutral-700 text-xs font-mono font-bold flex items-center justify-center cursor-pointer"
                    >
                      +
                    </button>
                    <button
                      onClick={() =>
                        setCamera((c) => ({
                          ...c,
                          zoom: Math.max(2, Number((c.zoom - 1).toFixed(1))),
                        }))
                      }
                      className="w-8 h-8 rounded-lg bg-white/90 dark:bg-neutral-900/90 border border-neutral-300 dark:border-neutral-700 text-xs font-mono font-bold flex items-center justify-center cursor-pointer"
                    >
                      -
                    </button>
                  </div>

                  <div className="absolute bottom-2 left-2.5 right-2.5 flex items-center justify-between text-[10px] font-mono pointer-events-none">
                    <span className="px-1.5 py-0.5 rounded bg-white/80 dark:bg-neutral-900/80 text-neutral-700 dark:text-neutral-300">
                      LatLng({camera.lat.toFixed(4)}, {camera.lng.toFixed(4)}) · z
                      {camera.zoom.toFixed(1)}
                    </span>
                    <span className="px-1.5 py-0.5 rounded bg-white/85 dark:bg-neutral-900/85 text-neutral-600 dark:text-neutral-400">
                      © OpenStreetMap · Waymorphic
                    </span>
                  </div>

                  {peopleSheetOpen && (
                    <div className="absolute inset-0 bg-black/40 z-30 flex items-end">
                      <div className="w-full rounded-t-2xl bg-white dark:bg-neutral-900 border-t border-neutral-200 dark:border-neutral-800 p-4 space-y-3">
                        <div className="flex items-center justify-between">
                          <div>
                            <h3 className="text-sm font-bold">
                              {t('people_sheet_title')}
                            </h3>
                            <p className="text-[11px] text-neutral-500">
                              {t('people_sheet_subtitle')}
                            </p>
                          </div>
                          <button
                            onClick={() => setPeopleSheetOpen(false)}
                            className="text-xs font-semibold underline cursor-pointer"
                          >
                            Done
                          </button>
                        </div>
                        <div className="space-y-1.5 max-h-44 overflow-y-auto">
                          {activeGroupMembers.map((m) => {
                            const checked = currentFollowedIds.includes(
                              m.userId
                            );
                            return (
                              <label
                                key={m.userId}
                                className="flex items-center justify-between p-2 rounded-lg hover:bg-neutral-100 dark:hover:bg-neutral-800 cursor-pointer text-xs"
                              >
                                <div className="flex items-center gap-2.5">
                                  <span
                                    className="w-3 h-3 rounded-full shrink-0"
                                    style={{ backgroundColor: m.color }}
                                  />
                                  <span className="font-medium">
                                    {m.displayName}
                                  </span>
                                </div>
                                <input
                                  type="checkbox"
                                  checked={checked}
                                  onChange={() => {
                                    if (!activeGroupId) return;
                                    const next = checked
                                      ? currentFollowedIds.filter(
                                          (id) => id !== m.userId
                                        )
                                      : [...currentFollowedIds, m.userId];
                                    setFollowedByGroup((prev) => ({
                                      ...prev,
                                      [activeGroupId]: next,
                                    }));
                                  }}
                                  className="h-4 w-4 accent-neutral-900 dark:accent-white"
                                />
                              </label>
                            );
                          })}
                        </div>
                      </div>
                    </div>
                  )}
                </div>

                {/* BOTTOM PANEL: Member Chips + "Open in maps" Snapshot Actions */}
                <div className="p-3 border-t border-neutral-200 dark:border-neutral-800 bg-white dark:bg-neutral-950 space-y-2.5 shrink-0">
                  {visibleLocations.length === 0 ? (
                    <div className="text-xs text-neutral-500 py-2">
                      {t('no_followed_members')}
                    </div>
                  ) : (
                    <>
                      <div className="flex items-center gap-1.5 overflow-x-auto pb-1">
                        {visibleLocations.map((loc) => (
                          <button
                            key={loc.userId}
                            onClick={() =>
                              setCamera({
                                lat: loc.lat,
                                lng: loc.lng,
                                zoom: 15.5,
                              })
                            }
                            className="px-2.5 py-1.5 rounded-lg border border-neutral-200 dark:border-neutral-800 hover:border-neutral-900 dark:hover:border-white text-xs flex items-center gap-1.5 shrink-0 transition-colors cursor-pointer"
                          >
                            <span
                              className="w-2.5 h-2.5 rounded-full shrink-0"
                              style={{ backgroundColor: loc.color }}
                            />
                            <span className="font-semibold">
                              {loc.displayName}
                            </span>
                            <span className="text-[11px] text-neutral-500">
                              · {formatMinutesAgo(loc.updatedAt)}
                            </span>
                          </button>
                        ))}
                      </div>

                      <div className="divide-y divide-neutral-100 dark:divide-neutral-900 max-h-32 overflow-y-auto">
                        {visibleLocations.map((loc) => {
                          const latStr = loc.lat.toFixed(6);
                          const lngStr = loc.lng.toFixed(6);
                          const googleMapsUrl = `https://www.google.com/maps/search/?api=1&query=${latStr},${lngStr}`;
                          const appleOrGeoUrl = `https://maps.apple.com/?ll=${latStr},${lngStr}&q=${encodeURIComponent(
                            loc.displayName
                          )}`;

                          return (
                            <div
                              key={loc.userId}
                              className="py-1.5 flex items-center justify-between gap-2 text-xs"
                            >
                              <div className="flex items-center gap-2 min-w-0">
                                <span
                                  className="w-2 h-2 rounded-full shrink-0"
                                  style={{ backgroundColor: loc.color }}
                                />
                                <span className="font-medium truncate">
                                  {loc.displayName}
                                </span>
                                <span className="text-[11px] text-neutral-500 shrink-0">
                                  ({formatMinutesAgo(loc.updatedAt)})
                                </span>
                              </div>
                              <div className="flex items-center gap-2 shrink-0">
                                <a
                                  href={googleMapsUrl}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  className="text-[11px] font-semibold underline flex items-center gap-1 hover:opacity-80"
                                >
                                  <span>{t('open_in_maps')}</span>
                                  <ExternalLink className="w-3 h-3" />
                                </a>
                                <a
                                  href={appleOrGeoUrl}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  className="text-[11px] text-neutral-500 underline hover:text-neutral-900 dark:hover:text-white"
                                >
                                  {t('open_in_system_geo')}
                                </a>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </>
                  )}
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* RIGHT COLUMN (7 cols): Exact Backend API Contract & Environment Config Workbench */}
      <div className="lg:col-span-7 space-y-6">
        <div className="p-6 rounded-2xl border border-neutral-200 dark:border-neutral-800 bg-white dark:bg-neutral-900/40 space-y-5">
          <div className="flex flex-wrap items-center justify-between gap-4 border-b border-neutral-200 dark:border-neutral-800 pb-4">
            <div>
              <h2 className="text-lg font-bold tracking-tight">
                Flutter Client State &amp; API Inspector
              </h2>
              <p className="text-xs text-neutral-500 dark:text-neutral-400 mt-0.5">
                Reads SUPABASE_URL &amp; SUPABASE_ANON_KEY at compile time via --dart-define-from-file=config/env.json.
              </p>
            </div>

            <div className="flex items-center gap-1 p-1 rounded-xl bg-neutral-100 dark:bg-neutral-900 border border-neutral-200 dark:border-neutral-800">
              {(
                [
                  ['contract', 'JSON RPC & Edge Payloads'],
                  ['background', 'Location Upsert'],
                  ['config', 'env.json & CLI Build'],
                ] as const
              ).map(([tabId, label]) => (
                <button
                  key={tabId}
                  onClick={() => setInspectorTab(tabId)}
                  className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors cursor-pointer whitespace-nowrap ${
                    inspectorTab === tabId
                      ? 'bg-neutral-950 text-white dark:bg-white dark:text-neutral-950'
                      : 'text-neutral-600 dark:text-neutral-400 hover:text-neutral-950 dark:hover:text-white'
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
          </div>

          {/* Quick Scenario Bar */}
          <div className="flex flex-wrap items-center gap-2">
            <button
              onClick={() => setSimulateMissingConfig((v) => !v)}
              className={`px-3 py-1.5 rounded-lg border text-xs font-medium cursor-pointer ${
                simulateMissingConfig
                  ? 'border-neutral-950 bg-neutral-950 text-white dark:border-white dark:bg-white dark:text-neutral-950'
                  : 'border-neutral-300 dark:border-neutral-700 hover:bg-neutral-100 dark:hover:bg-neutral-800'
              }`}
            >
              {simulateMissingConfig
                ? 'Restore SUPABASE_URL Config'
                : 'Test Missing Config Screen'}
            </button>
            <button
              onClick={() => setCooldownSeconds(0)}
              className="px-3 py-1.5 rounded-lg border border-neutral-300 dark:border-neutral-700 text-xs font-medium flex items-center gap-1.5 hover:bg-neutral-100 dark:hover:bg-neutral-800 cursor-pointer"
            >
              <FastForward className="w-3.5 h-3.5" />
              <span>Skip 180s Cooldown</span>
            </button>
            <button
              onClick={() => {
                if (activeGroupId) {
                  setLastApiCallLog({
                    endpoint: "supabase.rpc('fetch_locations')",
                    request: {
                      p_group_id: activeGroupId,
                      p_target_user_ids: currentFollowedIds,
                    },
                    response: {
                      ok: false,
                      error: 'cooldown_active',
                      remaining_seconds: 142,
                    },
                  });
                  setCooldownSeconds(142);
                }
              }}
              className="px-3 py-1.5 rounded-lg border border-neutral-300 dark:border-neutral-700 text-xs font-medium hover:bg-neutral-100 dark:hover:bg-neutral-800 cursor-pointer"
            >
              Simulate {`{ok: false, error: "cooldown_active"}`}
            </button>
            <button
              onClick={() => {
                setActiveGroupId(null);
                setErrorCode('group_expired');
                setLastApiCallLog({
                  endpoint: "supabase.rpc('fetch_locations')",
                  request: { p_group_id: 'grp-tehran-family-01' },
                  response: { ok: false, error: 'group_expired' },
                });
              }}
              className="px-3 py-1.5 rounded-lg border border-neutral-300 dark:border-neutral-700 text-xs font-medium hover:bg-neutral-100 dark:hover:bg-neutral-800 cursor-pointer"
            >
              Simulate {`{ok: false, error: "group_expired"}`}
            </button>
          </div>

          {inspectorTab === 'contract' && (
            <div className="space-y-4">
              <div className="rounded-xl border border-neutral-200 dark:border-neutral-800 overflow-hidden">
                <div className="px-4 py-2.5 bg-neutral-50 dark:bg-neutral-900 border-b border-neutral-200 dark:border-neutral-800 flex items-center justify-between text-xs font-mono">
                  <span className="font-semibold">
                    Latest Client Call: {lastApiCallLog.endpoint}
                  </span>
                  <button
                    onClick={() => onSelectDeliverable('supabase-service')}
                    className="underline text-neutral-500 hover:text-neutral-900 dark:hover:text-white cursor-pointer"
                  >
                    View supabase_service.dart
                  </button>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 divide-y md:divide-y-0 md:divide-x divide-neutral-200 dark:divide-neutral-800 bg-neutral-950 text-neutral-100 text-xs font-mono">
                  <div className="p-4 overflow-x-auto">
                    <div className="text-neutral-400 mb-1.5">
                      Request Payload:
                    </div>
                    <pre className="leading-relaxed">
                      {JSON.stringify(lastApiCallLog.request, null, 2)}
                    </pre>
                  </div>
                  <div className="p-4 overflow-x-auto">
                    <div className="text-neutral-400 mb-1.5">
                      JSON Response:
                    </div>
                    <pre className="leading-relaxed">
                      {JSON.stringify(lastApiCallLog.response, null, 2)}
                    </pre>
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
                <div className="p-3.5 rounded-xl border border-neutral-200 dark:border-neutral-800 space-y-1">
                  <div className="font-mono font-semibold">
                    1. join_group Edge Function
                  </div>
                  <div className="text-neutral-500">
                    Sends <code>{`{code, display_name}`}</code> (12 chars from{' '}
                    <code>ABCDEFGHJKMNPQRSTUVWXYZ23456789</code>). Saves{' '}
                    <code>group_id, display_name, color</code> locally on{' '}
                    <code>ok: true</code>.
                  </div>
                </div>
                <div className="p-3.5 rounded-xl border border-neutral-200 dark:border-neutral-800 space-y-1">
                  <div className="font-mono font-semibold">
                    4. fetch_locations RPC
                  </div>
                  <div className="text-neutral-500">
                    Sends <code>{`{p_group_id, p_target_user_ids}`}</code> with
                    no client cooldown parameter. Parses JSON{' '}
                    <code>{`{ok, cooldown_seconds, locations}`}</code> or{' '}
                    <code>{`{ok: false, error, remaining_seconds}`}</code>.
                  </div>
                </div>
              </div>
            </div>
          )}

          {inspectorTab === 'background' && (
            <div className="space-y-4">
              <div className="p-4 rounded-xl border border-neutral-200 dark:border-neutral-800 bg-neutral-50 dark:bg-neutral-900/50 space-y-2">
                <div className="text-xs font-semibold">
                  3. Send My Location (Never Sends updated_at)
                </div>
                <p className="text-xs text-neutral-600 dark:text-neutral-400 leading-relaxed">
                  Calls{' '}
                  <code className="font-mono">
                    supabase.from(&apos;locations&apos;).upsert(&#123;&apos;user_id&apos;:
                    myUserId, &apos;lat&apos;: ..., &apos;lng&apos;: ...,
                    &apos;accuracy&apos;: ...&#125;)
                  </code>
                  . The server sets <code className="font-mono">updated_at</code>.
                  Never selects from <code className="font-mono">public.locations</code> for other users.
                </p>
                <div className="pt-2 text-xs font-mono text-neutral-700 dark:text-neutral-300">
                  {bgLastLog}
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <button
                  onClick={() =>
                    simulateBackgroundLocationTick('small_move_30m')
                  }
                  className="p-3.5 rounded-xl border border-neutral-300 dark:border-neutral-700 hover:bg-neutral-100 dark:hover:bg-neutral-800 text-left transition-colors cursor-pointer"
                >
                  <div className="text-xs font-bold">1. Move ~25m (2 min)</div>
                  <div className="text-[11px] text-neutral-500 mt-1">
                    Below 75m threshold → Skips network call
                  </div>
                </button>

                <button
                  onClick={() => simulateBackgroundLocationTick('moving_110m')}
                  className="p-3.5 rounded-xl border border-neutral-300 dark:border-neutral-700 hover:bg-neutral-100 dark:hover:bg-neutral-800 text-left transition-colors cursor-pointer"
                >
                  <div className="text-xs font-bold">2. Move ~115m (2 min)</div>
                  <div className="text-[11px] text-neutral-500 mt-1">
                    Exceeds 75m → Upserts without updated_at
                  </div>
                </button>

                <button
                  onClick={() =>
                    simulateBackgroundLocationTick('stationary_20min')
                  }
                  className="p-3.5 rounded-xl border border-neutral-300 dark:border-neutral-700 hover:bg-neutral-100 dark:hover:bg-neutral-800 text-left transition-colors cursor-pointer"
                >
                  <div className="text-xs font-bold">
                    3. Stationary (20 min)
                  </div>
                  <div className="text-[11px] text-neutral-500 mt-1">
                    Heartbeat → Server refreshes updated_at
                  </div>
                </button>
              </div>

              <div className="flex items-center justify-between p-3.5 rounded-xl border border-neutral-200 dark:border-neutral-800">
                <div className="text-xs">
                  <span className="font-semibold">Offline Queue Mode: </span>
                  <span className="text-neutral-500">
                    {bgOfflineMode
                      ? 'Device is OFFLINE (queues latest fix locally)'
                      : 'Device is ONLINE (flushes immediately)'}
                  </span>
                </div>
                <button
                  onClick={toggleOfflineMode}
                  className="px-3 py-1.5 rounded-lg border border-neutral-300 dark:border-neutral-700 text-xs font-medium flex items-center gap-1.5 cursor-pointer"
                >
                  {bgOfflineMode ? (
                    <>
                      <WifiOff className="w-3.5 h-3.5" />
                      <span>Go Online &amp; Flush</span>
                    </>
                  ) : (
                    <>
                      <Wifi className="w-3.5 h-3.5" />
                      <span>Simulate Offline</span>
                    </>
                  )}
                </button>
              </div>
            </div>
          )}

          {inspectorTab === 'config' && (
            <div className="space-y-4 text-xs">
              <div className="p-4 rounded-xl border border-neutral-200 dark:border-neutral-800 bg-neutral-50 dark:bg-neutral-900/50 space-y-2">
                <div className="font-semibold">
                  Compile-Time Environment Configuration (No Hard-Coded Keys in Dart)
                </div>
                <p className="text-neutral-600 dark:text-neutral-400 leading-relaxed">
                  <code className="font-mono">config/env.json</code> is created
                  with your project URL and publishable key and added to{' '}
                  <code className="font-mono">.gitignore</code>.{' '}
                  <code className="font-mono">lib/config/app_config.dart</code>{' '}
                  reads them via{' '}
                  <code className="font-mono">
                    String.fromEnvironment(&apos;SUPABASE_URL&apos;)
                  </code>{' '}
                  and{' '}
                  <code className="font-mono">
                    String.fromEnvironment(&apos;SUPABASE_ANON_KEY&apos;)
                  </code>
                  .
                </p>
              </div>

              <div className="p-4 rounded-xl bg-neutral-950 text-neutral-100 font-mono space-y-1.5 overflow-x-auto">
                <div className="text-neutral-400">
                  # Run &amp; Build Commands:
                </div>
                <div>flutter run --dart-define-from-file=config/env.json</div>
                <div>
                  flutter build apk --dart-define-from-file=config/env.json
                </div>
                <div>
                  flutter build ios --dart-define-from-file=config/env.json
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Updated Source File Shortcuts */}
        <div className="p-6 rounded-2xl border border-neutral-200 dark:border-neutral-800 bg-white dark:bg-neutral-900/40 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-bold">
              Updated Flutter &amp; Config Files (Click to Inspect)
            </h3>
            <span className="text-xs font-mono text-neutral-500">
              19 files ready
            </span>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
            {[
              ['app-config', 'flutter_app/lib/config/app_config.dart'],
              [
                'supabase-service',
                'flutter_app/lib/services/supabase_service.dart',
              ],
              ['app-providers', 'flutter_app/lib/providers/app_providers.dart'],
              ['login-screen', 'flutter_app/lib/screens/login_screen.dart'],
              ['main-dart', 'flutter_app/lib/main.dart'],
              ['setup-guide', 'SETUP_GUIDE.md'],
              ['env-example-json', 'config/env.example.json'],
              ['vscode-launch', 'flutter_app/.vscode/launch.json'],
            ].map(([id, path]) => (
              <button
                key={id}
                onClick={() => onSelectDeliverable(id)}
                className="p-3 rounded-xl border border-neutral-200 dark:border-neutral-800 hover:border-neutral-900 dark:hover:border-white text-left font-mono text-xs truncate transition-colors cursor-pointer"
              >
                {path}
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};
