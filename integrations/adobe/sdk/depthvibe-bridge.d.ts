export type DepthVibeAdobeHost =
  | "premierepro"
  | "aftereffects"
  | "aftereffects-beta";

export interface DepthVibePairingResponse {
  ok: true;
  sessionId: string;
  token: string;
  hostApp: DepthVibeAdobeHost;
  bridgeVersion: 1;
}

export interface DepthVibeEffectParameter {
  id: string;
  label: string;
  min: number;
  max: number;
  defaultValue: number;
}

export interface DepthVibeEffectDescriptor {
  id: string;
  name: string;
  category: string;
  description: string;
  parameters: DepthVibeEffectParameter[];
}

export interface DepthVibeCompositionDocument {
  name: string;
  width: number;
  height: number;
  frameRate: number;
  durationMs: number;
  layers: Array<Record<string, unknown>>;
  transitions: Array<Record<string, unknown>>;
  audioBuses: Array<Record<string, unknown>>;
}

export interface DepthVibeBridgeClient {
  pair(code: string, hostApp: DepthVibeAdobeHost, hostVersion: string):
    Promise<DepthVibePairingResponse>;
  getComposition(): Promise<DepthVibeCompositionDocument>;
  getEffects(): Promise<DepthVibeEffectDescriptor[]>;
  sendComposition(document: DepthVibeCompositionDocument):
    Promise<{ ok: true; importedLayers: number }>;
  disconnect(): Promise<void>;
}

/**
 * Bridge endpoints:
 * GET /v1/health
 * POST /v1/pair
 * GET /v1/session
 * GET /v1/effects
 * GET /v1/composition
 * POST /v1/composition
 * POST /v1/disconnect
 *
 * Always obtain the pairing code from the user. Never embed pairing codes or
 * bearer tokens in plugin packages.
 */
