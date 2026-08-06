import { ApiProperty } from '@nestjs/swagger';
import { ERROR_CODES } from './error-codes';

/**
 * The error envelope, declared as a class so that Swagger can document it.
 *
 * It is never instantiated by the service: `AuthExceptionFilter` builds the
 * response. It exists to make `/docs` show the same shape the filter emits.
 */
export class ErrorResponseDto {
  @ApiProperty({
    description: 'Machine-readable failure code. Clients branch on this, never on the message.',
    enum: Object.values(ERROR_CODES),
    example: ERROR_CODES.UNAUTHORISED,
  })
  errorCode!: string;

  @ApiProperty({
    description: 'Human-readable failure text. Deliberately vague on the authentication paths.',
    example: 'Unauthorised',
  })
  message!: string;
}
