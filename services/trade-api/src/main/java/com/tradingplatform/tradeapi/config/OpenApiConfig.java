package com.tradingplatform.tradeapi.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * The live API description, served at {@code /swagger-ui}.
 *
 * <p>The authority is {@code docs/contracts/trade-api.yaml}. The Angular UI generates its typed
 * client from that file, so a field renamed there is a compile error in the UI. What springdoc
 * publishes here is generated from the running code, which makes it useful for a different reason:
 * where the two disagree, the code has drifted from the contract and the difference is visible
 * without reading either.
 *
 * <p>Do not treat the generated document as the contract and do not hand-edit it into agreement.
 * Fix the code.
 */
@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI tradeApiDefinition() {
        SecurityScheme bearer = new SecurityScheme()
                .type(SecurityScheme.Type.HTTP)
                .scheme("bearer")
                .bearerFormat("JWT")
                .description("An access token issued by the auth service, or by the Node auth stub "
                        + "in Sprints 6 and 7. The claims contract is in contracts/auth-api.yaml.");

        return new OpenAPI()
                .info(new Info()
                        .title("Trade REST API")
                        .version("1.0.0")
                        .description("Order placement, order cancellation and account queries for "
                                + "the Enterprise Trading Platform. The binding contract is "
                                + "docs/contracts/trade-api.yaml.")
                        .license(new License().name("Instructional use only")))
                .components(new Components().addSecuritySchemes("bearerAuth", bearer))
                .addSecurityItem(new SecurityRequirement().addList("bearerAuth"));
    }
}
