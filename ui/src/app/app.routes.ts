import { Routes } from '@angular/router';

import { authGuard } from './core/guards/auth-guard';

/**
 * Four screens. Every one except sign-in is behind `authGuard`.
 *
 * Each screen is loaded with `loadComponent`, so the sign-in bundle does not carry the
 * dashboard, the order ticket and the blotter with it. That matters on a Sprint 11 deployment
 * where the first paint comes over a CDN to a browser that has cached nothing.
 */
export const routes: Routes = [
  { path: '', pathMatch: 'full', redirectTo: 'dashboard' },
  {
    path: 'login',
    title: 'Sign in',
    loadComponent: () => import('./features/login/login').then((m) => m.Login),
  },
  {
    path: 'dashboard',
    title: 'Dashboard',
    canActivate: [authGuard],
    loadComponent: () => import('./features/dashboard/dashboard').then((m) => m.Dashboard),
  },
  {
    path: 'orders/new',
    title: 'Order ticket',
    canActivate: [authGuard],
    loadComponent: () => import('./features/order-ticket/order-ticket').then((m) => m.OrderTicket),
  },
  {
    path: 'orders',
    title: 'Order history',
    canActivate: [authGuard],
    loadComponent: () => import('./features/blotter/blotter').then((m) => m.Blotter),
  },
  { path: '**', redirectTo: 'dashboard' },
];
