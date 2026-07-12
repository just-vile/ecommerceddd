import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideToastr } from 'ngx-toastr';
import { AppComponent } from './app.component';
import { RuntimeConfigService } from './core/services/runtime-config.service';
 
const runtimeConfigServiceMock = {
  apiBaseUrl: 'http://localhost',
  identityUrl: 'http://localhost/identity',
  signalRHubUrl: 'http://localhost/signalr',
  load: () => Promise.resolve(),
};
 
describe('AppComponent', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [AppComponent],
      providers: [
        provideRouter([]),
        provideToastr(),
        { provide: RuntimeConfigService, useValue: runtimeConfigServiceMock },
      ],
    }).compileComponents();
  });
 
  it('should create the app', () => {
    const fixture = TestBed.createComponent(AppComponent);
    const app = fixture.componentInstance;
    expect(app).toBeTruthy();
  });
});
 
 