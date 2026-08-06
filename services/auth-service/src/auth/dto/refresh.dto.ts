import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength, MinLength } from 'class-validator';

/** `POST /auth/refresh` body. The token issued by the previous login or refresh. */
export class RefreshDto {
  @ApiProperty({
    description: 'The refresh token issued by the previous login or refresh. Opaque to the client.',
    example: '9c1f7a2e4b6d8e0a2c4e6a8c0e2a4c6e8a0c2e4a6c8e0a2c',
  })
  @IsString()
  @MinLength(1)
  @MaxLength(512)
  refreshToken!: string;
}
