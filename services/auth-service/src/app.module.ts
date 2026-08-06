import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { AuthModule } from './auth/auth.module';
import { AuthConfig, loadConfiguration } from './config/configuration';
import { DatabaseModule } from './database/database.module';
import { TokensModule } from './tokens/tokens.module';
import { UsersModule } from './users/users.module';

/**
 * The composition root.
 *
 * Four feature modules with one direction of dependency: auth depends on users
 * and tokens, both depend on database, and nothing depends on auth. A dependency
 * pointing the other way, users reaching into auth for a token, is the first
 * step towards a service where every file imports every other file.
 */
@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      load: [loadConfiguration],
      // .env is read in development. In a container the values come from the
      // environment, and no .env file is copied into the image.
      envFilePath: ['.env'],
    }),
    ThrottlerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService<AuthConfig, true>) => {
        const login = config.get('login', { infer: true });
        return {
          throttlers: [{ name: 'login', ttl: login.throttleTtlSeconds * 1000, limit: login.throttleLimit }],
        };
      },
    }),
    DatabaseModule,
    UsersModule,
    TokensModule,
    AuthModule,
  ],
})
export class AppModule {}
