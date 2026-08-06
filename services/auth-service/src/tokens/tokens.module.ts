import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { RefreshTokenRepository } from './refresh-token.repository';
import { TokenService } from './token.service';

/**
 * The token layer, separate from the auth layer on purpose.
 *
 * Signing, verification and refresh-token storage have nothing to do with
 * credentials, and keeping them apart is what makes the move from HS256 to
 * RS256 a change to one module rather than a change to the login flow.
 *
 * JwtModule is registered with no secret. Every call passes the secret and the
 * algorithm explicitly, so a token can never be signed with a default that
 * somebody forgot to configure.
 */
@Module({
  imports: [JwtModule.register({})],
  providers: [TokenService, RefreshTokenRepository],
  exports: [TokenService],
})
export class TokensModule {}
