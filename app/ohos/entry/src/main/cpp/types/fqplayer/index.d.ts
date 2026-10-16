export interface PlayerEvent { what: number; a: number; b: number; }
export interface PlayerState {
  events: PlayerEvent[];
  position: number;
  duration: number;
  playing: boolean;
}
export const create: (url: string) => number;
export const poll: (id: number) => PlayerState;
export const setSurface: (id: number, surfaceId: string) => number;
export const command: (id: number, name: string, value: number) => number;
export const release: (id: number) => Promise<void>;
