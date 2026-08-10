import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { Component, provideBrowserGlobalErrorListeners } from '@angular/core';
import { bootstrapApplication } from '@angular/platform-browser';
import { provideRouter, RouterOutlet } from '@angular/router';

/*
 * The bootstrap, and nothing else.
 *
 * This file exists so that `npm run build` succeeds on a fresh clone and you have a running
 * shell to hang your first screen on. It is not the shape of the finished application.
 *
 * Replace the placeholder below with a real root component in `src/app/`, move the provider
 * list into an `ApplicationConfig` of its own, declare your routes in a routes file and
 * register your interceptor in `withInterceptors`. Every directory under `src/app/` carries
 * a README saying what belongs in it.
 *
 * There are no NgModules in this workspace and none are wanted. Standalone components and
 * signals are the house approach for the whole platform.
 */

@Component({
  selector: 'app-root',
  template: `
    <main>
      <h1>Enterprise Trading Platform</h1>
      <p>Sprint 9 scaffold. Nothing is implemented yet.</p>
      <router-outlet />
    </main>
  `,
  imports: [RouterOutlet],
})
export class AppShell {}

bootstrapApplication(AppShell, {
  providers: [
    provideBrowserGlobalErrorListeners(),

    // No routes yet. The guarded routes and the one unguarded route are yours to declare.
    provideRouter([]),

    // No interceptors yet. The bearer token is attached in exactly one place, and this is
    // where that place is registered.
    provideHttpClient(withInterceptors([])),
  ],
}).catch((error: unknown) => console.error(error));
