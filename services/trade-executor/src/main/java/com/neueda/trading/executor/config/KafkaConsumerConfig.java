package com.neueda.trading.executor.config;

import com.neueda.trading.executor.messaging.NonRetryableMessageException;
import org.apache.kafka.common.TopicPartition;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.util.backoff.ExponentialBackOff;

/**
 * Retry and dead-letter policy for the {@code orders} consumer.
 *
 * <p>Two failure classes are handled differently, which is the point of the configuration. A
 * malformed or unprocessable message will fail the same way for ever, so it is dead-lettered on the
 * first attempt. A transient failure, a Fauxnance timeout or a database that is briefly
 * unreachable, is retried with exponential backoff and only dead-lettered once the budget is spent.
 * Retrying a poison message indefinitely stops the partition, and with it every account keyed to
 * that partition.
 */
@Configuration
public class KafkaConsumerConfig {

    private static final Logger log = LoggerFactory.getLogger(KafkaConsumerConfig.class);

    @Bean
    DefaultErrorHandler kafkaErrorHandler(KafkaTemplate<String, String> kafkaTemplate,
                                          ExecutorProperties properties) {
        String suffix = properties.getTopics().getDeadLetterSuffix();

        DeadLetterPublishingRecoverer recoverer = new DeadLetterPublishingRecoverer(
                kafkaTemplate,
                // Partition -1 lets the broker choose, so the dead-letter topic does not have to
                // have as many partitions as its source.
                (record, exception) -> new TopicPartition(record.topic() + suffix, -1));

        ExponentialBackOff backOff = new ExponentialBackOff();
        backOff.setInitialInterval(500L);
        backOff.setMultiplier(2.0);
        backOff.setMaxInterval(10_000L);
        // Bound the retries by count, not by elapsed time. A budget expressed in seconds is a
        // budget that changes meaning the moment the backoff intervals change.
        backOff.setMaxAttempts(Math.max(0, properties.getMaxDeliveryAttempts() - 1));
        backOff.setMaxElapsedTime(Long.MAX_VALUE);

        DefaultErrorHandler handler = new DefaultErrorHandler(recoverer, backOff);
        handler.addNotRetryableExceptions(NonRetryableMessageException.class);
        handler.setLogLevel(org.springframework.kafka.KafkaException.Level.WARN);
        log.info("Dead-letter topic suffix {}, {} delivery attempts per message",
                suffix, properties.getMaxDeliveryAttempts());
        return handler;
    }
}
