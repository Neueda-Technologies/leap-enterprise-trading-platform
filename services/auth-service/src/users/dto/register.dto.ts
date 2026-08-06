import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsEnum, IsInt, IsOptional, IsString, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';
import { Role } from '../role.enum';

/**
 * `POST /auth/register` body, validated by class-validator before the
 * controller sees it.
 *
 * The rules mirror `contracts/auth-api.yaml` exactly. Validation that is looser
 * than the contract means the service accepts requests the UI's generated client
 * will never send, and those are the requests an attacker sends.
 */
export class RegisterDto {
  @ApiProperty({
    description: 'Login name. Letters, digits, dot, underscore and hyphen.',
    minLength: 3,
    maxLength: 64,
    pattern: '^[a-zA-Z0-9._-]+$',
    example: 'priya.menon',
  })
  @IsString()
  @MinLength(3)
  @MaxLength(64)
  @Matches(/^[a-zA-Z0-9._-]+$/, { message: 'username contains an unsupported character' })
  username!: string;

  @ApiProperty({
    description:
      'Minimum twelve characters. Length beats character-class rules, so there is no symbol requirement pushing users towards a shorter password.',
    minLength: 12,
    maxLength: 128,
    writeOnly: true,
    example: 'correct horse battery staple',
  })
  @IsString()
  @MinLength(12)
  @MaxLength(128)
  password!: string;

  @ApiProperty({
    description: 'The numeric trading account key, `ACCOUNTS.id`, that this user will trade.',
    minimum: 1,
    example: 1,
  })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(Number.MAX_SAFE_INTEGER)
  accountId!: number;

  @ApiPropertyOptional({
    description:
      'Ignored on this route. Public registration always produces `["CUSTOMER"]`. Accepting a self-declared role here is a privilege-escalation bug.',
    enum: Role,
    isArray: true,
    example: [Role.CUSTOMER],
  })
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @IsEnum(Role, { each: true })
  roles?: Role[];
}
