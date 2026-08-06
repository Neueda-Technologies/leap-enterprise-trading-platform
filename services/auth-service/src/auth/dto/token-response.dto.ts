import { ApiProperty } from '@nestjs/swagger';

/** The body returned by `POST /auth/login` and `POST /auth/refresh`. */
export class TokenResponseDto {
  @ApiProperty({
    description: 'Signed JWT carrying the claims contract: `sub`, `accountId`, `roles`, `iat`, `exp`, `iss`.',
    example:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4ZjE0ZTQ1Zi1jZWVhLTRjMWItOWQzYi0xYTJiM2M0ZDVlNmYifQ.signature',
  })
  accessToken!: string;

  @ApiProperty({
    description: 'Opaque, stored server-side, revocable, rotated on every use.',
    example: '9c1f7a2e4b6d8e0a2c4e6a8c0e2a4c6e8a0c2e4a6c8e0a2c',
  })
  refreshToken!: string;

  @ApiProperty({ enum: ['Bearer'], example: 'Bearer' })
  tokenType!: 'Bearer';

  @ApiProperty({ description: 'Access token lifetime in seconds.', example: 900 })
  expiresIn!: number;
}
