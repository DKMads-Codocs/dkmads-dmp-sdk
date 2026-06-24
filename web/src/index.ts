import type { Consent, InitConfig } from '@dkmads/shared';
import {
  createClientState,
  resolveBridge,
  sendBatch,
  sendConsent,
  syncOptOutToServer,
  applyServerOptOut,
  applyPersistedOptOut,
  persistOptOut,
  canCollect,
  shouldCollectIdentifier,
  buildMatchIdentifiersFromTraits,
  mergeIdentifiers,
  OPT_OUT_STORAGE_KEY,
  DMP_DEVICE_PID_STORAGE_KEY,
  type DMPClientState,
  type OptOutStorage,
  type MatchIdentifier,
  type SharedIdentity,
} from '@dkmads/sdk-core';

const COOKIE_KEY = 'dkmads_dmp_id';
const DEVICE_PID_KEY = DMP_DEVICE_PID_STORAGE_KEY;

const webOptOutStorage: OptOutStorage = {
  load() {
    try {
      return localStorage.getItem(OPT_OUT_STORAGE_KEY) === '1';
    } catch {
      return false;
    }
  },
  save(optedOut: boolean) {
    try {
      if (optedOut) localStorage.setItem(OPT_OUT_STORAGE_KEY, '1');
      else localStorage.removeItem(OPT_OUT_STORAGE_KEY);
    } catch {
      /* ignore */
    }
  },
};

function getOrCreateCookieId(): string {
  try {
    const match = document.cookie.match(new RegExp(`(?:^|; )${COOKIE_KEY}=([^;]*)`));
    if (match?.[1]) return match[1];
    const id = crypto.randomUUID();
    document.cookie = `${COOKIE_KEY}=${id}; path=/; max-age=31536000; SameSite=Lax`;
    return id;
  } catch {
    return crypto.randomUUID();
  }
}

function getOrCreateDevicePid(): string {
  try {
    const existing = localStorage.getItem(DEVICE_PID_KEY);
    if (existing) return existing;
    const id = `dkmads_${crypto.randomUUID()}`;
    localStorage.setItem(DEVICE_PID_KEY, id);
    return id;
  } catch {
    return `dkmads_${crypto.randomUUID()}`;
  }
}

function detectBrowser(): string {
  const ua = navigator.userAgent;
  if (ua.includes('Firefox/')) return 'firefox';
  if (ua.includes('Edg/')) return 'edge';
  if (ua.includes('Chrome/')) return 'chrome';
  if (ua.includes('Safari/') && !ua.includes('Chrome')) return 'safari';
  return 'other';
}

async function collectFingerprint(): Promise<string> {
  const parts = [
    navigator.userAgent,
    screen.width,
    screen.height,
    screen.colorDepth,
    navigator.language,
    new Date().getTimezoneOffset(),
  ];
  const data = new TextEncoder().encode(parts.join('|'));
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

class DMPClient {
  private state: DMPClientState;
  private initialized = false;
  private devicePid = '';

  constructor() {
    this.state = createClientState({ appKey: '' });
  }

  async init(config: InitConfig): Promise<void> {
    this.state = createClientState(config);
    if (config.workspaceId) this.state.workspaceId = config.workspaceId;
    if (config.propertyId) this.state.propertyId = config.propertyId;

    applyPersistedOptOut(this.state, webOptOutStorage);
    this.devicePid = getOrCreateDevicePid();

    if (!this.state.workspaceId || !this.state.propertyId) {
      await resolveBridge(this.state);
    }

    await applyServerOptOut(this.state, this.devicePid);

    const flushMs = config.flushIntervalMs ?? 10_000;
    this.state.flushTimer = setInterval(() => void this.flush(), flushMs);
    this.initialized = true;

    this.track('sdk_initialized', { platform: 'web' });
  }

  identify(userId: string, traits?: Record<string, unknown>): void {
    if (!canCollect(this.state)) return;
    this.state.userId = userId;
    if (traits) Object.assign(this.state.traits, traits);
    void this.enqueue('identify', { userId, ...traits });
  }

  track(event: string, properties?: Record<string, unknown>): void {
    if (!this.initialized || !canCollect(this.state)) return;
    void this.enqueue(event, properties);
  }

  setTrait(key: string, value: unknown): void {
    if (!canCollect(this.state)) return;
    this.state.traits[key] = value;
    void this.enqueue('$trait_update', { [key]: value });
  }

  setTraits(traits: Record<string, unknown>): void {
    Object.entries(traits).forEach(([k, v]) => this.setTrait(k, v));
  }

  setContext(context: Record<string, unknown>): void {
    Object.assign(this.state.context, context);
  }

  async setConsent(consent: Consent): Promise<void> {
    this.state.consent = { ...consent, devicePid: this.devicePid || getOrCreateDevicePid() };
    await sendConsent(this.state, this.state.consent);
  }

  optOut(): void {
    this.state.optedOut = true;
    persistOptOut(this.state, webOptOutStorage);
    void syncOptOutToServer(this.state, this.devicePid || getOrCreateDevicePid());
    this.reset();
  }

  reset(): void {
    this.state.userId = undefined;
    this.state.traits = {};
    this.state.queue = [];
  }

  async flush(): Promise<void> {
    const events = this.state.queue.splice(0, this.state.batchSize);
    if (events.length === 0) return;
    await sendBatch(this.state, events);
  }

  getDevicePid(): string {
    return this.devicePid || getOrCreateDevicePid();
  }

  getUserPid(): string | null {
    return this.state.userId ?? null;
  }

  getSharedIdentity(): SharedIdentity {
    return {
      devicePid: this.getDevicePid(),
      userPid: this.getUserPid(),
    };
  }

  private async buildIdentifiers(): Promise<MatchIdentifier[]> {
    const identifiers: MatchIdentifier[] = [
      { type: 'dmp_cookie', value: getOrCreateCookieId() },
      { type: 'device_pid', value: this.devicePid || getOrCreateDevicePid() },
    ];

    if (shouldCollectIdentifier('fingerprint_hash', this.state)) {
      const fingerprint = await collectFingerprint();
      identifiers.push({ type: 'fingerprint_hash', value: fingerprint });
    }

    if (this.state.userId) {
      identifiers.push({ type: 'publisher_user_id', value: this.state.userId });
      identifiers.push({ type: 'user_pid', value: this.state.userId });
    }

    const matchIds = await buildMatchIdentifiersFromTraits(this.state.traits);
    return mergeIdentifiers(identifiers, matchIds);
  }

  private async enqueue(eventName: string, properties?: Record<string, unknown>): Promise<void> {
    if (!canCollect(this.state)) return;

    const identifiers = await this.buildIdentifiers();
    const eventTraits = { ...this.state.traits, ...(properties ?? {}) };
    const matchFromEvent = await buildMatchIdentifiersFromTraits(eventTraits);

    this.state.queue.push({
      eventName,
      timestamp: new Date().toISOString(),
      identifiers: mergeIdentifiers(identifiers, matchFromEvent),
      traits: Object.keys(this.state.traits).length > 0 ? { ...this.state.traits } : undefined,
      properties,
      context: {
        ...this.state.context,
        url: location.href,
        referrer: document.referrer,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        locale: navigator.language,
        browser: detectBrowser(),
        platform: 'web',
      },
    });

    if (this.state.queue.length >= this.state.batchSize) await this.flush();
  }
}

const client = new DMPClient();

export const DMP = {
  init: (config: InitConfig) => client.init(config),
  identify: (userId: string, traits?: Record<string, unknown>) => client.identify(userId, traits),
  track: (event: string, properties?: Record<string, unknown>) => client.track(event, properties),
  setTrait: (key: string, value: unknown) => client.setTrait(key, value),
  setTraits: (traits: Record<string, unknown>) => client.setTraits(traits),
  setContext: (context: Record<string, unknown>) => client.setContext(context),
  setConsent: (consent: Consent) => client.setConsent(consent),
  optOut: () => client.optOut(),
  reset: () => client.reset(),
  flush: () => client.flush(),
  getDevicePid: () => client.getDevicePid(),
  getUserPid: () => client.getUserPid(),
  getSharedIdentity: () => client.getSharedIdentity(),
};

export default DMP;

export {
  STANDARD_AGE_RANGES,
  STANDARD_GENDER_VALUES,
  ageFromDateOfBirth,
  ageRangeFromAge,
  ageRangeFromDateOfBirth,
  normalizeAgeRange,
  normalizeGender,
  DMP_DEVICE_PID_STORAGE_KEY,
  type StandardAgeRange,
  type StandardGender,
  type SharedIdentity,
} from '@dkmads/sdk-core';
