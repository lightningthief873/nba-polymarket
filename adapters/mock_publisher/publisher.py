"""Core publisher logic — separated from CLI so tests can import it directly."""

from __future__ import annotations

import os
import random
import sys
import time

# Make the proto stubs importable: add adapters/proto/ so that
# `nba_polymarket` is a top-level package (matching how pb2 files cross-import).
_HERE = os.path.dirname(os.path.abspath(__file__))
_ADAPTERS = os.path.dirname(_HERE)
_PROTO_DIR = os.path.join(_ADAPTERS, "proto")
for _p in (_PROTO_DIR,):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from nba_polymarket.v1 import common_pb2, market_pb2  # noqa: E402


def build_event(condition_id: str, rng: random.Random) -> market_pb2.MarketEvent:
    """Build a synthetic MarketEvent with a live timestamp_ns."""
    event = market_pb2.MarketEvent()
    event.meta.timestamp_ns = time.time_ns()
    event.meta.source = common_pb2.SOURCE_POLYMARKET_WS
    event.meta.trace_id = f"mock-{rng.randint(0, 0xFFFFFFFF):08x}"
    event.condition_id = condition_id
    event.token_id = f"tok-{condition_id[:8]}"

    mid = rng.uniform(0.20, 0.80)
    half_spread = rng.uniform(0.001, 0.005)

    bid = event.bids.add()
    bid.price = max(0.01, mid - half_spread)
    bid.size = rng.uniform(10.0, 1000.0)

    ask = event.asks.add()
    ask.price = min(0.99, mid + half_spread)
    ask.size = rng.uniform(10.0, 1000.0)

    event.last_trade_price = mid
    event.last_trade_size = rng.uniform(1.0, 100.0)
    return event


class Publisher:
    """ZMQ PUB socket wrapper with rate-controlled publish loop."""

    def __init__(self, socket, rate: float, condition_ids: list[str], seed: int = 42):
        self._socket = socket
        self._rate = rate
        self._condition_ids = condition_ids
        self._rng = random.Random(seed)

    def run(self, duration: float) -> dict:
        """Publish events for `duration` seconds. Returns stats dict."""
        interval = 1.0 / self._rate
        deadline = time.monotonic() + duration
        count = 0
        t_start = time.monotonic()

        while time.monotonic() < deadline:
            cid = self._rng.choice(self._condition_ids)
            event = build_event(cid, self._rng)
            topic = f"market.{cid}".encode()
            self._socket.send_multipart([topic, event.SerializeToString()])
            count += 1

            elapsed = time.monotonic() - t_start
            expected_elapsed = count / self._rate
            slack = expected_elapsed - elapsed
            if slack > 0:
                time.sleep(slack)

        actual = count / max(time.monotonic() - t_start, 1e-9)
        return {"count": count, "rate_actual": actual}
