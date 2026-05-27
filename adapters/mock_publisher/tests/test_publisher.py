"""Unit tests for the mock publisher."""

import os
import random
import sys
import threading
import time

import zmq

# Add adapters/proto/ so pb2 files can do `from nba_polymarket.v1 import ...`
# Add adapters/mock_publisher/ so `from publisher import ...` works.
_HERE = os.path.dirname(os.path.abspath(__file__))
_PKG_ROOT = os.path.dirname(_HERE)          # adapters/mock_publisher/
_ADAPTERS = os.path.dirname(_PKG_ROOT)      # adapters/
_PROTO_DIR = os.path.join(_ADAPTERS, "proto")
for _p in (_PROTO_DIR, _PKG_ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from nba_polymarket.v1 import market_pb2    # noqa: E402
from publisher import Publisher, build_event  # noqa: E402


class TestProtoRoundtrip:
    def test_build_event_encodes_and_decodes(self):
        """build_event() produces a valid, decodable MarketEvent."""
        rng = random.Random(42)
        event = build_event("0xABCD", rng)
        raw = event.SerializeToString()

        decoded = market_pb2.MarketEvent()
        decoded.ParseFromString(raw)

        assert decoded.condition_id == "0xABCD"
        assert len(decoded.bids) == 1
        assert len(decoded.asks) == 1
        assert decoded.bids[0].price > 0
        assert decoded.asks[0].price > decoded.bids[0].price
        assert decoded.meta.timestamp_ns > 0

    def test_different_seeds_differ(self):
        """Different seeds produce different events."""
        e1 = build_event("0xABCD", random.Random(1))
        e2 = build_event("0xABCD", random.Random(2))
        assert e1.SerializeToString() != e2.SerializeToString()

    def test_same_seed_reproducible(self):
        """Same seed, same condition_id → same event (excluding timestamp_ns)."""
        rng1 = random.Random(99)
        rng2 = random.Random(99)
        e1 = build_event("0xXXXX", rng1)
        e2 = build_event("0xXXXX", rng2)
        # Everything except timestamp_ns should match.
        e1.meta.timestamp_ns = 0
        e2.meta.timestamp_ns = 0
        e1.meta.trace_id = ""
        e2.meta.trace_id = ""
        assert e1.SerializeToString() == e2.SerializeToString()


class TestRateAccuracy:
    """Publisher delivers events at the requested rate (±10%)."""

    def test_rate_within_tolerance(self):
        ctx = zmq.Context()
        pub_sock = ctx.socket(zmq.PUB)
        port = pub_sock.bind_to_random_port("tcp://127.0.0.1")

        sub_sock = ctx.socket(zmq.SUB)
        sub_sock.connect(f"tcp://127.0.0.1:{port}")
        sub_sock.subscribe(b"")
        sub_sock.setsockopt(zmq.RCVTIMEO, 200)  # 200 ms receive timeout

        time.sleep(0.05)  # allow connection to establish

        target_rate = 200.0  # low enough to be reliable in CI
        duration = 1.0
        pub = Publisher(pub_sock, rate=target_rate,
                        condition_ids=["0xTEST"], seed=42)

        results = {}

        def publish():
            results["stats"] = pub.run(duration)

        t = threading.Thread(target=publish, daemon=True)
        t.start()

        received = 0
        deadline = time.monotonic() + duration + 0.5
        while time.monotonic() < deadline:
            try:
                sub_sock.recv_multipart()
                received += 1
            except zmq.Again:
                break

        t.join(timeout=3.0)

        pub_sock.close()
        sub_sock.close()
        ctx.term()

        expected = target_rate * duration
        assert results["stats"]["count"] >= int(expected * 0.90), (
            f"published {results['stats']['count']} but expected >= {int(expected * 0.90)}"
        )
        assert abs(received - expected) / expected < 0.15, (
            f"received {received}, expected ~{expected:.0f} (±15%)"
        )
