import type {
  DepthVibeAdobeHost,
  DepthVibeCompositionDocument,
  DepthVibeEffectDescriptor,
} from "./depthvibe-bridge";

/** A normalized snapshot produced by a host-specific Adobe DOM adapter. */
export interface AdobeHostTimelineSnapshot {
  host: DepthVibeAdobeHost;
  hostVersion: string;
  frameRate: number;
  width: number;
  height: number;
  durationFrames: number;
  tracks: AdobeHostTrackSnapshot[];
}

export interface AdobeHostTrackSnapshot {
  id: string;
  name: string;
  kind: "video" | "audio" | "graphics" | "adjustment";
  clips: AdobeHostClipSnapshot[];
}

export interface AdobeHostClipSnapshot {
  id: string;
  name: string;
  startFrame: number;
  durationFrames: number;
  sourceInFrame: number;
  sourcePath?: string;
  enabled: boolean;
  effects: AdobeHostEffectSnapshot[];
}

export interface AdobeHostEffectSnapshot {
  matchName: string;
  displayName: string;
  parameters: Record<string, number | string | boolean>;
}

export interface AdobeHostAdapter {
  readonly host: DepthVibeAdobeHost;
  getHostVersion(): Promise<string>;
  readActiveTimeline(): Promise<AdobeHostTimelineSnapshot>;
  readDepthVibeEffectCatalog(): Promise<DepthVibeEffectDescriptor[]>;
  translateToDepthVibe(
    snapshot: AdobeHostTimelineSnapshot,
  ): Promise<DepthVibeCompositionDocument>;
  translateFromDepthVibe(
    document: DepthVibeCompositionDocument,
  ): Promise<{ warnings: string[]; unsupportedEffects: string[] }>;
}

/**
 * Every host translator must declare lossy mappings and unsupported effects.
 * Do not silently claim parity between Premiere/After Effects and DepthVibe.
 */
