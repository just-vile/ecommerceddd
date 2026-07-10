import { Injectable } from '@angular/core';

export interface RuntimeConfig {
  apiBaseUrl: string;
  identityUrl: string;
  signalRHubUrl: string;
}

@Injectable({
  providedIn: 'root',
})
export class RuntimeConfigService {
  private config!: RuntimeConfig;

  async load(): Promise<void> {
    const response = await fetch('/assets/config.json');
    if (!response.ok) {
      throw new Error(`Failed to load runtime config: ${response.status}`);
    }
    this.config = await response.json();
  }

  get apiBaseUrl(): string {
    return this.config.apiBaseUrl;
  }

  get identityUrl(): string {
    return this.config.identityUrl;
  }

  get signalRHubUrl(): string {
    return this.config.signalRHubUrl;
  }
}
