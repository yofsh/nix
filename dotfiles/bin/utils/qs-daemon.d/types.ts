export interface DaemonContext {
  hyprIPC: HyprIPCBus;
  runtimeDir: string;
  signal: AbortSignal;
}

export interface DaemonModule {
  name: string;
  init(ctx: DaemonContext): Promise<void> | void;
  routes: Record<string, (req: Request) => Response | Promise<Response>>;
  shutdown?(): Promise<void> | void;
}

export interface HyprIPCBus {
  on(event: string, handler: (data: string) => void): void;
  off(event: string, handler: (data: string) => void): void;
  once(event: string, handler: (data: string) => void): void;
}
