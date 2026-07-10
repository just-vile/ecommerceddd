import { Injectable, inject } from '@angular/core';
import * as signalR from '@microsoft/signalr';
import { RuntimeConfigService } from './runtime-config.service';

@Injectable({
  providedIn: 'root',
})
export class SignalrService {
  private readonly runtimeConfig = inject(RuntimeConfigService);
  connection!: signalR.HubConnection;
  constructor() {
    this.connection = this.buildConnection(this.runtimeConfig.signalRHubUrl);
  }

  // Start Hub Connection and Register events
  private buildConnection = (hubUrl: string) => {
    return (
      new signalR.HubConnectionBuilder()
        //.configureLogging(signalR.LogLevel.Trace)
        .withUrl(hubUrl)
        .build()
    );
  };
}
