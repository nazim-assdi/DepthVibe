import type {
  DepthVibeAdobeHost,
  DepthVibeBridgeClient,
  DepthVibeCompositionDocument,
  DepthVibeEffectDescriptor,
  DepthVibePairingResponse,
  DepthVibeAdobeHostSnapshot,
} from "./depthvibe-bridge";

export class DepthVibeBridgeError extends Error {
  constructor(
    message: string,
    readonly statusCode: number,
  ) {
    super(message);
    this.name = "DepthVibeBridgeError";
  }
}

/**
 * Minimal browser/UXP client for the authenticated localhost bridge.
 * The caller owns the pairing code and decides when to import/export documents.
 */
export class LocalDepthVibeBridgeClient implements DepthVibeBridgeClient {
  private token: string | null = null;
  private sessionId: string | null = null;

  constructor(private readonly baseUrl: string) {
    const url = new URL(baseUrl);
    if (
      !["http:", "https:"].includes(url.protocol) ||
      url.hostname !== "127.0.0.1" ||
      url.port !== "47653" ||
      url.username ||
      url.password ||
      (url.pathname !== "/" && url.pathname !== "")
    ) {
      throw new Error("Bridge URL must be the DepthVibe loopback endpoint.");
    }
  }

  async pair(
    code: string,
    hostApp: DepthVibeAdobeHost,
    hostVersion: string,
  ): Promise<DepthVibePairingResponse> {
    if (!/^\d{6}$/.test(code)) {
      throw new Error("Enter the six-digit pairing code from DepthVibe.");
    }
    const result = await this.request<DepthVibePairingResponse>(
      "/v1/pair",
      {
        method: "POST",
        body: JSON.stringify({ code, hostApp, hostVersion }),
      },
      false,
    );
    this.token = result.token;
    this.sessionId = result.sessionId;
    return result;
  }

  async getComposition(): Promise<DepthVibeCompositionDocument> {
    const result = await this.request<{ document: DepthVibeCompositionDocument }>(
      "/v1/composition",
    );
    return result.document;
  }

  async getEffects(): Promise<DepthVibeEffectDescriptor[]> {
    const result = await this.request<{ effects: DepthVibeEffectDescriptor[] }>(
      "/v1/effects",
    );
    return result.effects;
  }

  async getAdobeMetadata(): Promise<DepthVibeAdobeHostSnapshot> {
    const result = await this.request<{ snapshot: DepthVibeAdobeHostSnapshot }>(
      "/v1/adobe/metadata",
    );
    return result.snapshot;
  }

  async sendAdobeMetadata(
    snapshot: DepthVibeAdobeHostSnapshot,
  ): Promise<{
    ok: true;
    message: string;
    hostApp: DepthVibeAdobeHost;
    payloadKeys: number;
  }> {
    return this.request("/v1/adobe/metadata", {
      method: "POST",
      body: JSON.stringify({ snapshot }),
    });
  }

  async sendComposition(
    document: DepthVibeCompositionDocument,
  ): Promise<{ ok: true; importedLayers: number }> {
    return this.request("/v1/composition", {
      method: "POST",
      body: JSON.stringify({ document }),
    });
  }

  async disconnect(): Promise<void> {
    try {
      await this.request("/v1/disconnect", { method: "POST" });
    } finally {
      this.token = null;
      this.sessionId = null;
    }
  }

  get isConnected(): boolean {
    return this.token !== null && this.sessionId !== null;
  }

  private async request<T>(
    path: string,
    options: RequestInit = {},
    authenticated = true,
  ): Promise<T> {
    if (authenticated && !this.token) {
      throw new Error("Connect this Adobe panel to DepthVibe first.");
    }
    const headers = new Headers(options.headers);
    headers.set("Content-Type", "application/json");
    if (authenticated && this.token) {
      headers.set("Authorization", "Bearer " + this.token);
    }
    const response = await fetch(this.baseUrl + path, {
      ...options,
      headers,
      cache: "no-store",
    });
    let result: Record<string, unknown>;
    try {
      result = await response.json() as Record<string, unknown>;
    } catch {
      throw new DepthVibeBridgeError(
        "DepthVibe Bridge returned an invalid response.",
        response.status,
      );
    }
    if (!response.ok) {
      throw new DepthVibeBridgeError(
        String(result.error ?? ("Bridge HTTP " + response.status)),
        response.status,
      );
    }
    return result as T;
  }
}
