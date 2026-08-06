package com.tradingplatform.domain.model;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static com.tradingplatform.domain.TestFixtures.instrument;
import static com.tradingplatform.domain.TestFixtures.suspendedInstrument;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

@DisplayName("Instrument")
class InstrumentTest {

    @Test
    void testIsTradable_TradableInstrument() {
        assertTrue(instrument().isTradable());
    }

    @Test
    @DisplayName("business rule 3: a suspended instrument is not tradable")
    void testIsTradable_SuspendedInstrument() {
        assertFalse(suspendedInstrument().isTradable());
    }

    @Test
    @DisplayName("trading is suspended by clearing the flag, never by deleting the row")
    void testSetTradableSuspendsAndResumes() {
        Instrument instrument = instrument();

        instrument.setTradable(false);
        assertFalse(instrument.isTradable());

        instrument.setTradable(true);
        assertTrue(instrument.isTradable());
    }

    @Test
    @DisplayName("the symbol is the identity, so two rows with one symbol are one instrument")
    void testEqualityIsBySymbol() {
        Instrument tradable = new Instrument("AAPL", "Apple Inc", "EQUITY", "USD", true);
        Instrument suspended = new Instrument("AAPL", "Apple Inc", "EQUITY", "USD", false);
        Instrument other = new Instrument("INFY.NS", "Infosys", "EQUITY", "INR", true);

        assertTrue(tradable.equals(suspended));
        assertNotEquals(tradable, other);
    }

    @Test
    void testSymbolIsRequired() {
        assertThrows(NullPointerException.class,
                () -> new Instrument(null, "Apple Inc", "EQUITY", "USD", true));
    }
}
