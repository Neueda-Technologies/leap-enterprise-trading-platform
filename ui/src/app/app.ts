import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';

/** The shell. Every screen renders its own header, so this holds the outlet and nothing else. */
@Component({
  selector: 'app-root',
  imports: [RouterOutlet],
  templateUrl: './app.html',
})
export class App {}
