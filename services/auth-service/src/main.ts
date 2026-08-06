import { Logger, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { AuthExceptionFilter } from './common/errors/auth-exception.filter';
import { InvalidInputException } from './common/errors/auth.exceptions';
import { JsonLogger } from './common/logging/json.logger';
import { AuthConfig } from './config/configuration';

/**
 * Process entry point.
 *
 * Everything global to the service is set up here, in one place, so that a
 * reviewer can answer "is validation on, and does it reject unknown fields"
 * without reading twenty controllers.
 */
async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { logger: new JsonLogger() });
  const config = app.get<ConfigService<AuthConfig, true>>(ConfigService);

  app.useGlobalPipes(
    new ValidationPipe({
      // Strips properties with no decorator, then rejects the request if any
      // were present. That is the contract's additionalProperties: false, and it
      // is what stops a client smuggling a `roles` field into a route that later
      // starts trusting the body.
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: false },
      // Validation failures are VAL-422 with a fixed message. The default
      // response lists every field that failed, which on a login route is a
      // free description of the credential format.
      exceptionFactory: () => new InvalidInputException(),
    }),
  );

  app.useGlobalFilters(new AuthExceptionFilter());
  app.enableShutdownHooks();

  // The Angular dev server calls this service directly from the browser.
  // Production fronts both with one origin, so the allow-list is configuration.
  app.enableCors({
    origin: process.env.CORS_ORIGINS?.split(',') ?? ['http://localhost:4200'],
    methods: ['GET', 'POST'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  });

  // Swagger is generated from the decorators on the controller and the DTOs, so
  // the published document cannot drift from the code the way a hand-written
  // YAML file does. It is checked against contracts/auth-api.yaml, which stays
  // the source of truth for the two implementations.
  const document = SwaggerModule.createDocument(
    app,
    new DocumentBuilder()
      .setTitle('Auth service')
      .setVersion('1.0.0')
      .setDescription(
        'Registration, login, token refresh and current-user lookup for the Enterprise Trading Platform. Implements contracts/auth-api.yaml. Tokens are HS256, signed with JWT_SECRET, and carry sub, accountId, roles, iat, exp and iss.',
      )
      .addBearerAuth({ type: 'http', scheme: 'bearer', bearerFormat: 'JWT' }, 'bearerAuth')
      .addTag('Auth', 'Registration, login and token lifecycle.')
      .addTag('Profile', 'The authenticated user.')
      .addServer('http://localhost:3000', 'Local development.')
      .addServer('http://auth-service:3000', 'Service name inside the Docker Compose network.')
      .build(),
  );
  SwaggerModule.setup('docs', app, document, { jsonDocumentUrl: 'docs/json' });

  const port = config.get('port', { infer: true });
  await app.listen(port, '0.0.0.0');

  new Logger('bootstrap').log('auth service listening', {
    event: 'service.started',
    port,
    docs: `http://localhost:${port}/docs`,
  });
}

void bootstrap();
