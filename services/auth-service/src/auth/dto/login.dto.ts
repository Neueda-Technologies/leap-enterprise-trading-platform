import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength, MinLength } from 'class-validator';

/**
 * `POST /auth/login` body.
 *
 * No minimum length and no pattern on either field. The registration rules
 * belong on registration; enforcing them here would reject a login for a user
 * created before the rules changed, and would tell a caller which of the two
 * fields failed the rule.
 */
export class LoginDto {
  @ApiProperty({ maxLength: 64, example: 'demo1' })
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  username!: string;

  @ApiProperty({ maxLength: 128, writeOnly: true, example: 'Trainee#2026' })
  @IsString()
  @MinLength(1)
  @MaxLength(128)
  password!: string;
}
