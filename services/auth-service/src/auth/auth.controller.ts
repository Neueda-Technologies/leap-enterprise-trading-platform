import { Body, Controller, Get, HttpCode, HttpStatus, Post, UseGuards } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiBody,
  ApiOkResponse,
  ApiCreatedResponse,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { ThrottlerGuard } from '@nestjs/throttler';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ErrorResponseDto } from '../common/errors/error-response.dto';
import { AuthenticatedUser } from '../users/user.entity';
import { RegisterDto } from '../users/dto/register.dto';
import { UserResponseDto } from '../users/dto/user-response.dto';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { RefreshDto } from './dto/refresh.dto';
import { TokenResponseDto } from './dto/token-response.dto';
import { JwtAuthGuard } from './guards/jwt-auth.guard';

/**
 * The four routes of `contracts/auth-api.yaml`.
 *
 * The controller does three things and no more: it takes a validated DTO, it
 * calls one service method, and it maps the result to a response DTO. No hashing,
 * no SQL, no token handling. Anything else in here is in the wrong layer.
 *
 * The Swagger decorators are what generate `/docs`. Keeping them accurate is
 * part of the deliverable, because the Angular team generates its client from
 * the contract and a documented response that the service does not return costs
 * somebody a morning.
 */
@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({
    summary: 'Register a user',
    description:
      'Creates a user and links it to an existing trading account. It does not create the trading account. Registration returns no tokens: the client logs in afterwards, so that the unauthenticated route cannot mint a session.',
  })
  @ApiBody({ type: RegisterDto })
  @ApiCreatedResponse({ description: 'User created.', type: UserResponseDto })
  @ApiResponse({ status: 409, description: 'The username is already taken.', type: ErrorResponseDto })
  @ApiResponse({ status: 422, description: 'The request failed field validation.', type: ErrorResponseDto })
  async register(@Body() dto: RegisterDto): Promise<UserResponseDto> {
    return UserResponseDto.from(await this.auth.register(dto));
  }

  /**
   * Rate limited, unlike the other routes.
   *
   * Five attempts a minute per address, set by LOGIN_THROTTLE_LIMIT and
   * LOGIN_THROTTLE_TTL_SECONDS. That does not inconvenience a person who
   * mistyped a password and does stop an unattended script working through a
   * password list. It is a blunt control: an attacker with many addresses is
   * unaffected, which is why it sits alongside argon2 rather than instead of it.
   *
   * The guard is applied to this route only. A global throttler would also cap
   * `/auth/me`, which the UI calls on every page load.
   */
  @Post('login')
  @HttpCode(HttpStatus.OK)
  @UseGuards(ThrottlerGuard)
  @ApiOperation({
    summary: 'Log in and receive tokens',
    description:
      'Verifies the credentials and issues an access token and a refresh token. Every failure, whatever its cause, returns the same AUTH-401 body. Throttled: repeated failures from one address return 429.',
  })
  @ApiBody({ type: LoginDto })
  @ApiOkResponse({ description: 'Authenticated.', type: TokenResponseDto })
  @ApiResponse({ status: 401, description: 'Authentication failed.', type: ErrorResponseDto })
  @ApiResponse({ status: 422, description: 'The request failed field validation.', type: ErrorResponseDto })
  @ApiResponse({ status: 429, description: 'Too many login attempts.', type: ErrorResponseDto })
  async login(@Body() dto: LoginDto): Promise<TokenResponseDto> {
    return this.auth.login(dto);
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Exchange a refresh token for a new token pair',
    description:
      'Consumes the presented refresh token and issues a new pair. The presented token stops working immediately. Presenting a consumed token is treated as theft: every refresh token for that user is revoked and the response is AUTH-401.',
  })
  @ApiBody({ type: RefreshDto })
  @ApiOkResponse({ description: 'A new token pair.', type: TokenResponseDto })
  @ApiResponse({ status: 401, description: 'Authentication failed.', type: ErrorResponseDto })
  @ApiResponse({ status: 422, description: 'The request failed field validation.', type: ErrorResponseDto })
  async refresh(@Body() dto: RefreshDto): Promise<TokenResponseDto> {
    return this.auth.refresh(dto);
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('bearerAuth')
  @ApiTags('Profile')
  @ApiOperation({
    summary: 'Get the authenticated user',
    description:
      'Returns the user identified by the access token. The identity comes from the verified token, never from a query parameter or a header the client controls.',
  })
  @ApiOkResponse({ description: 'The authenticated user.', type: UserResponseDto })
  @ApiResponse({ status: 401, description: 'Authentication failed.', type: ErrorResponseDto })
  async me(@CurrentUser() user: AuthenticatedUser): Promise<UserResponseDto> {
    return UserResponseDto.from(await this.auth.currentUser(user.id));
  }
}
