import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Role } from '../role.enum';
import { UserRecord } from '../user.entity';

/**
 * The user as a client sees it. Returned by `POST /auth/register` and
 * `GET /auth/me`.
 *
 * There is no password field and no hash field, and there is no code path that
 * could add one, because this object is built column by column from the record
 * rather than spread from it.
 */
export class UserResponseDto {
  @ApiProperty({
    format: 'uuid',
    description: 'The value carried in the `sub` claim.',
    example: '8f14e45f-ceea-4c1b-9d3b-1a2b3c4d5e6f',
  })
  id!: string;

  @ApiProperty({ example: 'priya.menon' })
  username!: string;

  @ApiProperty({ description: 'The numeric trading account key, `ACCOUNTS.id`.', example: 1 })
  accountId!: number;

  @ApiProperty({ enum: Role, isArray: true, example: [Role.CUSTOMER] })
  roles!: Role[];

  @ApiPropertyOptional({ format: 'date-time', example: '2026-10-05T08:00:00Z' })
  createdOn?: string;

  static from(user: UserRecord): UserResponseDto {
    const dto = new UserResponseDto();
    dto.id = user.id;
    dto.username = user.username;
    dto.accountId = user.accountId;
    dto.roles = user.roles;
    dto.createdOn = user.createdOn instanceof Date ? user.createdOn.toISOString() : user.createdOn;
    return dto;
  }
}
