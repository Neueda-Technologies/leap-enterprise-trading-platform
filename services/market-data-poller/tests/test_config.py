from __future__ import annotations

import pytest

from market_data_poller.config import (
    MINIMUM_POLL_INTERVAL_SECONDS,
    ConfigurationError,
    Settings,
    parse_symbols,
)


def test_only_the_api_key_is_required():
    settings = Settings.from_env({"FAUXNANCE_API_KEY": "k"})

    assert settings.symbols == ("AAPL", "MSFT", "GOOGL", "AMZN", "TSLA", "NVDA", "JPM", "SPY")
    assert settings.poll_interval_seconds == 30.0
    assert settings.topic == "market-data"
    assert settings.daily_request_budget == 2000
    assert settings.health_port == 8083


def test_a_missing_api_key_stops_the_process_at_start_up():
    with pytest.raises(ConfigurationError):
        Settings.from_env({})


def test_a_blank_api_key_is_treated_as_missing():
    with pytest.raises(ConfigurationError):
        Settings.from_env({"FAUXNANCE_API_KEY": "   "})


def test_symbols_are_trimmed_upper_cased_and_deduplicated_in_order():
    assert parse_symbols(" aapl , MSFT ,, aapl , infy.ns ") == ("AAPL", "MSFT", "INFY.NS")


def test_an_empty_symbol_list_stops_the_process():
    with pytest.raises(ConfigurationError):
        Settings.from_env({"FAUXNANCE_API_KEY": "k", "MARKET_DATA_SYMBOLS": " , ,"})


def test_the_poll_interval_is_raised_to_the_floor():
    settings = Settings.from_env({"FAUXNANCE_API_KEY": "k", "POLL_INTERVAL_SECONDS": "1"})

    assert settings.poll_interval_seconds == MINIMUM_POLL_INTERVAL_SECONDS


def test_an_interval_above_the_floor_is_kept():
    settings = Settings.from_env({"FAUXNANCE_API_KEY": "k", "POLL_INTERVAL_SECONDS": "60"})

    assert settings.poll_interval_seconds == 60.0


def test_a_non_numeric_setting_names_itself_in_the_error():
    with pytest.raises(ConfigurationError, match="HEALTH_PORT"):
        Settings.from_env({"FAUXNANCE_API_KEY": "k", "HEALTH_PORT": "eighty-eighty-three"})


def test_the_trailing_slash_on_the_base_url_is_dropped():
    settings = Settings.from_env(
        {"FAUXNANCE_API_KEY": "k", "FAUXNANCE_BASE_URL": "https://example.test/v1/"}
    )

    assert settings.base_url == "https://example.test/v1"


def test_requests_per_poll_counts_batches_not_symbols():
    eight = Settings.from_env({"FAUXNANCE_API_KEY": "k"})
    assert eight.requests_per_poll == 1

    thirty = Settings.from_env(
        {
            "FAUXNANCE_API_KEY": "k",
            "MARKET_DATA_SYMBOLS": ",".join(f"SYM{i}" for i in range(30)),
        }
    )
    assert thirty.requests_per_poll == 2
